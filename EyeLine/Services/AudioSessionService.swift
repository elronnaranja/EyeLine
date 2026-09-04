import AVFoundation

/// Owns the single shared AVAudioSession configuration for the app.
///
/// Both video recording (via AVCaptureSession's audio input) and, later,
/// on-device speech recognition need microphone access. They must not each
/// try to configure and activate their own competing session — there is only
/// ever one AVAudioSession per process. This service configures it once, and
/// every other service (CameraService, SpeechRecognitionService) reads from
/// the same active session rather than reconfiguring it.
enum AudioSessionService {

    /// Configures the shared session for simultaneous video+audio capture
    /// and (eventually) speech recognition. Safe to call multiple times.
    static func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
