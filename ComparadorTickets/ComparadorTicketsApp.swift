import SwiftUI
import SwiftData

@main
struct ComparadorTicketsApp: App {
    @StateObject private var updateManager = AppUpdateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateManager)
        }
        .modelContainer(for: [Product.self, PriceRecord.self])
    }
}
