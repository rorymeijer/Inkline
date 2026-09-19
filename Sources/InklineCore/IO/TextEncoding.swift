import Foundation

/// The encodings Inkline can read and write. A closed enum (rather than raw
/// `String.Encoding` values) keeps sessions and preferences round-trippable and
/// gives the Encoding menu a stable order.
public enum TextEncoding: String, CaseIterable, Codable, Sendable {
    case utf8
    case utf8BOM
    case utf16LE
    case utf16BE
    case utf16LEWithBOM
    case utf16BEWithBOM
    case utf32LEWithBOM
    case utf32BEWithBOM
    case isoLatin1
    case isoLatin2
    case windowsCP1252
    case macRoman
    case ascii
    case shiftJIS
    case windowsCP1251

    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE, .utf16LEWithBOM: return .utf16LittleEndian
        case .utf16BE, .utf16BEWithBOM: return .utf16BigEndian
        case .utf32LEWithBOM: return .utf32LittleEndian
        case .utf32BEWithBOM: return .utf32BigEndian
        case .isoLatin1: return .isoLatin1
        case .isoLatin2: return .isoLatin2
        case .windowsCP1252: return .windowsCP1252
        case .macRoman: return .macOSRoman
        case .ascii: return .ascii
        case .shiftJIS: return .shiftJIS
        case .windowsCP1251: return .windowsCP1251
        }
    }

    public var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 met BOM"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .utf16LEWithBOM: return "UTF-16 LE met BOM"
        case .utf16BEWithBOM: return "UTF-16 BE met BOM"
        case .utf32LEWithBOM: return "UTF-32 LE met BOM"
        case .utf32BEWithBOM: return "UTF-32 BE met BOM"
        case .isoLatin1: return "ISO-8859-1 (Latin-1)"
        case .isoLatin2: return "ISO-8859-2 (Latin-2)"
        case .windowsCP1252: return "Windows-1252"
        case .macRoman: return "Mac OS Roman"
        case .ascii: return "ASCII"
        case .shiftJIS: return "Shift JIS"
        case .windowsCP1251: return "Windows-1251 (Cyrillisch)"
        }
    }

    /// Byte order mark written in front of the encoded text, if any.
    public var byteOrderMark: [UInt8]? {
        switch self {
        case .utf8BOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LEWithBOM: return [0xFF, 0xFE]
        case .utf16BEWithBOM: return [0xFE, 0xFF]
        case .utf32LEWithBOM: return [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BEWithBOM: return [0x00, 0x00, 0xFE, 0xFF]
        default: return nil
        }
    }

    public var hasBOM: Bool { byteOrderMark != nil }

    /// The same encoding with or without a BOM, where that makes sense.
    public func withBOM(_ wanted: Bool) -> TextEncoding {
        switch (self, wanted) {
        case (.utf8, true): return .utf8BOM
        case (.utf8BOM, false): return .utf8
        case (.utf16LE, true): return .utf16LEWithBOM
        case (.utf16LEWithBOM, false): return .utf16LE
        case (.utf16BE, true): return .utf16BEWithBOM
        case (.utf16BEWithBOM, false): return .utf16BE
        default: return self
        }
    }

    /// Encodings offered in the Encoding menu, in menu order.
    public static let menuOrder: [TextEncoding] = [
        .utf8, .utf8BOM, .utf16LEWithBOM, .utf16BEWithBOM, .utf16LE, .utf16BE,
        .utf32LEWithBOM, .utf32BEWithBOM,
        .isoLatin1, .isoLatin2, .windowsCP1252, .macRoman, .ascii, .shiftJIS, .windowsCP1251
    ]
}
