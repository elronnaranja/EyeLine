import SwiftUI

/// Transparent overlay drawn on top of the live camera preview. This is a
/// SwiftUI view only — it is never composited into the recorded video, which
/// comes straight from AVCaptureMovieFileOutput.
///
/// Both teleprompter modes share the same positioning mechanism: the text is
/// offset by `teleprompter.scrollOffset` and clipped to the reading box. A
/// plain SwiftUI ScrollView isn't used because both modes need an exact,
/// externally-driven pixel position — constant speed for Auto Scroll, eased
/// toward a computed target for Voice Tracking — rather than user-driven
/// scrolling.
///
/// Auto Scroll renders the plain script text. Voice Tracking instead renders
/// `teleprompter.karaokeText`, an AttributedString TeleprompterViewModel
/// rebuilds only when the current word changes (never per-frame), with
/// completed words dimmed and the current word highlighted. A swipe
/// up/down, enabled only in Voice Tracking, lets the speaker manually
/// correct their position without touching recording controls.
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

            textView
                .frame(maxWidth: geometry.size.width * settings.textWidthFraction, alignment: frameAlignment)
                .padding(.vertical, 8)
                // Without this, the frame(height:) below would propose its
                // small box height down to the Text and it would wrap/
                // truncate to fit — leaving nothing extra to scroll through.
                // This forces Text to report its full natural height instead,
                // so there's real content beyond the box for offset+clipped
                // to reveal as it scrolls.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(
                    GeometryReader { textGeometry in
                        Color.clear
                            .onAppear { teleprompter.reportMeasuredTextHeight(textGeometry.size.height) }
                            .onChange(of: textGeometry.size.height) { _, newHeight in
                                teleprompter.reportMeasuredTextHeight(newHeight)
                            }
                    }
                )
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
                .contentShape(Rectangle())
                .gesture(repositionGesture) // reachable only when hit testing is enabled below
        }
        .allowsHitTesting(settings.mode == .voiceTracking)
    }

    @ViewBuilder
    private var textView: some View {
        switch settings.mode {
        case .autoScroll:
            Text(script.content.isEmpty ? "Your script will appear here." : script.content)
                .font(.system(size: settings.fontSize, weight: fontWeight))
                .lineSpacing(settings.lineSpacing)
                .multilineTextAlignment(swiftUIAlignment)
                .foregroundStyle(.white.opacity(settings.textOpacity))
                .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
        case .voiceTracking:
            Text(teleprompter.karaokeText)
                .font(.system(size: settings.fontSize, weight: fontWeight))
                .lineSpacing(settings.lineSpacing)
                .multilineTextAlignment(swiftUIAlignment)
                .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
        }
    }

    /// Swipe up = move forward, swipe down = move back, roughly a phrase's
    /// worth of words per swipe. Only active in Voice Tracking, where the
    /// concept of "which word am I on" exists; Auto Scroll has its own
    /// explicit restart/speed controls instead.
    private var repositionGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let wordsPerSwipe = 6
                if value.translation.height < -40 {
                    teleprompter.manuallyReposition(byWords: wordsPerSwipe)
                } else if value.translation.height > 40 {
                    teleprompter.manuallyReposition(byWords: -wordsPerSwipe)
                }
            }
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
