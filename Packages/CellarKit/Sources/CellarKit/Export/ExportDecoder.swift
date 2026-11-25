import Foundation

/// Errors from turning a CellarTracker export response into records.
public enum ExportError: Error, Equatable, Sendable {
    /// CellarTracker returned its "not logged in" HTML page (bad credentials).
    /// Note that it does this with HTTP 200.
    case notLoggedIn
    /// CellarTracker returned some other HTML page instead of CSV.
    case unexpectedHTML
    /// The bytes couldn't be decoded as text.
    case undecodableText
    /// The CSV has no header row, or is missing the columns we need.
    case missingColumns([String])
}

/// Decodes the raw bytes of a CellarTracker `xlquery.asp` CSV export.
public enum ExportDecoder {
    static let notLoggedInMarker = "You are currently not logged into CellarTracker"
    static let requiredColumns = ["iWine", "Wine"]

    /// Decodes response bytes to text.
    ///
    /// CellarTracker serves windows-1252 rather than UTF-8. If the
    /// `Content-Type` header names a charset we use it. Without one (for
    /// example a file saved from a browser) we accept the bytes as UTF-8 only
    /// if they are valid UTF-8, and otherwise fall back to windows-1252.
    public static func decodeText(_ data: Data, contentType: String? = nil) throws -> String {
        let declared = contentType.flatMap(charset(fromContentType:))
        let windows1252 = String.Encoding.windowsCP1252

        switch declared {
        case "utf-8", "utf8":
            if let text = String(data: data, encoding: .utf8) { return text }
        case "windows-1252", "cp1252", "iso-8859-1", "latin1", "us-ascii":
            if let text = String(data: data, encoding: windows1252) { return text }
        default:
            if let text = String(data: data, encoding: .utf8) { return text }
        }
        if let text = String(data: data, encoding: windows1252) { return text }
        throw ExportError.undecodableText
    }

    /// Extracts a lowercased charset name from a `Content-Type` header value.
    static func charset(fromContentType contentType: String) -> String? {
        for part in contentType.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset"
            else { continue }
            return pair[1]
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
                .lowercased()
        }
        return nil
    }

    /// Decodes response bytes into bottle records, detecting the HTML pages
    /// CellarTracker returns instead of CSV on errors.
    public static func decodeBottles(_ data: Data, contentType: String? = nil) throws -> [BottleRecord] {
        let text = try decodeText(data, contentType: contentType)
        return try parseBottles(text)
    }

    /// Parses decoded CSV text into bottle records.
    public static func parseBottles(_ text: String) throws -> [BottleRecord] {
        let trimmed = text.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
        if trimmed.first == "<" {
            if trimmed.contains(notLoggedInMarker) { throw ExportError.notLoggedIn }
            throw ExportError.unexpectedHTML
        }

        let (header, records) = CSVParser.parseRecords(text)
        let missing = requiredColumns.filter { !header.contains($0) }
        if !missing.isEmpty { throw ExportError.missingColumns(missing) }

        return records.compactMap(BottleRecord.init(row:))
    }
}
