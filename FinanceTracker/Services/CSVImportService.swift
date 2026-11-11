import Foundation
import CryptoKit

struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
    var categoryID: UUID? = nil   // mutable, defaulted; never affects importHash
}

struct ColumnMapping {
    let dateIndex: Int
    let amountIndex: Int
    let payeeIndex: Int
    let hasHeader: Bool
}

struct CSVImportService {
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
        rows = rows.filter { $0.count > max(mapping.dateIndex, mapping.amountIndex, mapping.payeeIndex) }
        let decimalSeparator = Self.decimalSeparator(
            amounts: rows.map { $0[mapping.amountIndex] },
            fallback: delimiter == ";" ? "," : "."
        )

        return try rows.compactMap { columns -> ParsedTransaction? in
            guard let date = Self.parseDate(columns[mapping.dateIndex]) else { return nil }
            guard let rawAmount = Self.parseAmount(columns[mapping.amountIndex], decimalSeparator: decimalSeparator) else { return nil }
            let amount = abs(rawAmount)
            let payee = columns[mapping.payeeIndex]
            return ParsedTransaction(
                date: date,
                amount: amount,
                payee: payee,
                importHash: Self.importHash(date: date, amount: amount, payee: payee)
            )
        }
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
        // The open quote of the current quoted field. If it is never closed, the field is re-read
        // from there with that quote as a literal, so one malformed field can't swallow the rest of the file.
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

        while records.count < limit {
            guard i < csv.endIndex else {
                // `records` and `record` can't change inside quotes, so only the field is rewound.
                guard inQuotes, let start = quoteStart else { break }
                field = ""
                inQuotes = false
                fieldStarted = false
                literalQuote = start
                quoteStart = nil
                i = start
                continue
            }
            let char = csv[i]
            var next = csv.index(after: i)
            if inQuotes {
                if char == "\"" {
                    if next < csv.endIndex && csv[next] == "\"" {
                        field.append("\"")
                        next = csv.index(after: next)
                    } else {
                        inQuotes = false
                        quoteStart = nil
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
            } else if char.isNewline {
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
        guard let number = amountParts(raw)?.number.filter({ $0 == "." || $0 == "," || $0.isNumber }) else { return nil }
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

    /// Splits off what bank exports put around the number: a currency symbol or 3-letter code
    /// ("$4.25", "12,50 €", "USD 3.00") and a leading or trailing sign ("12.50-"). Nil if anything else is left.
    private static func amountParts(_ raw: String) -> (sign: String, number: String)? {
        let pattern = /^\s*(?:[A-Z]{3}|\p{Sc})?\s*([+-]?)\s*(?:[A-Z]{3}|\p{Sc})?\s*([0-9.,][0-9., \u{00A0}\u{202F}]*?)\s*([+-]?)\s*(?:[A-Z]{3}|\p{Sc})?\s*$/
        guard let match = raw.wholeMatch(of: pattern) else { return nil }
        let (_, leading, number, trailing) = match.output
        guard leading.isEmpty || trailing.isEmpty else { return nil }
        return (leading + trailing == "-" ? "-" : "", String(number))
    }

    /// Parses the whole amount or returns nil, never a valid prefix (`Decimal(string:)` turned "12,50" into 12).
    /// Spaces between digits count as grouping ("1 234,56").
    private static func parseAmount(_ raw: String, decimalSeparator: Character) -> Decimal? {
        guard let amount = amountParts(raw) else { return nil }
        let grouping: Character = decimalSeparator == "," ? "." : ","
        let text = String(amount.number.map { " \u{00A0}\u{202F}".contains($0) ? grouping : $0 })
        let parts = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let isDigits: (Substring) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        let integer = parts[0], fraction = parts.count == 2 ? parts[1] : ""
        // ".50" and "12." parsed before this fix, so keep them; a lone separator does not.
        guard !(integer.isEmpty && fraction.isEmpty) else { return nil }
        let groups = integer.isEmpty ? ["0"] : integer.split(separator: grouping, omittingEmptySubsequences: false)
        guard groups.allSatisfy(isDigits) else { return nil }
        if groups.count > 1 {
            guard groups[0].count <= 3, groups[0].first != "0", groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        var normalized = amount.sign + groups.joined()
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
