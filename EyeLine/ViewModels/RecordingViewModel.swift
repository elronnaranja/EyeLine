import Foundation
import AVFoundation
import Observation

enum RecordingScreenState: Equatable {
    case preparing
    case permissionDenied(String)
    case ready
    case countingDown(secondsRemaining: Int)
    case recording
    case reviewing(url: URL)
    case saving
    case saved
    case error(String)
}

/// Orchestrates CameraService + VideoRecordingService + AudioSessionService +
/// PhotoLibraryService for the recording screen. Owns no teleprompter logic —
/// TeleprompterViewModel handles script position, scrolling, and voice
/// tracking independently, driven by the same `isRecording` signal.
@Observable
@MainActor
final class RecordingViewModel {

    let camera: CameraService
    private let recorder: VideoRecordingService

    private(set) var screenState: RecordingScreenState = .preparing
    private(set) var elapsedSeconds: Int = 0

    private var timerTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    let countdownDuration: Int

    init(countdownDuration: Int = 3) {
        let camera = CameraService()
        self.camera = camera
        self.recorder = VideoRecordingService(output: camera.movieFileOutput)
        self.countdownDuration = countdownDuration
    }

    var isRecording: Bool { recorder.isRecording }

    func onAppear() async {
        VideoRecordingService.cleanUpStaleRecordings()
        await camera.requestAuthorizationIfNeeded()

        guard camera.authorizationState == .authorized else {
            screenState = .permissionDenied(
                "EyeLine needs camera and microphone access to record. You can enable this in Settings."
            )
            return
        }

        do {
            try AudioSessionService.configureForRecording()
        } catch {
            screenState = .error("Couldn't set up audio: \(error.localizedDescription)")
            return
        }

        await camera.start()

        if let setupError = camera.setupError {
            screenState = .error(setupError.localizedDescription)
            return
        }

        screenState = .ready
    }

    func onDisappear() async {
        timerTask?.cancel()
        countdownTask?.cancel()
        await camera.stop()
        AudioSessionService.deactivate()
    }

    func beginCountdownThenRecord() {
        guard screenState == .ready else { return }
        guard countdownDuration > 0 else {
            startRecording()
            return
        }
        screenState = .countingDown(secondsRemaining: countdownDuration)
        countdownTask = Task {
            for remaining in stride(from: countdownDuration - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if remaining == 0 {
                    self.startRecording()
                } else {
                    self.screenState = .countingDown(secondsRemaining: remaining)
                }
            }
        }
    }

    func startRecording() {
        recorder.startRecording()
        screenState = .recording
        elapsedSeconds = 0
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    func stopRecording() async {
        timerTask?.cancel()
        do {
            let url = try await recorder.stopRecording()
            screenState = .reviewing(url: url)
        } catch {
            screenState = .error(error.localizedDescription)
        }
    }

    func retake() {
        recorder.discardCurrentRecording()
        elapsedSeconds = 0
        screenState = .ready
    }

    func discardAndExit() {
        recorder.discardCurrentRecording()
    }

    func save() async {
        guard case .reviewing(let url) = screenState else { return }
        screenState = .saving
        do {
            try await PhotoLibraryService.save(videoAt: url)
            recorder.discardCurrentRecording()
            screenState = .saved
        } catch {
            screenState = .error(error.localizedDescription)
        }
    }

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
