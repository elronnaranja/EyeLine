import SwiftUI
import AVKit

/// Shown after Stop is tapped. Plays back the just-recorded file straight
/// from disk and lets the user Save (to Photos), Retake (discard and go back
/// to the camera), or Delete (discard and leave the recording screen).
struct RecordingPreviewView: View {
    let videoURL: URL
    let onRetake: () -> Void
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var showDeleteConfirmation = false

    init(videoURL: URL, onRetake: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.videoURL = videoURL
        self.onRetake = onRetake
        self.onSave = onSave
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            VStack {
                Spacer()
                HStack(spacing: 24) {
                    ActionButton(title: "Delete", systemImage: "trash", tint: .red) {
                        showDeleteConfirmation = true
                    }
                    ActionButton(title: "Retake", systemImage: "arrow.counterclockwise", tint: .white) {
                        player.pause()
                        onRetake()
                    }
                    ActionButton(title: "Save", systemImage: "checkmark", tint: .green, prominent: true) {
                        player.pause()
                        onSave()
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) {
                player.pause()
                onRetake()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(prominent ? tint : .black.opacity(0.4), in: Circle())
                    .foregroundStyle(prominent ? .black : tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
    }
}
