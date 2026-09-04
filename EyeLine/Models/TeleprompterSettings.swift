import Foundation
import SwiftData

enum TeleprompterMode: String, Codable, CaseIterable {
    case voiceTracking
    case autoScroll
}

enum TeleprompterTextAlignment: String, Codable, CaseIterable {
    case leading, center
}

/// Singleton-style settings record. There should only ever be one row; use
/// TeleprompterSettings.fetchOrCreate(in:) to obtain it rather than inserting
/// new instances directly.
@Model
final class TeleprompterSettings {
    var id: UUID

    // Typography
    var fontSize: Double
    var fontWeightRawValue: Int // maps to Font.Weight via Self.weight(from:)
    var lineSpacing: Double
    var textWidthFraction: Double // fraction of screen width, 0.5...1.0
    var textAlignmentRawValue: String
    var textOpacity: Double
    var completedTextOpacity: Double
    var teleprompterHeightFraction: Double // fraction of screen height, e.g. 0.2

    // Behavior
    var modeRawValue: String
    var autoScrollSpeed: Double // lines per second, user-adjustable
    var countdownDuration: Int // seconds

    init(
        fontSize: Double = 32,
        fontWeightRawValue: Int = 2, // .semibold
        lineSpacing: Double = 8,
        textWidthFraction: Double = 0.86,
        textAlignmentRawValue: String = TeleprompterTextAlignment.center.rawValue,
        textOpacity: Double = 1.0,
        completedTextOpacity: Double = 0.35,
        teleprompterHeightFraction: Double = 0.2,
        modeRawValue: String = TeleprompterMode.autoScroll.rawValue,
        autoScrollSpeed: Double = 40,
        countdownDuration: Int = 3
    ) {
        self.id = UUID()
        self.fontSize = fontSize
        self.fontWeightRawValue = fontWeightRawValue
        self.lineSpacing = lineSpacing
        self.textWidthFraction = textWidthFraction
        self.textAlignmentRawValue = textAlignmentRawValue
        self.textOpacity = textOpacity
        self.completedTextOpacity = completedTextOpacity
        self.teleprompterHeightFraction = teleprompterHeightFraction
        self.modeRawValue = modeRawValue
        self.autoScrollSpeed = autoScrollSpeed
        self.countdownDuration = countdownDuration
    }

    var mode: TeleprompterMode {
        get { TeleprompterMode(rawValue: modeRawValue) ?? .autoScroll }
        set { modeRawValue = newValue.rawValue }
    }

    var textAlignment: TeleprompterTextAlignment {
        get { TeleprompterTextAlignment(rawValue: textAlignmentRawValue) ?? .center }
        set { textAlignmentRawValue = newValue.rawValue }
    }

    /// Fetches the single settings row, creating and inserting one if none exists yet.
    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> TeleprompterSettings {
        let descriptor = FetchDescriptor<TeleprompterSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = TeleprompterSettings()
        context.insert(created)
        return created
    }
}
