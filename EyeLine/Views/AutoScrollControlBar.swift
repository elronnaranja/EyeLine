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
        HStack(spacing: 22) {
            Button {
                teleprompter.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }

            Button {
                teleprompter.togglePlayPause()
            } label: {
                Image(systemName: teleprompter.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
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
            .frame(width: 150)

            Button {
                teleprompter.increaseSpeed()
            } label: {
                Image(systemName: "plus")
            }
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.5), in: Capsule())
        .tint(.white)
    }
}
