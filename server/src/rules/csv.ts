/**
 * A small RFC 4180 CSV parser (port of CellarKit's CSVParser).
 *
 * Handles quoted fields, escaped quotes (`""`), commas and line breaks inside
 * quotes, and `\n`, `\r\n` or `\r` row endings. Completely empty lines are
 * skipped, and stray quotes are kept rather than rejected.
 */
export function parseCSV(input: string): string[][] {
  const text = input.startsWith("﻿") ? input.slice(1) : input;
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;
  let fieldWasQuoted = false;

  const endField = () => {
    row.push(field);
    field = "";
    fieldWasQuoted = false;
  };
  const endRow = () => {
    // Skip blank lines: nothing at all on the line, not even `""`.
    const isBlankLine = row.length === 0 && field === "" && !fieldWasQuoted;
    endField();
    if (!isBlankLine) rows.push(row);
    row = [];
  };

  let i = 0;
  while (i < text.length) {
    const c = text[i];
    const next = i + 1 < text.length ? text[i + 1] : undefined;

    if (inQuotes) {
      if (c === '"') {
        if (next === '"') {
          field += '"'; // Escaped quote.
          i += 2;
          continue;
        }
        if (next === undefined || next === "," || next === "\n" || next === "\r") {
          inQuotes = false; // Closing quote.
        } else {
          field += c; // Lenient: an unescaped quote mid-field is literal.
        }
      } else {
        field += c;
      }
    } else if (c === '"' && field === "" && !fieldWasQuoted) {
      inQuotes = true;
      fieldWasQuoted = true;
    } else if (c === ",") {
      endField();
    } else if (c === "\n") {
      endRow();
    } else if (c === "\r") {
      endRow();
      if (next === "\n") {
        i += 2;
        continue;
      }
    } else {
      field += c; // Lenient: a stray quote in an unquoted field is kept.
    }
    i += 1;
  }

  // Last row without a trailing newline.
  if (field !== "" || row.length > 0 || fieldWasQuoted) endRow();
  return rows;
}

/** Parses CSV and maps each data row to an object keyed by the header row. */
export function parseCSVRecords(text: string): { header: string[]; records: Record<string, string>[] } {
  const rows = parseCSV(text);
  const header = rows[0];
  if (!header) return { header: [], records: [] };
  const records = rows.slice(1).map((fields) => {
    const record: Record<string, string> = {};
    header.forEach((name, i) => {
      record[name] = fields[i] ?? "";
    });
    return record;
  });
  return { header, records };
}
