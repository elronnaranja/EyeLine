import AVFoundation
import UIKit
import Observation

enum CameraAuthorizationState {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum CameraSetupError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "The front camera isn't available on this device."
        case .microphoneUnavailable:
            return "The microphone isn't available on this device."
        case .cannotAddInput, .cannotAddOutput:
            return "Couldn't configure the camera session."
        case .configurationFailed(let error):
            return "Camera setup failed: \(error.localizedDescription)"
        }
    }
}

/// Owns the AVCaptureSession and the front camera.
///
/// This service intentionally does the bare minimum: it discovers the front
/// camera, feeds it into a capture session using Apple's automatic defaults
/// (continuous autofocus, auto exposure, auto white balance — all left
/// untouched), and exposes a preview layer plus a movie file output for
/// VideoRecordingService to drive. It never applies custom image processing,
/// never locks the device for manual exposure/focus/white-balance
/// configuration, and knows nothing about the teleprompter or scripts.
@Observable
@MainActor
final class CameraService: NSObject {

    private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    private(set) var isSessionRunning = false
    private(set) var setupError: CameraSetupError?
    /// True while the system has interrupted the session (e.g. an incoming
    /// call, another app taking the camera, Control Center recording, etc).
    private(set) var isInterrupted = false

    let session = AVCaptureSession()
    let movieFileOutput = AVCaptureMovieFileOutput()
    let audioDataOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "design.theorange.eyeline.camera.session")
    private var isConfigured = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted, object: session
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded, object: session
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError, object: session
        )
    }

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        var cameraGranted = cameraStatus == .authorized
        var micGranted = micStatus == .authorized

        if cameraStatus == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        }
        if micStatus == .notDetermined {
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        if cameraGranted && micGranted {
            authorizationState = .authorized
        } else if cameraStatus == .restricted || micStatus == .restricted {
            authorizationState = .restricted
        } else {
            authorizationState = .denied
        }
    }

    // MARK: - Session lifecycle

    /// Configures and starts the capture session. Safe to call repeatedly;
    /// configuration only runs once per instance.
    func start() async {
        guard authorizationState == .authorized else { return }

        if !isConfigured {
            do {
                try await configureSession()
                isConfigured = true
            } catch let error as CameraSetupError {
                setupError = error
                return
            } catch {
                setupError = .configurationFailed(error)
                return
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                Task { @MainActor in
                    self.isSessionRunning = running
                    continuation.resume()
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                Task { @MainActor in
                    self.isSessionRunning = false
                    continuation.resume()
                }
            }
        }
    }

    private func configureSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                do {
                    try self.performConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs on sessionQueue. Uses Apple's automatic capture defaults
    /// throughout — no exposure/focus/white-balance/zoom overrides.
    private func performConfiguration() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        ).devices.first else {
            throw CameraSetupError.cameraUnavailable
        }

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw CameraSetupError.microphoneUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else { throw CameraSetupError.cannotAddInput }
        session.addInput(videoInput)

        let audioInput = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(audioInput) else { throw CameraSetupError.cannotAddInput }
        session.addInput(audioInput)

        guard session.canAddOutput(movieFileOutput) else { throw CameraSetupError.cannotAddOutput }
        session.addOutput(movieFileOutput)

        // Added so SpeechRecognitionService can later tap raw audio buffers
        // from the same input rather than opening a second, competing audio
        // session. No delegate is attached until voice tracking starts.
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }

        if let connection = movieFileOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if movieFileOutput.connection(with: .video)?.isVideoStabilizationSupported == true {
            movieFileOutput.connection(with: .video)?.preferredVideoStabilizationMode = .auto
        }
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return layer
    }

    // MARK: - Interruptions

    @objc private func sessionWasInterrupted(notification: Notification) {
        Task { @MainActor in
            self.isInterrupted = true
        }
    }

    @objc private func sessionInterruptionEnded(notification: Notification) {
        Task { @MainActor in
            self.isInterrupted = false
        }
    }

    @objc private func sessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        Task { @MainActor in
            self.setupError = .configurationFailed(error)
            if error.code == .mediaServicesWereReset {
                await self.start()
            }
        }
    }
}
