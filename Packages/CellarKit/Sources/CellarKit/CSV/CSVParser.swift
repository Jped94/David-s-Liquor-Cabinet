/// A small RFC 4180 CSV parser.
///
/// Handles quoted fields, escaped quotes (`""`), commas and line breaks
/// inside quotes, and `\n`, `\r\n` or `\r` row endings. It works on Unicode
/// scalars rather than `Character`s, because Swift treats `"\r\n"` as a single
/// `Character`, which would break row splitting.
public enum CSVParser {
    /// Parses `text` into rows of fields. Completely empty lines are skipped.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldWasQuoted = false

        let quote: Unicode.Scalar = "\""
        let comma: Unicode.Scalar = ","
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"
        let bom: Unicode.Scalar = "\u{FEFF}"

        var scalars = text.unicodeScalars[...]
        if scalars.first == bom { scalars = scalars.dropFirst() }

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }

        func endRow() {
            // Skip blank lines: nothing at all on the line, not even `""`.
            let isBlankLine = row.isEmpty && field.isEmpty && !fieldWasQuoted
            endField()
            if !isBlankLine { rows.append(row) }
            row = []
        }

        var index = scalars.startIndex
        while index < scalars.endIndex {
            let c = scalars[index]
            let next = scalars.index(after: index)

            if inQuotes {
                if c == quote {
                    let following: Unicode.Scalar? = next < scalars.endIndex ? scalars[next] : nil
                    if following == quote {
                        field.append(quote) // Escaped quote.
                        index = scalars.index(after: next)
                        continue
                    }
                    if following == nil || following == comma || following == lf || following == cr {
                        inQuotes = false // Closing quote.
                    } else {
                        // Lenient: an unescaped quote in the middle of a quoted
                        // field (e.g. `"12" Barrel"`) is kept as a literal.
                        field.append(c)
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case quote where field.isEmpty && !fieldWasQuoted:
                    inQuotes = true
                    fieldWasQuoted = true
                case comma:
                    endField()
                case lf:
                    endRow()
                case cr:
                    endRow()
                    if next < scalars.endIndex, scalars[next] == lf {
                        index = scalars.index(after: next)
                        continue
                    }
                default:
                    // Lenient: a stray quote in an unquoted field is kept as-is.
                    field.append(c)
                }
            }
            index = next
        }

        // Last row without a trailing newline.
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted {
            endRow()
        }
        return rows
    }

    /// Parses `text` and maps each data row to a dictionary keyed by the
    /// header row. Missing trailing fields become empty strings.
    public static func parseRecords(_ text: String) -> (header: [String], records: [[String: String]]) {
        let rows = parse(text)
        guard let header = rows.first else { return ([], []) }
        let records = rows.dropFirst().map { fields -> [String: String] in
            var record: [String: String] = [:]
            record.reserveCapacity(header.count)
            for (i, name) in header.enumerated() {
                record[name] = i < fields.count ? fields[i] : ""
            }
            return record
        }
        return (header, records)
    }
}
