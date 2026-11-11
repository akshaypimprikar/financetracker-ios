# Incidents — past bugs and their root causes (append via /bugfix)

## 2026-11-11 — CSV import truncated comma amounts (#189)
**Symptom:** CSV amounts like `12,50` or `1,234.56` imported as 12 or 1, with no error; the row's `importHash` was built from the wrong amount.
**Root cause:** `Decimal(string:)` parses the longest valid prefix and silently drops the rest.
**Fix:** `CSVImportService.parseAmount` validates the whole string; `decimalSeparator(amounts:fallback:)` picks one separator per file.
**Search terms:** Decimal(string:), decimal comma, thousands separator, truncated amount, wrong amount, EU bank CSV, importHash mismatch

## 2026-11-11 — CSV delimiter switched by a stray semicolon (#190)
**Symptom:** A comma CSV with `;` in any field (payee `Smith; Co`) was split on `;`; rows were dropped or mapped to the wrong columns. Quoted fields with the delimiter split in the middle.
**Root cause:** Delimiter chosen by `csv.contains(";")` over the whole file, and lines split with `components(separatedBy:)`, which ignores quoting. `ImportViewModel.loadCSV` had a copy of the same logic.
**Fix:** `CSVImportService.detectDelimiter` (most records with the same field count over the first 10, one-field lines ignored, tie to `;`) and the RFC 4180 `rows(from:)` tokenizer, shared by `parse` and `loadCSV`.
**Search terms:** delimiter detection, semicolon, quoted field, RFC 4180, column mapping preview, wrong columns, rows dropped
