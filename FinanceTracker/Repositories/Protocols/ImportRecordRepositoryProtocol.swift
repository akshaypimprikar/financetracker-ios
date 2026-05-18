import Foundation

protocol ImportRecordRepositoryProtocol {
    func fetchAll() throws -> [ImportRecord]
    func save(_ record: ImportRecord) throws
    func delete(_ record: ImportRecord) throws
}
