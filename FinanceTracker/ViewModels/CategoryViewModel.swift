import Foundation
import Observation

@Observable
final class CategoryViewModel {
    private(set) var categories: [Category] = []

    private let categoryRepo: any CategoryRepositoryProtocol

    init(categoryRepo: any CategoryRepositoryProtocol) {
        self.categoryRepo = categoryRepo
    }

    func load() throws {
        categories = try categoryRepo.fetchAll()
    }

    func add(name: String, icon: String, colorHex: String, type: CategoryType) throws {
        let category = Category(name: name, icon: icon, colorHex: colorHex, type: type)
        try categoryRepo.save(category)
        try load()
    }

    func delete(_ category: Category) throws {
        try categoryRepo.delete(category)
        try load()
    }

    func findNearDuplicate(named name: String) -> Category? {
        categories.first { CategoryNameMatching.isNearDuplicate($0.name, name) }
    }
}
