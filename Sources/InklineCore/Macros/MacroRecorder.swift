import Foundation

/// Collects actions while recording. The editor calls `record(_:)` from the
/// places where it performs an action, which is the only invasive part of the
/// macro system — everything else works off the recorded value type.
public final class MacroRecorder {

    public private(set) var isRecording = false
    public private(set) var isPaused = false
    public private(set) var actions: [MacroAction] = []

    public var onChange: ((MacroRecorder) -> Void)?

    public init() {}

    public func start() {
        actions.removeAll()
        isRecording = true
        isPaused = false
        onChange?(self)
    }

    public func pause() {
        guard isRecording else { return }
        isPaused = true
        onChange?(self)
    }

    public func resume() {
        guard isRecording else { return }
        isPaused = false
        onChange?(self)
    }

    /// Ends recording and returns the macro, or `nil` when nothing was
    /// recorded.
    @discardableResult
    public func stop(name: String = "") -> Macro? {
        guard isRecording else { return nil }
        isRecording = false
        isPaused = false
        defer { onChange?(self) }
        guard !actions.isEmpty else { return nil }
        return Macro(name: name.isEmpty ? Self.defaultName() : name, actions: actions)
    }

    public func record(_ action: MacroAction) {
        guard isRecording, !isPaused else { return }
        // Consecutive typing collapses into one insert: shorter macros, and
        // replay that does not fight the undo coalescer.
        if case let .insertText(text) = action,
           case let .insertText(previous)? = actions.last {
            actions[actions.count - 1] = .insertText(previous + text)
        } else {
            actions.append(action)
        }
        onChange?(self)
    }

    public func discard() {
        actions.removeAll()
        isRecording = false
        isPaused = false
        onChange?(self)
    }

    static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Macro \(formatter.string(from: Date()))"
    }
}

/// What a macro is replayed against. The editor implements this; the tests
/// implement it over a plain `TextBuffer`, which is how the macro system is
/// covered without a running app.
public protocol MacroExecutionTarget: AnyObject {
    func perform(_ action: MacroAction) throws
    /// Used by `.untilEndOfDocument` to know when to stop.
    var caretOffset: Int { get }
    var documentLength: Int { get }
}

public enum MacroPlaybackError: LocalizedError, Equatable {
    case unsupportedAction(String)
    case noMatch

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAction(description): return "Actie wordt niet ondersteund: \(description)"
        case .noMatch: return "Geen resultaat meer gevonden."
        }
    }
}

public enum MacroPlayer {

    /// Replays `macro` on `target`. Stops early when an iteration makes no
    /// progress, which is what makes `.untilEndOfDocument` terminate on a macro
    /// whose search no longer matches.
    @discardableResult
    public static func play(_ macro: Macro,
                            on target: MacroExecutionTarget,
                            repeatMode: MacroRepeatMode = .once) throws -> Int {
        var iterations = 0
        let limit = repeatMode.maximumIterations

        while iterations < limit {
            let caretBefore = target.caretOffset
            let lengthBefore = target.documentLength

            do {
                for action in macro.actions {
                    try target.perform(action)
                }
            } catch MacroPlaybackError.noMatch where repeatMode == .untilEndOfDocument {
                break
            }
            iterations += 1

            if case .untilEndOfDocument = repeatMode {
                let madeProgress = target.caretOffset != caretBefore || target.documentLength != lengthBefore
                if !madeProgress { break }
                if target.caretOffset >= target.documentLength { break }
            }
        }
        return iterations
    }
}
