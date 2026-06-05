import SwiftData

// MARK: - SchemaV1

/// The initial versioned schema capturing all @Model types at v1.0.
/// Add future schemas (SchemaV2, SchemaV3…) alongside new migration stages
/// rather than modifying this enum so old migration paths remain intact.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Account.self,
            Transaction.self,
            Category.self,
            Budget.self,
            ImportRecord.self,
        ]
    }
}

// MARK: - FinanceTrackerMigrationPlan

/// No-op migration plan for the initial release.
/// When a future schema version is added, append a `MigrationStage` to `stages`
/// and add the new schema to `schemas` — the store will migrate automatically.
enum FinanceTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
