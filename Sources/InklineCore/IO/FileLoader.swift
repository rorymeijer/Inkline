import Foundation

public struct LoadedDocument: Sendable {
    /// Text with all line terminators normalised to LF.
    public let text: String
    public let encoding: TextEncoding
    public let lineEnding: LineEnding
    public let hasMixedLineEndings: Bool
    public let byteCount: Int
    public let modificationDate: Date?
    public let looksBinary: Bool
    public let detectionConfidence: EncodingDetection.Confidence
}

public struct SaveOptions: Codable, Sendable, Equatable {
    public var trimTrailingWhitespace: Bool
    public var ensureTrailingNewline: Bool

    public init(trimTrailingWhitespace: Bool = false, ensureTrailingNewline: Bool = false) {
        self.trimTrailingWhitespace = trimTrailingWhitespace
        self.ensureTrailingNewline = ensureTrailingNewline
    }

    public static let `default` = SaveOptions()
}

public enum FileIOError: LocalizedError, Equatable {
    case tooLarge(byteCount: Int, limit: Int)
    case decodingFailed(TextEncoding)
    case encodingFailed(TextEncoding)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(byteCount, limit):
            return "Het bestand is \(byteCount) bytes groot; de limiet is \(limit) bytes."
        case let .decodingFailed(encoding):
            return "Het bestand kon niet als \(encoding.displayName) worden gelezen."
        case let .encodingFailed(encoding):
            return "De tekst bevat tekens die niet in \(encoding.displayName) passen."
        }
    }
}

/// Reading and writing text files: encoding detection, BOM handling and line
/// ending conversion in one place, so the rest of the app only ever sees
/// LF-normalised `String`s.
public enum FileLoader {

    /// Refuse to open anything larger than this in the text editor (the hex
    /// viewer plugin handles the rest). 512 MB is far beyond the ~100 MB the
    /// editor is tuned for, but still a guard against opening a disk image.
    public static let defaultSizeLimit = 512 * 1024 * 1024

    public static func load(contentsOf url: URL,
                            forcedEncoding: TextEncoding? = nil,
                            sizeLimit: Int = defaultSizeLimit) throws -> LoadedDocument {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= sizeLimit else {
            throw FileIOError.tooLarge(byteCount: data.count, limit: sizeLimit)
        }
        return try decode(data, forcedEncoding: forcedEncoding, modificationDate: modificationDate)
    }

    public static func decode(_ data: Data,
                              forcedEncoding: TextEncoding? = nil,
                              modificationDate: Date? = nil) throws -> LoadedDocument {
        let detection: EncodingDetection
        if let forcedEncoding {
            let bomLength = EncodingDetector.detectByteOrderMark(data)?.byteOrderMarkLength ?? 0
            detection = EncodingDetection(encoding: forcedEncoding,
                                          confidence: .certain,
                                          byteOrderMarkLength: forcedEncoding.hasBOM ? bomLength : 0,
                                          looksBinary: EncodingDetector.looksBinary(data))
        } else {
            detection = EncodingDetector.detect(data)
        }

        let payload = detection.byteOrderMarkLength > 0
            ? data.subdata(in: detection.byteOrderMarkLength..<data.count)
            : data

        guard var text = String(data: payload, encoding: detection.encoding.stringEncoding) else {
            // Last resort: Windows-1252 maps every byte, so this always succeeds
            // and the user can re-open with the right encoding from the menu.
            guard let recovered = String(data: payload, encoding: .windowsCP1252) else {
                throw FileIOError.decodingFailed(detection.encoding)
            }
            let statistics = LineEnding.statistics(of: recovered)
            return LoadedDocument(text: LineEnding.normalize(recovered),
                                  encoding: .windowsCP1252,
                                  lineEnding: statistics.dominant ?? .lf,
                                  hasMixedLineEndings: statistics.isMixed,
                                  byteCount: data.count,
                                  modificationDate: modificationDate,
                                  looksBinary: detection.looksBinary,
                                  detectionConfidence: .low)
        }

        let statistics = LineEnding.statistics(of: text)
        text = LineEnding.normalize(text)
        return LoadedDocument(text: text,
                              encoding: detection.encoding,
                              lineEnding: statistics.dominant ?? .lf,
                              hasMixedLineEndings: statistics.isMixed,
                              byteCount: data.count,
                              modificationDate: modificationDate,
                              looksBinary: detection.looksBinary,
                              detectionConfidence: detection.confidence)
    }

    /// Turns LF-normalised buffer text into the bytes that go to disk.
    public static func encode(_ text: String,
                              encoding: TextEncoding,
                              lineEnding: LineEnding,
                              options: SaveOptions = .default) throws -> Data {
        var output = text
        if options.trimTrailingWhitespace {
            output = TextTransforms.trimTrailingWhitespace(output)
        }
        if options.ensureTrailingNewline, !output.isEmpty, !output.hasSuffix("\n") {
            output += "\n"
        }
        output = lineEnding.applied(to: output)

        guard let body = output.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            throw FileIOError.encodingFailed(encoding)
        }
        if let bom = encoding.byteOrderMark {
            var data = Data(bom)
            data.append(body)
            return data
        }
        return body
    }

    public static func write(_ text: String,
                             to url: URL,
                             encoding: TextEncoding,
                             lineEnding: LineEnding,
                             options: SaveOptions = .default) throws {
        let data = try encode(text, encoding: encoding, lineEnding: lineEnding, options: options)
        try data.write(to: url, options: [.atomic])
    }

    /// Cheap "did someone else change this file?" check for the tab's
    /// reload prompt.
    public static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public static func byteCount(of url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue
    }
}
