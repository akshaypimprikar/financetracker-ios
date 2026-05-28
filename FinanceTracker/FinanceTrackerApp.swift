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
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FinanceTrackerMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
