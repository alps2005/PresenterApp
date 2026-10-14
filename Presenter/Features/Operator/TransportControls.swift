import SwiftUI

/// Play/pause, position, mute and volume for the video on the audience output's background layer.
struct TransportControls: View {
    @Environment(MediaPlaybackController.self) private var playback

    var body: some View {
        HStack(spacing: 8) {
            Button { playback.togglePlay() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 14)
            }
            .help(playback.isPlaying ? "Pause the video" : "Play the video")

            Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                   in: 0...max(playback.duration, 0.1))
                .disabled(playback.duration <= 0)

            Text("-" + Self.format(max(playback.duration - playback.currentTime, 0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .help("Time left in the clip")

            if playback.loops {
                Image(systemName: "repeat").foregroundStyle(.secondary).help("Loops")
            }

            Button { playback.toggleMute() } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 16)
            }
            .help(playback.isMuted ? "Unmute" : "Mute")

            Slider(value: Binding(get: { Double(playback.volume) }, set: { playback.volume = Float($0) }), in: 0...1)
                .frame(width: 60)
                .disabled(playback.isMuted)
                .help("Volume")
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
