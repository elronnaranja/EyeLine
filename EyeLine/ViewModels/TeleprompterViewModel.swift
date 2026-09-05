import SwiftUI
import QuartzCore
import Observation
import AVFoundation

/// Owns both teleprompter modes and the single scrollOffset that positions
/// the text on screen.
///
/// Auto Scroll advances scrollOffset at a constant speed via CADisplayLink.
/// Voice Tracking instead eases scrollOffset toward a target computed from
/// the speaker's current position in the script (from ScriptMatchingService,
/// fed by SpeechRecognitionService) — reusing the same CADisplayLink loop
/// rather than a second timing mechanism, so both modes share one smooth,
/// 60fps-driven code path. TeleprompterOverlayView only ever reads
/// `scrollOffset` (and, for Voice Tracking, `karaokeText`); it has no idea
/// which mode produced them.
@Observable
@MainActor
final class TeleprompterViewModel: NSObject {

    private(set) var scrollOffset: CGFloat = 0
    private(set) var isPlaying: Bool = false

    /// Points per second for Auto Scroll. Mirrors settings.autoScrollSpeed
    /// and writes back to it so the user's chosen speed is remembered.
    var speed: Double {
        didSet {
            guard speed != oldValue else { return }
            settings.autoScrollSpeed = speed
        }
    }

    // MARK: Voice Tracking

    let matcher = ScriptMatchingService()
    let speechRecognizer = SpeechRecognitionService()

    private(set) var currentWordIndex: Int = -1
    private(set) var karaokeText: AttributedString = AttributedString("")

    private var scriptContent: String = ""
    private var totalTextHeight: CGFloat = 0
    private var voiceTrackingTargetOffset: CGFloat = 0

    private let settings: TeleprompterSettings
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    static let speedRange: ClosedRange<Double> = 10...220
    static let speedStep: Double = 10

    init(settings: TeleprompterSettings) {
        self.settings = settings
        self.speed = settings.autoScrollSpeed
        super.init()
    }

    // MARK: - Shared scroll loop (Auto Scroll speed OR Voice Tracking easing)

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        lastTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func pause() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Resets scroll position to the top without changing play state.
    func restart() {
        scrollOffset = 0
    }

    func increaseSpeed() {
        speed = min(Self.speedRange.upperBound, speed + Self.speedStep)
    }

    func decreaseSpeed() {
        speed = max(Self.speedRange.lowerBound, speed - Self.speedStep)
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        let delta = link.timestamp - last
        switch settings.mode {
        case .autoScroll:
            scrollOffset += CGFloat(speed * delta)
        case .voiceTracking:
            let diff = voiceTrackingTargetOffset - scrollOffset
            // Deliberately gentle: catches up over roughly a second rather
            // than snapping, so a jump reads as a smooth scroll instead of
            // the screen suddenly cutting to a new position.
            let easing = min(1, CGFloat(delta) * 1.8)
            scrollOffset += diff * easing
        }
    }

    // No deinit here: `deinit` always runs outside the main-actor context,
    // even for a @MainActor class, so it cannot touch actor-isolated
    // properties like `displayLink`. CameraRecordingView.onDisappear already
    // calls pause() reliably, which invalidates the link; relying on that
    // single call site avoids the deinit isolation problem entirely.

    // MARK: - Voice Tracking lifecycle

    func loadScript(_ script: Script) {
        scriptContent = script.content
        matcher.loadScript(script.content)
        currentWordIndex = -1
        rebuildKaraokeText()
    }

    /// TeleprompterOverlayView reports the full (unclipped) rendered height
    /// of the script text here once, so Voice Tracking can compute a scroll
    /// target as a fraction of that height without doing its own text layout.
    func reportMeasuredTextHeight(_ height: CGFloat) {
        totalTextHeight = height
        updateVoiceTrackingTarget()
    }

    func startVoiceTracking(audioOutput: AVCaptureAudioDataOutput, queue: DispatchQueue) async {
        await speechRecognizer.requestAuthorizationIfNeeded()
        guard speechRecognizer.authorizationState == .authorized else { return }

        speechRecognizer.onTranscriptUpdate = { [weak self] text in
            guard let self else { return }
            if let newIndex = self.matcher.processRecognizedText(text) {
                self.currentWordIndex = newIndex
                self.rebuildKaraokeText()
                self.updateVoiceTrackingTarget()
            }
        }
        audioOutput.setSampleBufferDelegate(speechRecognizer, queue: queue)
        speechRecognizer.start()
        play()
    }

    func stopVoiceTracking(audioOutput: AVCaptureAudioDataOutput) {
        speechRecognizer.stop()
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        pause()
    }

    /// Swipe-to-correct: moves a fixed number of tokens forward/backward and
    /// re-centers the matcher's search window there. Never touches
    /// RecordingViewModel, so it can't interrupt an active recording.
    func manuallyReposition(byWords delta: Int) {
        guard !matcher.tokens.isEmpty else { return }
        let newIndex = max(-1, min(matcher.tokens.count - 1, currentWordIndex + delta))
        matcher.manuallySetPosition(to: newIndex)
        currentWordIndex = newIndex
        rebuildKaraokeText()
        updateVoiceTrackingTarget()
    }

    private func updateVoiceTrackingTarget() {
        guard totalTextHeight > 0, !matcher.tokens.isEmpty else { return }
        let progress = Double(currentWordIndex + 1) / Double(matcher.tokens.count)
        voiceTrackingTargetOffset = CGFloat(max(0, min(1, progress))) * totalTextHeight
    }

    private func rebuildKaraokeText() {
        karaokeText = Self.buildKaraokeText(
            content: scriptContent,
            tokens: matcher.tokens,
            currentIndex: currentWordIndex,
            baseOpacity: settings.textOpacity,
            completedOpacity: settings.completedTextOpacity
        )
    }

    /// Builds one AttributedString for the whole script with per-word
    /// styling, preserving all original whitespace/punctuation by copying
    /// the untouched gaps between tokens verbatim. Rebuilt only when
    /// currentWordIndex changes (a few times a second at most from speech
    /// updates), never per-frame — the 60fps scroll loop only touches
    /// scrollOffset, which this string doesn't depend on.
    private static func buildKaraokeText(
        content: String,
        tokens: [ScriptToken],
        currentIndex: Int,
        baseOpacity: Double,
        completedOpacity: Double
    ) -> AttributedString {
        guard !content.isEmpty else { return AttributedString("") }
        var result = AttributedString()
        var cursor = content.startIndex

        for token in tokens {
            if cursor < token.range.lowerBound {
                result += AttributedString(String(content[cursor..<token.range.lowerBound]))
            }
            var wordAttr = AttributedString(String(content[token.range]))
            if token.index < currentIndex {
                wordAttr.foregroundColor = Color.white.opacity(completedOpacity)
            } else if token.index == currentIndex {
                // Color + underline only — NOT a font/weight change. A bold
                // current word is wider than its regular form, so as the
                // highlight moved from word to word the surrounding text
                // would reflow and words would visibly jump between lines.
                // Underline and color don't affect glyph width, so the line
                // breaks stay fixed regardless of which word is current.
                wordAttr.foregroundColor = Color.yellow
                wordAttr.underlineStyle = .single
            } else {
                wordAttr.foregroundColor = Color.white.opacity(baseOpacity)
            }
            result += wordAttr
            cursor = token.range.upperBound
        }
        if cursor < content.endIndex {
            result += AttributedString(String(content[cursor..<content.endIndex]))
        }
        return result
    }
}
