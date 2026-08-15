//
//  FinanceTrackerApp.swift
//  FinanceTracker
//
//  Created by Akshay Pimprikar on 5/5/26.
//

import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let isSeedingScreenshots = CommandLine.arguments.contains("--seedscreenshots")
        let isUITesting = CommandLine.arguments.contains("--uitesting") || isSeedingScreenshots
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            // In-memory stores (UI tests, screenshot seeding) start fresh every
            // launch — there is no existing store to migrate, and SwiftData's
            // behavior when a SchemaMigrationPlan is applied to
            // isStoredInMemoryOnly is undefined. Skip the migration plan for
            // in-memory stores.
            let container: ModelContainer
            if isUITesting {
                container = try ModelContainer(for: schema, configurations: [config])
            } else {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: FinanceTrackerMigrationPlan.self,
                    configurations: [config]
                )
            }
            if isSeedingScreenshots {
                DemoDataSeeder.seed(into: container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    let importActor: TransactionImportActor

    init() {
        importActor = TransactionImportActor(modelContainer: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(importActor: importActor)
        }
        .modelContainer(sharedModelContainer)
    }
}
