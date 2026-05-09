import Foundation

protocol ImportRecordRepositoryProtocol {
    func fetchAll() throws -> [ImportRecord]
    func save(_ record: ImportRecord) throws
}
