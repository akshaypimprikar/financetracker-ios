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
    static func rows(from csv: String) -> [[String]] {
        rows(from: csv, delimiter: detectDelimiter(in: csv))
    }

    private static func rows(from csv: String, delimiter: Character, limit: Int = .max) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        var iterator = csv.makeIterator()
        var pending: Character? = nil

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

        while records.count < limit, let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && !fieldStarted && field.allSatisfy(\.isWhitespace) {
                field = ""
                inQuotes = true
                fieldStarted = true
            } else if char == delimiter {
                endField()
            } else if char.isNewline {
                endRecord()
            } else {
                field.append(char)
                if !char.isWhitespace { fieldStarted = true }
            }
        }
        if records.count < limit && (!field.isEmpty || !record.isEmpty) { endRecord() }
        return records
    }

    /// Picks `,` or `;` by which one splits the first records into a consistent field count,
    /// so a stray delimiter inside one field doesn't switch the whole file.
    private static func detectDelimiter(in csv: String) -> Character {
        func score(_ delimiter: Character) -> (consistent: Bool, fields: Int) {
            let counts = rows(from: csv, delimiter: delimiter, limit: 10).map(\.count)
            guard let first = counts.first, first > 1 else { return (false, 0) }
            return (counts.allSatisfy { $0 == first }, first)
        }
        let comma = score(","), semicolon = score(";")
        if semicolon.consistent != comma.consistent { return semicolon.consistent ? ";" : "," }
        return semicolon.fields > comma.fields ? ";" : ","
    }

    /// The decimal separator for the whole file: the one most unambiguous amounts point to,
    /// else `fallback`. An amount like "1,234" or "1.234" (one separator, 3 digits after) is ambiguous.
    private static func decimalSeparator(amounts: [String], fallback: Character) -> Character {
        var votes: [Character: Int] = [:]
        for amount in amounts where amount.allSatisfy({ "0123456789.,+-".contains($0) }) {
            let lastDot = amount.lastIndex(of: "."), lastComma = amount.lastIndex(of: ",")
            let hint: Character?
            switch (lastDot, lastComma) {
            case let (dot?, comma?): hint = dot > comma ? "." : ","
            case let (index?, nil), let (nil, index?):
                let separator = amount[index], other: Character = separator == "." ? "," : "."
                if amount.filter({ $0 == separator }).count > 1 { hint = other }
                else if amount[amount.index(after: index)...].count == 3 { hint = nil }
                else { hint = separator }
            case (nil, nil): hint = nil
            }
            if let hint { votes[hint, default: 0] += 1 }
        }
        let dots = votes["."] ?? 0, commas = votes[","] ?? 0
        return dots == commas ? fallback : (dots > commas ? "." : ",")
    }

    /// Parses the whole string or returns nil — never a valid prefix (`Decimal(string:)` would turn "12,50" into 12).
    private static func parseAmount(_ raw: String, decimalSeparator: Character) -> Decimal? {
        let grouping: Character = decimalSeparator == "," ? "." : ","
        var text = Substring(raw)
        var sign = ""
        if let first = text.first, first == "-" || first == "+" {
            sign = first == "-" ? "-" : ""
            text = text.dropFirst()
        }
        let parts = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let isDigits: (Substring) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        let integer = parts[0], fraction = parts.count == 2 ? parts[1] : ""
        // ".50" and "12." parsed before this fix, so keep them; a lone separator does not.
        guard !(integer.isEmpty && fraction.isEmpty) else { return nil }
        let groups = integer.isEmpty ? ["0"] : integer.split(separator: grouping, omittingEmptySubsequences: false)
        guard groups.allSatisfy(isDigits) else { return nil }
        if groups.count > 1 {
            guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        var normalized = sign + groups.joined()
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
