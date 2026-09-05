import Speech
import AVFoundation
import Observation

/// Feeds live microphone audio into Apple's Speech framework and reports
/// back the growing transcript for the current utterance. Prefers on-device
/// recognition so it works offline and keeps audio off the network.
///
/// This service does not open its own audio session or audio engine — it
/// receives audio buffers as an AVCaptureAudioDataOutputSampleBufferDelegate,
/// tapping the SAME AVCaptureSession microphone input CameraService already
/// owns for video recording. That's what lets recording and speech
/// recognition run simultaneously without two competing audio sessions.
///
/// It only produces text; it has no idea what a script is or where the
/// speaker is in one — that's ScriptMatchingService's job, orchestrated by
/// TeleprompterViewModel.
@Observable
final class SpeechRecognitionService: NSObject {

    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    @MainActor private(set) var authorizationState: AuthorizationState = .notDetermined
    @MainActor private(set) var isListening = false
    @MainActor private(set) var lastError: String?

    /// Invoked on the main actor with the full recognized text of the
    /// current utterance every time it changes (partial results included).
    @MainActor var onTranscriptUpdate: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    @MainActor
    func requestAuthorizationIfNeeded() async {
        let current = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if current == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        } else {
            status = current
        }
        authorizationState = Self.map(status)
    }

    @MainActor
    func start() {
        guard authorizationState == .authorized else { return }
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition isn't available right now."
            return
        }
        guard !isListening else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.onTranscriptUpdate?(result.bestTranscription.formattedString)
                }
                if let error {
                    let nsError = error as NSError
                    // "No speech detected" / cancellation errors fire
                    // routinely on stop() or during silence — not real
                    // failures worth surfacing to the user.
                    let isBenign = nsError.domain == "kAFAssistantErrorDomain"
                    if !isBenign {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
        isListening = true
        lastError = nil
    }

    @MainActor
    func stop() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}

extension SpeechRecognitionService: AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Called on whatever queue CameraService's audio output was configured
    /// with — deliberately NOT hopped to the main actor here, so buffers are
    /// appended in the exact order they arrive rather than racing through
    /// separately scheduled Tasks. SFSpeechAudioBufferRecognitionRequest's
    /// append method is documented as safe to call from any queue.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        request?.appendAudioSampleBuffer(sampleBuffer)
    }
}
