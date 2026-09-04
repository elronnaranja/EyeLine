import SwiftUI
import SwiftData

@main
struct EyeLineApp: App {

    let modelContainer: ModelContainer = {
        let schema = Schema([Script.self, TeleprompterSettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
