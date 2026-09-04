import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ScriptLibraryViewModel {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createScript() -> Script {
        let script = Script()
        modelContext.insert(script)
        try? modelContext.save()
        return script
    }

    func duplicate(_ script: Script) {
        let copy = script.duplicate()
        modelContext.insert(copy)
        try? modelContext.save()
    }

    func delete(_ script: Script) {
        modelContext.delete(script)
        try? modelContext.save()
    }

    func touch(_ script: Script) {
        script.updatedAt = .now
        try? modelContext.save()
    }
}
