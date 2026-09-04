import Foundation
import QuartzCore
import Observation

/// Drives Auto Scroll: a continuous, smooth pixel offset advanced every
/// frame via CADisplayLink rather than a repeating Timer, so it stays smooth
/// regardless of script length (nothing here re-measures or re-lays-out text
/// on each tick — TeleprompterOverlayView just reads `scrollOffset`).
///
/// Voice Tracking (current word index, karaoke highlighting, manual
/// repositioning) is a separate concern that lands in Milestone 3 and will
/// live in its own service; this view model intentionally only knows about
/// Auto Scroll for now.
@Observable
@MainActor
final class TeleprompterViewModel: NSObject {

    private(set) var scrollOffset: CGFloat = 0
    private(set) var isPlaying: Bool = false

    /// Points per second. Mirrors settings.autoScrollSpeed and writes back
    /// to it so the user's chosen speed is remembered next time.
    var speed: Double {
        didSet {
            guard speed != oldValue else { return }
            settings.autoScrollSpeed = speed
        }
    }

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
        scrollOffset += CGFloat(speed * delta)
    }

    deinit {
        displayLink?.invalidate()
    }
}
