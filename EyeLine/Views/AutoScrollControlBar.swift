import SwiftUI

/// Compact control strip for Auto Scroll: restart, pause/resume, and speed
/// (both a slider and +/- buttons per the product spec). Available both
/// before recording (to dial in a comfortable speed) and during recording
/// (live speed changes, pause/resume) — none of these interactions touch
/// RecordingViewModel, so they never start, stop, or interrupt the capture
/// session itself.
struct AutoScrollControlBar: View {
    @Bindable var teleprompter: TeleprompterViewModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                teleprompter.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }

            Button {
                teleprompter.togglePlayPause()
            } label: {
                Image(systemName: teleprompter.isPlaying ? "pause.fill" : "play.fill")
            }

            Button {
                teleprompter.decreaseSpeed()
            } label: {
                Image(systemName: "minus")
            }

            Slider(
                value: $teleprompter.speed,
                in: TeleprompterViewModel.speedRange
            )
            .frame(width: 110)

            Button {
                teleprompter.increaseSpeed()
            } label: {
                Image(systemName: "plus")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45), in: Capsule())
        .tint(.white)
    }
}
