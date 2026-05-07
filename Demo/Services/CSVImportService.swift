import Foundation
import CryptoKit

struct ParsedTransaction {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
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
        let delimiter: Character = csv.contains(";") ? ";" : ","
        var lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if mapping.hasHeader && !lines.isEmpty { lines.removeFirst() }

        return try lines.compactMap { line -> ParsedTransaction? in
            let columns = line.components(separatedBy: String(delimiter)).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard columns.count > max(mapping.dateIndex, mapping.amountIndex, mapping.payeeIndex) else { return nil }
            guard let date = Self.parseDate(columns[mapping.dateIndex]) else { return nil }
            guard let amount = Decimal(string: columns[mapping.amountIndex]) else { return nil }
            let payee = columns[mapping.payeeIndex]
            return ParsedTransaction(
                date: date,
                amount: amount,
                payee: payee,
                importHash: Self.importHash(date: date, amount: amount, payee: payee)
            )
        }
    }

    func deduplicated(parsed: [ParsedTransaction], existingHashes: Set<String>) -> [ParsedTransaction] {
        parsed.filter { !existingHashes.contains($0.importHash) }
    }

    static func importHash(date: Date, amount: Decimal, payee: String) -> String {
        let input = "\(Int(date.timeIntervalSince1970))-\(amount)-\(payee.lowercased().trimmingCharacters(in: .whitespaces))"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatters.lazy.compactMap { $0.date(from: string) }.first
    }
}
