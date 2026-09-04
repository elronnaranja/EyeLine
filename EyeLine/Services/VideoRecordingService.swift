import AVFoundation
import Observation

enum VideoRecordingError: LocalizedError {
    case notReady
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The camera isn't ready to record yet."
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        }
    }
}

/// Drives AVCaptureMovieFileOutput to record exactly what the camera
/// captures — video and microphone audio, encoded by the system the same
/// way the built-in Camera app would. It has no awareness of the
/// teleprompter overlay; SwiftUI draws that overlay on top of the live
/// preview only, so it can never end up in the output file.
@Observable
@MainActor
final class VideoRecordingService: NSObject {

    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case finished(url: URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let output: AVCaptureMovieFileOutput
    private var recordingContinuation: CheckedContinuation<URL, Error>?

    init(output: AVCaptureMovieFileOutput) {
        self.output = output
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func startRecording() {
        guard !output.isRecording else { return }
        let url = Self.makeTemporaryFileURL()
        state = .recording(startedAt: .now)
        output.startRecording(to: url, recordingDelegate: self)
    }

    /// Stops recording and resolves once the file has finished writing.
    @discardableResult
    func stopRecording() async throws -> URL {
        guard output.isRecording else {
            if case .finished(let url) = state { return url }
            throw VideoRecordingError.notReady
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.recordingContinuation = continuation
            self.output.stopRecording()
        }
    }

    /// Discards the current or most recent recording's temp file.
    func discardCurrentRecording() {
        if case .finished(let url) = state {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
    }

    private static func makeTemporaryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EyeLineRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    /// Removes any leftover temp recordings from previous, interrupted sessions.
    static func cleanUpStaleRecordings() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EyeLineRecordings", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

extension VideoRecordingService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                // AVFoundation reports a non-fatal "recording stopped by
                // request" error even on a clean, user-initiated stop; the
                // file is still valid in that case.
                let nsError = error as NSError
                let wasSuccessfulStop = (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
                if !wasSuccessfulStop {
                    self.state = .failed(error.localizedDescription)
                    self.recordingContinuation?.resume(throwing: VideoRecordingError.recordingFailed(error))
                    self.recordingContinuation = nil
                    return
                }
            }
            self.state = .finished(url: outputFileURL)
            self.recordingContinuation?.resume(returning: outputFileURL)
            self.recordingContinuation = nil
        }
    }
}
