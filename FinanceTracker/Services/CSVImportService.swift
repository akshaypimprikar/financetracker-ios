import Foundation
import CryptoKit
import RegexBuilder

struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
    var categoryID: UUID? = nil   // mutable, defaulted; never affects importHash
}

nonisolated struct ColumnMapping {
    let dateIndex: Int
    let amountIndex: Int
    let payeeIndex: Int
    let hasHeader: Bool
}

nonisolated struct CSVImportService {
    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"].map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    func parse(csv: String, mapping: ColumnMapping) throws -> [ParsedTransaction] {
        let delimiter = Self.detectDelimiter(in: csv)
        var rows = Self.rows(from: csv, delimiter: delimiter)
        if mapping.hasHeader && !rows.isEmpty { rows.removeFirst() }
        let dated = rows
            .filter { $0.count > max(mapping.dateIndex, mapping.amountIndex, mapping.payeeIndex) }
            .compactMap { columns in Self.parseDate(columns[mapping.dateIndex]).map { (date: $0, columns: columns) } }
        let decimalSeparator = Self.decimalSeparator(
            amounts: dated.map { $0.columns[mapping.amountIndex] },
            fallback: delimiter == ";" ? "," : "."
        )

        // Amounts are stored unsigned, so the sign is dropped.
        return dated.compactMap { date, columns -> ParsedTransaction? in
            guard let amount = Self.parseAmount(columns[mapping.amountIndex], decimalSeparator: decimalSeparator) else { return nil }
            let payee = columns[mapping.payeeIndex]
            return ParsedTransaction(
                date: date,
                amount: amount,
                payee: payee,
                importHash: Self.importHash(date: date, amount: amount, payee: payee)
            )
        }
    }

    /// `parse` off the caller's actor, so a large file doesn't block the UI.
    @concurrent func parseInBackground(csv: String, mapping: ColumnMapping) async throws -> [ParsedTransaction] {
        try parse(csv: csv, mapping: mapping)
    }

    /// Splits CSV text into trimmed fields per record (RFC 4180 quoting), dropping blank records.
    /// `limit` stops after that many records (the column-mapping preview needs only the first few).
    static func rows(from csv: String, limit: Int = .max) -> [[String]] {
        rows(from: csv, delimiter: detectDelimiter(in: csv), limit: limit)
    }

    private static func rows(from csv: String, delimiter: Character, limit: Int = .max) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        // The open quote of the current quoted field. If it is never closed, text follows its closing
        // quote (the "closing" quote was really the next field's opener), or the field would hold a later
        // row (closed by an inch mark such as `27"`), the field is re-read from there with that
        // quote as a literal, so one stray quote can't swallow the rows after it.
        var quoteStart: String.Index? = nil
        var literalQuote: String.Index? = nil
        var i = csv.startIndex

        func endField() {
            record.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field = ""
            fieldStarted = false
        }
        func endRecord() {
            endField()
            if record.contains(where: { !$0.isEmpty }) { records.append(record) }
            record = []
        }
        // The fields a row has: the previous record's count, or (in the first record) the fields before
        // this one, this one, and one per delimiter left on the line after `index` (its closing quote).
        func rowFieldCount(after index: String.Index) -> Int {
            let rest = csv[index...].prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
            return max(records.last?.count ?? 0, record.count + 1 + rest.filter { $0 == delimiter }.count)
        }
        // `records` and `record` can't change inside quotes, so only the field is rewound.
        func rewind(to start: String.Index) {
            field = ""
            inQuotes = false
            fieldStarted = false
            literalQuote = start
            quoteStart = nil
            i = start
        }

        while records.count < limit {
            guard i < csv.endIndex else {
                guard inQuotes, let start = quoteStart else { break }
                rewind(to: start)
                continue
            }
            let char = csv[i]
            var next = csv.index(after: i)
            if inQuotes {
                if char == "\"" {
                    if next < csv.endIndex && csv[next] == "\"" {
                        field.append("\"")
                        next = csv.index(after: next)
                    } else if (next == csv.endIndex || csv[next] == delimiter || csv[next].isWhitespace)
                                && !holdsARow(field, delimiter: delimiter, rowFieldCount: rowFieldCount(after: next)) {
                        inQuotes = false
                        quoteStart = nil
                    } else if let start = quoteStart {
                        rewind(to: start)
                        continue
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && !fieldStarted && i != literalQuote {
                field = ""
                inQuotes = true
                fieldStarted = true
                quoteStart = i
            } else if char == delimiter {
                endField()
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                endRecord()
            } else {
                field.append(char)
                if !char.isWhitespace { fieldStarted = true }
            }
            i = next
        }
        if records.count < limit && (!field.isEmpty || !record.isEmpty) { endRecord() }
        return records
    }

    /// Whether a line after the first in a quoted field looks like a row: it has at least `rowFieldCount`
    /// fields and one of them parses as a date. The quote was then a stray
    /// one, and the "field" is really the rows after it. A memo line with a date but fewer fields
    /// ("Card purchase\n11/10/2026, Store") stays in the field.
    private static func holdsARow(_ field: String, delimiter: Character, rowFieldCount: Int) -> Bool {
        field.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }).dropFirst().contains { line in
            let fields = line.split(separator: delimiter, omittingEmptySubsequences: false)
            return fields.count >= rowFieldCount
                && fields.contains { parseDate($0.trimmingCharacters(in: .whitespaces)) != nil }
        }
    }

    /// Picks `,` or `;` by which one splits more of the first 10 records into the same field count,
    /// so a stray delimiter inside one field doesn't switch the whole file. One-field records (a title
    /// line such as "Kontoauszug") are ignored. When both agree on as many records, the one that leaves
    /// more records with a field that parses as a date wins (a `;` file with "Doe, John, Jr" in a field,
    /// or a `,` file with "A;B" in a field, both tie on agreement), and `;` wins a full tie.
    private static func detectDelimiter(in csv: String) -> Character {
        func score(_ delimiter: Character) -> (agreeing: Int, withDate: Int) {
            let sample = rows(from: csv, delimiter: delimiter, limit: 10).filter { $0.count > 1 }
            let agreeing = Dictionary(sample.map { ($0.count, 1) }, uniquingKeysWith: +).values.max() ?? 0
            return (agreeing, sample.filter { $0.contains { parseDate($0) != nil } }.count)
        }
        let comma = score(","), semicolon = score(";")
        return (comma.agreeing, comma.withDate) > (semicolon.agreeing, semicolon.withDate) ? "," : ";"
    }

    /// The decimal separator for the whole file: the one more amounts point to on their own, or
    /// `fallback` when no amount points either way or the votes tie. Only amounts that parse under
    /// the separator they point to get a vote.
    private static func decimalSeparator(amounts: [String], fallback: Character) -> Character {
        var dots = 0, commas = 0
        for amount in amounts {
            guard let hint = separatorHint(amount), parseAmount(amount, decimalSeparator: hint) != nil else { continue }
            if hint == "." { dots += 1 } else { commas += 1 }
        }
        return dots == commas ? fallback : (dots > commas ? "." : ",")
    }

    /// The decimal separator one amount implies by itself, or nil when it can't tell:
    /// "1,234" or "1.234" (one separator, 3 digits after, a 1-3 digit integer part other than 0) could be either.
    private static func separatorHint(_ raw: String) -> Character? {
        guard let number = amountNumber(raw)?.filter({ $0 == "." || $0 == "," || $0.isNumber }) else { return nil }
        switch (number.lastIndex(of: "."), number.lastIndex(of: ",")) {
        case let (dot?, comma?):
            return dot > comma ? "." : ","
        case let (index?, nil), let (nil, index?):
            let separator = number[index]
            if number.filter({ $0 == separator }).count > 1 { return separator == "." ? "," : "." }
            let integer = number[..<index]
            if number[number.index(after: index)...].count == 3 && (1...3).contains(integer.count) && integer != "0" { return nil }
            return separator
        case (nil, nil):
            return nil
        }
    }

    /// A currency marker: a currency symbol ("$", "€"), any uppercase 3-letter code ("GHS"), or a common
    /// code or local abbreviation in any case ("usd", "kr", "zł", "R$", "Fr.", "Kč"). Lowercase codes are
    /// limited to the list so trailing text such as "12.50abc" is still rejected.
    private static let currencyMarker = Regex {
        ChoiceOf {
            /\p{Sc}/
            /[A-Z]{3}/
            Regex {
                /USD|EUR|GBP|CHF|CAD|AUD|NZD|JPY|CNY|INR|SEK|NOK|DKK|PLN|CZK|HUF|RON|BRL|MXN|ZAR|SGD|HKD|kr|zł|R\$|Fr\.|Kč/
            }.ignoresCase()
        }
    }

    private static let amountPattern = Regex {
        /\s*/
        Optionally { currencyMarker }
        /\s*/
        Capture { /[+-]?/ }
        /\s*/
        Optionally { currencyMarker }
        /\s*/
        Capture { /[0-9.,][0-9., '\u{2019}\u{00A0}\u{2009}\u{202F}]*?/ }
        /\s*/
        Capture { /[+-]?/ }
        /\s*/
        Optionally { currencyMarker }
        /\s*/
        Optionally { /CR|DR/.ignoresCase() }
        /\s*/
    }

    /// The number left after removing what bank exports put around it: a currency marker
    /// ("$4.25", "12,50 €", "USD 3.00"), a leading or trailing sign ("12.50-"), but not both signs,
    /// and a credit/debit suffix ("12.50 CR", "12.50 DR"; amounts are stored unsigned, so it is dropped
    /// like the sign). Nil if anything else is left.
    private static func amountNumber(_ raw: String) -> String? {
        guard let match = raw.wholeMatch(of: amountPattern) else { return nil }
        let (_, leading, number, trailing) = match.output
        guard leading.isEmpty || trailing.isEmpty else { return nil }
        return String(number)
    }

    /// Parses the whole amount or returns nil, never a valid prefix (`Decimal(string:)` turned "12,50" into 12).
    /// Spaces and apostrophes between digits count as grouping ("1 234,56", "1'234.50"). The result is unsigned.
    private static func parseAmount(_ raw: String, decimalSeparator: Character) -> Decimal? {
        guard let number = amountNumber(raw) else { return nil }
        let grouping: Character = decimalSeparator == "," ? "." : ","
        let text = String(number.map { " '\u{2019}\u{00A0}\u{2009}\u{202F}".contains($0) ? grouping : $0 })
        let parts = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let isDigits: (Substring) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        let integer = parts[0], fraction = parts.count == 2 ? parts[1] : ""
        // ".50" and "12." parsed before this fix, so keep them; a lone separator does not.
        guard !(integer.isEmpty && fraction.isEmpty) else { return nil }
        let groups = integer.isEmpty ? ["0"] : integer.split(separator: grouping, omittingEmptySubsequences: false)
        guard groups.allSatisfy(isDigits) else { return nil }
        if groups.count > 1 {
            let thousands = groups[0].count <= 3 && groups.dropFirst().allSatisfy { $0.count == 3 }
            // Indian lakh grouping: "1,23,456.78" (groups of 2, then the last 3 digits).
            let lakh = groups.count > 2 && groups[0].count <= 2 && groups.last?.count == 3
                && groups.dropFirst().dropLast().allSatisfy { $0.count == 2 }
            guard groups[0].first != "0", thousands || lakh else { return nil }
        }
        var normalized = groups.joined()
        if !fraction.isEmpty {
            guard isDigits(fraction) else { return nil }
            normalized += "." + fraction
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    func deduplicated(parsed: [ParsedTransaction], existingHashes: Set<String>) -> [ParsedTransaction] {
        parsed.filter { !existingHashes.contains($0.importHash) }
    }

    static func importHash(date: Date, amount: Decimal, payee: String) -> String {
        let dateString = Self.iso8601DateFormatter.string(from: date)
        let input = "\(dateString)-\(amount)-\(payee.lowercased().trimmingCharacters(in: .whitespaces))"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let iso8601DateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Use the device calendar timezone so parsed dates (which use Calendar.current)
        // and importHash dates both produce the same date-only string for the same local day.
        f.timeZone = Calendar.current.timeZone
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatters.lazy.compactMap { $0.date(from: string) }.first
    }
}
