import SwiftUI
import SwiftData

/// Lets the user tune how the teleprompter looks and behaves. Everything
/// here writes directly to the single shared TeleprompterSettings row via
/// @Bindable, so changes apply immediately and persist automatically —
/// there's no separate "Save" step.
struct SettingsView: View {
    @Bindable var settings: TeleprompterSettings

    var body: some View {
        Form {
            Section {
                GeometryReader { geometry in
                    previewText
                        .frame(width: geometry.size.width * settings.textWidthFraction)
                        .frame(maxWidth: .infinity, alignment: settings.textAlignment == .center ? .center : .leading)
                }
                .frame(minHeight: 90)
                .padding(.vertical, 12)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            }

            Section("Typography") {
                sliderRow(
                    title: "Font Size",
                    value: $settings.fontSize,
                    range: 18...60,
                    format: "%.0f pt"
                )

                Picker("Font Weight", selection: $settings.fontWeightRawValue) {
                    Text("Regular").tag(0)
                    Text("Medium").tag(1)
                    Text("Semibold").tag(2)
                    Text("Bold").tag(3)
                }

                sliderRow(
                    title: "Line Spacing",
                    value: $settings.lineSpacing,
                    range: 0...20,
                    format: "%.0f pt"
                )

                sliderRow(
                    title: "Text Width",
                    value: $settings.textWidthFraction,
                    range: 0.5...1.0,
                    format: "%.0f%%",
                    displayMultiplier: 100
                )

                Picker("Alignment", selection: Binding(
                    get: { settings.textAlignment },
                    set: { settings.textAlignment = $0 }
                )) {
                    Text("Center").tag(TeleprompterTextAlignment.center)
                    Text("Left").tag(TeleprompterTextAlignment.leading)
                }
                .pickerStyle(.segmented)
            }

            Section("Readability") {
                sliderRow(
                    title: "Text Opacity",
                    value: $settings.textOpacity,
                    range: 0.3...1.0,
                    format: "%.0f%%",
                    displayMultiplier: 100
                )

                sliderRow(
                    title: "Completed Text Opacity",
                    value: $settings.completedTextOpacity,
                    range: 0.1...1.0,
                    format: "%.0f%%",
                    displayMultiplier: 100
                )

                sliderRow(
                    title: "Teleprompter Height",
                    value: $settings.teleprompterHeightFraction,
                    range: 0.12...0.35,
                    format: "%.0f%% of screen",
                    displayMultiplier: 100
                )
            }

            Section("Recording Behavior") {
                Picker("Default Mode", selection: Binding(
                    get: { settings.mode },
                    set: { settings.mode = $0 }
                )) {
                    Text("Auto Scroll").tag(TeleprompterMode.autoScroll)
                    Text("Voice Tracking").tag(TeleprompterMode.voiceTracking)
                }
                .pickerStyle(.segmented)

                sliderRow(
                    title: "Auto Scroll Speed",
                    value: $settings.autoScrollSpeed,
                    range: TeleprompterViewModel.speedRange,
                    format: "%.0f"
                )

                Stepper(
                    "Countdown: \(settings.countdownDuration)s",
                    value: $settings.countdownDuration,
                    in: 0...10
                )
            }
        }
        .navigationTitle("Teleprompter Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewText: some View {
        Text("The quick brown fox jumps over the lazy dog.")
            .font(.system(size: settings.fontSize, weight: fontWeight))
            .lineSpacing(settings.lineSpacing)
            .multilineTextAlignment(settings.textAlignment == .center ? .center : .leading)
            .foregroundStyle(.white.opacity(settings.textOpacity))
    }

    private var fontWeight: Font.Weight {
        switch settings.fontWeightRawValue {
        case 0: return .regular
        case 1: return .medium
        case 2: return .semibold
        case 3: return .bold
        default: return .semibold
        }
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        displayMultiplier: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayMultiplier))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
