import Foundation
import SwiftData

/// A user-authored teleprompter script. Content is stored as the raw text the
/// user wrote or pasted; tokenization for voice matching happens on demand in
/// ScriptMatchingService and is never persisted here.
@Model
final class Script {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "Untitled Script", content: String = "", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Short single-line preview for library rows.
    var preview: String {
        let collapsed = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 120 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]) + "…"
    }

    var wordCount: Int {
        content.split { $0.isWhitespace || $0.isNewline }.count
    }

    func duplicate() -> Script {
        Script(title: title + " Copy", content: content, createdAt: .now, updatedAt: .now)
    }
}
