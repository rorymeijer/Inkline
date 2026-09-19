import AppKit
import SwiftUI

/// Small helper for the windows that are not documents: compare, the plugin
/// manager, macros and About. Each gets one window, reused on every invocation.
@MainActor
enum AuxiliaryWindow {

    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(identifier: String,
                                    title: String,
                                    size: NSSize = NSSize(width: 760, height: 460),
                                    @ViewBuilder content: () -> Content) {
        if let existing = windows[identifier] {
            // Replace the content so a second "Vergelijken…" shows the new diff
            // instead of the previous one.
            existing.contentViewController = NSHostingController(rootView: content())
            existing.title = title
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.setContentSize(size)
        window.styleMask.insert([.resizable, .miniaturizable, .closable, .titled])
        window.center()
        window.isReleasedWhenClosed = false
        windows[identifier] = window
        window.makeKeyAndOrderFront(nil)
    }

    static func close(identifier: String) {
        windows[identifier]?.close()
        windows.removeValue(forKey: identifier)
    }
}

@MainActor
enum DiffWindowController {
    static func show(model: DiffModel, environment: AppEnvironment) {
        AuxiliaryWindow.show(identifier: "diff",
                             title: NSLocalizedString("Vergelijken", comment: "Venstertitel")) {
            DiffView(model: model, environment: environment)
        }
    }
}
