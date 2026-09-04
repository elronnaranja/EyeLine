import SwiftUI
import SwiftData
import UIKit

struct CameraRecordingView: View {
    let script: Script

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RecordingViewModel
    @State private var settings: TeleprompterSettings?
    @State private var teleprompter: TeleprompterViewModel?

    init(script: Script) {
        self.script = script
        _viewModel = State(initialValue: RecordingViewModel())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.screenState {
            case .preparing:
                ProgressView()
                    .tint(.white)

            case .permissionDenied(let message):
                PermissionDeniedView(message: message)

            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.onAppear() }
                }

            case .ready, .countingDown, .recording:
                CameraPreviewView(camera: viewModel.camera)
                    .ignoresSafeArea()

                if let settings, let teleprompter {
                    TeleprompterOverlayView(script: script, settings: settings, teleprompter: teleprompter)
                }

                recordingControls

                if case .countingDown(let remaining) = viewModel.screenState {
                    CountdownOverlay(secondsRemaining: remaining)
                }

            case .reviewing(let url):
                RecordingPreviewView(
                    videoURL: url,
                    onRetake: { viewModel.retake() },
                    onSave: { Task { await viewModel.save() } }
                )

            case .saving:
                ProgressView("Saving…")
                    .tint(.white)
                    .foregroundStyle(.white)

            case .saved:
                SavedConfirmationView { dismiss() }
            }
        }
        .statusBarHidden(isImmersiveState)
        .task {
            let fetchedSettings = TeleprompterSettings.fetchOrCreate(in: modelContext)
            settings = fetchedSettings
            teleprompter = TeleprompterViewModel(settings: fetchedSettings)
            await viewModel.onAppear()
        }
        .onDisappear {
            teleprompter?.pause()
            Task { await viewModel.onDisappear() }
        }
        .onChange(of: viewModel.screenState) { _, newState in
            guard let teleprompter else { return }
            switch newState {
            case .recording:
                teleprompter.play()
            case .ready:
                teleprompter.pause()
                teleprompter.restart()
            case .preparing, .permissionDenied, .countingDown, .reviewing, .saving, .saved, .error:
                teleprompter.pause()
            }
        }
    }

    private var isImmersiveState: Bool {
        switch viewModel.screenState {
        case .ready, .countingDown, .recording: return true
        default: return false
        }
    }

    private var isCountingDown: Bool {
        if case .countingDown = viewModel.screenState { return true }
        return false
    }

    @ViewBuilder
    private var recordingControls: some View {
        VStack {
            HStack {
                Button {
                    viewModel.discardAndExit()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .padding(.leading)

                Spacer()
            }
            .padding(.top, 8)

            Spacer()

            if viewModel.isRecording {
                RecordingTimerBadge(text: viewModel.formattedElapsedTime)
                    .padding(.bottom, 12)
            }

            if let teleprompter, settings?.mode == .autoScroll {
                AutoScrollControlBar(teleprompter: teleprompter)
                    .padding(.bottom, 20)
            }

            HStack {
                Spacer()
                RecordButton(isRecording: viewModel.isRecording) {
                    if viewModel.isRecording {
                        Task { await viewModel.stopRecording() }
                    } else {
                        viewModel.beginCountdownThenRecord()
                    }
                }
                .disabled(isCountingDown)
                Spacer()
            }
            .padding(.bottom, 36)
        }
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }
}

private struct RecordingTimerBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(text)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

private struct CountdownOverlay: View {
    let secondsRemaining: Int
    var body: some View {
        Text("\(secondsRemaining)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(radius: 8)
            .transition(.scale.combined(with: .opacity))
            .id(secondsRemaining)
            .animation(.easeOut(duration: 0.3), value: secondsRemaining)
    }
}

private struct PermissionDeniedView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct SavedConfirmationView: View {
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Saved to Photos")
                .font(.headline)
                .foregroundStyle(.white)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
    }
}
