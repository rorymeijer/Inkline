import Foundation

/// Result of sniffing a file's bytes.
public struct EncodingDetection: Equatable, Sendable {
    public enum Confidence: Int, Comparable, Sendable {
        case low, medium, high, certain

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let encoding: TextEncoding
    public let confidence: Confidence
    /// Number of leading bytes that belong to a BOM and must be skipped.
    public let byteOrderMarkLength: Int
    public let looksBinary: Bool

    public init(encoding: TextEncoding,
                confidence: Confidence,
                byteOrderMarkLength: Int = 0,
                looksBinary: Bool = false) {
        self.encoding = encoding
        self.confidence = confidence
        self.byteOrderMarkLength = byteOrderMarkLength
        self.looksBinary = looksBinary
    }
}

/// Byte-order marks first, then a strict UTF-8 validation, then heuristics for
/// BOM-less UTF-16, and finally a single-byte fallback. Same order of
/// preference as every other editor, which matters: users compare.
public enum EncodingDetector {

    /// How many bytes are inspected for the heuristics. Enough to be reliable,
    /// small enough that opening a 100 MB file stays instant.
    public static let sampleSize = 64 * 1024

    public static func detect(_ data: Data, fallback: TextEncoding = .utf8) -> EncodingDetection {
        if let bom = detectByteOrderMark(data) { return bom }

        let sample = data.prefix(sampleSize)
        guard !sample.isEmpty else {
            return EncodingDetection(encoding: .utf8, confidence: .certain)
        }

        if let utf16 = detectBOMlessUTF16(sample) { return utf16 }

        let binary = looksBinary(sample)

        if isValidUTF8(sample, allowTruncatedTail: data.count > sampleSize) {
            let isASCII = sample.allSatisfy { $0 < 0x80 }
            return EncodingDetection(encoding: .utf8,
                                     confidence: isASCII ? .medium : .high,
                                     looksBinary: binary)
        }

        // Not UTF-8: a single byte encoding. Windows-1252 is the pragmatic
        // choice — it is a superset of Latin-1 for the printable range and
        // covers the smart quotes that plague "Latin-1" files in the wild.
        return EncodingDetection(encoding: fallback == .utf8 ? .windowsCP1252 : fallback,
                                 confidence: .low,
                                 looksBinary: binary)
    }

    public static func detectByteOrderMark(_ data: Data) -> EncodingDetection? {
        let bytes = [UInt8](data.prefix(4))
        func matches(_ prefix: [UInt8]) -> Bool {
            bytes.count >= prefix.count && Array(bytes.prefix(prefix.count)) == prefix
        }
        // UTF-32 must be tested before UTF-16: FF FE 00 00 starts like UTF-16 LE.
        if matches([0xFF, 0xFE, 0x00, 0x00]) {
            return EncodingDetection(encoding: .utf32LEWithBOM, confidence: .certain, byteOrderMarkLength: 4)
        }
        if matches([0x00, 0x00, 0xFE, 0xFF]) {
            return EncodingDetection(encoding: .utf32BEWithBOM, confidence: .certain, byteOrderMarkLength: 4)
        }
        if matches([0xEF, 0xBB, 0xBF]) {
            return EncodingDetection(encoding: .utf8BOM, confidence: .certain, byteOrderMarkLength: 3)
        }
        if matches([0xFF, 0xFE]) {
            return EncodingDetection(encoding: .utf16LEWithBOM, confidence: .certain, byteOrderMarkLength: 2)
        }
        if matches([0xFE, 0xFF]) {
            return EncodingDetection(encoding: .utf16BEWithBOM, confidence: .certain, byteOrderMarkLength: 2)
        }
        return nil
    }

    /// BOM-less UTF-16 shows up as a strong pattern of NUL bytes in either the
    /// even or the odd positions (Latin text in UTF-16 is "A\0B\0…").
    static func detectBOMlessUTF16(_ sample: Data) -> EncodingDetection? {
        let bytes = [UInt8](sample)
        guard bytes.count >= 16 else { return nil }
        var evenNulls = 0
        var oddNulls = 0
        let limit = min(bytes.count, 4096) & ~1
        for index in 0..<limit where bytes[index] == 0 {
            if index % 2 == 0 { evenNulls += 1 } else { oddNulls += 1 }
        }
        let pairs = limit / 2
        guard pairs > 0 else { return nil }
        let threshold = Int(Double(pairs) * 0.7)
        if oddNulls >= threshold && evenNulls < pairs / 8 {
            return EncodingDetection(encoding: .utf16LE, confidence: .medium)
        }
        if evenNulls >= threshold && oddNulls < pairs / 8 {
            return EncodingDetection(encoding: .utf16BE, confidence: .medium)
        }
        return nil
    }

    /// Strict UTF-8 validation. When the sample is a prefix of a larger file a
    /// multi-byte sequence may be cut in half; `allowTruncatedTail` tolerates
    /// that instead of misdetecting a big UTF-8 file as Windows-1252.
    public static func isValidUTF8(_ data: Data, allowTruncatedTail: Bool = false) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            var continuationCount = 0
            if byte < 0x80 {
                index += 1
                continue
            } else if byte >= 0xC2 && byte <= 0xDF {
                continuationCount = 1
            } else if byte >= 0xE0 && byte <= 0xEF {
                continuationCount = 2
            } else if byte >= 0xF0 && byte <= 0xF4 {
                continuationCount = 3
            } else {
                return false                        // 0x80…0xC1 and 0xF5…0xFF
            }
            if index + continuationCount >= bytes.count {
                return allowTruncatedTail
            }
            for offset in 1...continuationCount {
                let continuation = bytes[index + offset]
                guard continuation >= 0x80 && continuation <= 0xBF else { return false }
            }
            // Reject overlong forms and surrogates.
            if byte == 0xE0 && bytes[index + 1] < 0xA0 { return false }
            if byte == 0xED && bytes[index + 1] > 0x9F { return false }
            if byte == 0xF0 && bytes[index + 1] < 0x90 { return false }
            if byte == 0xF4 && bytes[index + 1] > 0x8F { return false }
            index += continuationCount + 1
        }
        return true
    }

    /// A NUL byte outside a UTF-16 pattern is the classic "this is not text"
    /// signal; Inkline warns before opening such a file in the text editor.
    public static func looksBinary(_ data: Data) -> Bool {
        data.prefix(8192).contains(0x00)
    }
}
