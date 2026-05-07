import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Dashboard")
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            Text("Transactions")
                .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }
            Text("Budgets")
                .tabItem { Label("Budgets", systemImage: "target") }
            Text("Accounts")
                .tabItem { Label("Accounts", systemImage: "building.columns.fill") }
            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
}
