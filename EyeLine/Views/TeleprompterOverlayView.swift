import SwiftUI

/// Transparent overlay drawn on top of the live camera preview. This is a
/// SwiftUI view only — it is never composited into the recorded video, which
/// comes straight from AVCaptureMovieFileOutput.
///
/// Auto Scroll (Milestone 2): the text is offset by
/// `teleprompter.scrollOffset`, a value TeleprompterViewModel advances every
/// frame via CADisplayLink, and clipped to the reading box. A plain
/// SwiftUI ScrollView isn't used here because Auto Scroll needs an exact,
/// externally-driven pixel position (for smooth constant-speed motion, live
/// speed changes, and restart-to-top) rather than user-driven scrolling.
///
/// Voice Tracking (karaoke highlighting, current-word tracking) lands in
/// Milestone 3 and will replace this plain Text with a windowed, highlighted
/// rendering — still positioned via the same scrollOffset mechanism.
struct TeleprompterOverlayView: View {
    let script: Script
    let settings: TeleprompterSettings
    let teleprompter: TeleprompterViewModel

    var body: some View {
        // Deliberately does NOT ignore the safe area: SwiftUI automatically
        // keeps a non-ignoring view clear of the Dynamic Island / notch, so
        // the reading position naturally starts just below it without any
        // manual offset math (an earlier version tried to compute that
        // offset by hand while also ignoring the safe area, which fought
        // itself and let the island cover the first line of text).
        GeometryReader { geometry in
            let height = geometry.size.height * settings.teleprompterHeightFraction

            Text(script.content.isEmpty ? "Your script will appear here." : script.content)
                .font(.system(size: settings.fontSize, weight: fontWeight))
                .lineSpacing(settings.lineSpacing)
                .multilineTextAlignment(swiftUIAlignment)
                .foregroundStyle(.white.opacity(settings.textOpacity))
                .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
                .frame(maxWidth: geometry.size.width * settings.textWidthFraction, alignment: frameAlignment)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .top)
                .offset(y: -teleprompter.scrollOffset)
                .frame(width: geometry.size.width, height: height, alignment: .top)
                .clipped()
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
