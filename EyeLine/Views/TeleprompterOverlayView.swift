import SwiftUI

/// Transparent overlay drawn on top of the live camera preview. This is a
/// SwiftUI view only — it is never composited into the recorded video, which
/// comes straight from AVCaptureMovieFileOutput.
///
/// Milestone 1 scope: static script display, scrollable by the user, sized
/// and positioned close to the front camera / Dynamic Island. Auto Scroll
/// and Voice Tracking (karaoke highlighting, current-word tracking) land in
/// later milestones and will replace the plain Text below with a windowed,
/// highlighted rendering driven by TeleprompterViewModel.
struct TeleprompterOverlayView: View {
    let script: Script
    let settings: TeleprompterSettings

    var body: some View {
        // Deliberately does NOT ignore the safe area: SwiftUI automatically
        // keeps a non-ignoring view clear of the Dynamic Island / notch, so
        // the reading position naturally starts just below it without any
        // manual offset math (an earlier version tried to compute that
        // offset by hand while also ignoring the safe area, which fought
        // itself and let the island cover the first line of text).
        GeometryReader { geometry in
            let height = geometry.size.height * settings.teleprompterHeightFraction

            ScrollView(.vertical, showsIndicators: false) {
                Text(script.content.isEmpty ? "Your script will appear here." : script.content)
                    .font(.system(size: settings.fontSize, weight: fontWeight))
                    .lineSpacing(settings.lineSpacing)
                    .multilineTextAlignment(swiftUIAlignment)
                    .foregroundStyle(.white.opacity(settings.textOpacity))
                    .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
                    .frame(maxWidth: geometry.size.width * settings.textWidthFraction, alignment: frameAlignment)
                    .padding(.vertical, 8)
            }
            .frame(width: geometry.size.width, height: height)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.28), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
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

    private var swiftUIAlignment: TextAlignment {
        settings.textAlignment == .center ? .center : .leading
    }

    private var frameAlignment: Alignment {
        settings.textAlignment == .center ? .center : .leading
    }
}
