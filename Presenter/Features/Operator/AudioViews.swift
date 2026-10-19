import SwiftUI
import UniformTypeIdentifiers
import PresenterCore

/// The playing track in the Live panel: its name, pause, position, time left and stop.
struct AudioTransport: View {
    let coordinator: PresentationCoordinator
    @Environment(AudioPlaybackController.self) private var audio

    var body: some View {
        if let missing = audio.missingAssetID {
            WarningLabel("Audio file missing: \(coordinator.project.asset(withID: missing)?.originalFilename ?? "a track"). Nothing is playing.")
        } else if let live = coordinator.state.audio {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(title(of: live), systemImage: live.isPaused ? "pause.circle" : "speaker.wave.2")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(live.isPaused ? "Paused" : "Playing for the audience")
                HStack(spacing: Spacing.md) {
                    Button { audio.togglePause() } label: {
                        Image(systemName: live.isPaused ? "play.fill" : "pause.fill")
                            .frame(width: 14)
                    }
                    .help(live.isPaused ? "Carry on playing" : "Pause the audio")
                    .accessibilityLabel(live.isPaused ? "Play audio" : "Pause audio")

                    Slider(value: Binding(get: { audio.currentTime }, set: { audio.seek(to: $0) }),
                           in: 0...max(audio.duration, 0.1))
                        .disabled(audio.duration <= 0)
                        .accessibilityLabel("Audio position")

                    Text("-" + TimeText.format(max(audio.duration - audio.currentTime, 0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: Widths.valueLabel, alignment: .trailing)
                        .help("Time left in the track")

                    if live.track.loops {
                        Image(systemName: "repeat").foregroundStyle(.secondary).help("Loops").accessibilityLabel("Loops")
                    }

                    Button { audio.stop() } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 14)
                    }
                    .help("Fade the audio out")
                    .accessibilityLabel("Stop audio")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        }
    }

    private func title(of live: LiveAudio) -> String {
        coordinator.project.asset(withID: live.track.assetID)?.originalFilename ?? "Audio"
    }
}

/// Loop and fade-in settings for a track.
struct AudioTrackOptions: View {
    @Binding var track: AudioTrack

    var body: some View {
        Toggle("Loop", isOn: Binding(get: { track.loops }, set: { track.loops = $0 }))
        FadeSlider(label: "Fade In", seconds: Binding(get: { track.fadeIn }, set: { track.fadeIn = $0 }))
    }
}

/// A fade length, in tenths of a second.
struct FadeSlider: View {
    let label: String
    @Binding var seconds: Double

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Slider(value: Binding(get: { seconds }, set: { seconds = ($0 * 10).rounded() / 10 }),
                   in: AudioTrack.fadeRange)
                .accessibilityLabel(label)
            Text(String(format: "%.1f s", seconds))
                .monospacedDigit()
                .frame(width: Widths.valueLabel, alignment: .trailing)
        }
    }
}

/// Chooses one of the project's audio tracks.
struct AudioAssetPicker: View {
    let coordinator: PresentationCoordinator
    @Binding var assetID: UUID

    var body: some View {
        Picker("Track", selection: $assetID) {
            ForEach(coordinator.audioAssets) { asset in
                Text(asset.originalFilename).tag(asset.id)
            }
        }
        .labelsHidden()
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

/// What a slide does to the audio when it's taken live, in the editor.
struct AudioCueControls: View {
    let coordinator: PresentationCoordinator
    @Binding var cue: AudioCue?

    private enum Choice: Hashable {
        case none, play, stop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("When live", selection: Binding(get: { choice }, set: { choose($0) })) {
                Text("Leave the audio alone").tag(Choice.none)
                Text("Play a track").tag(Choice.play)
                    .disabled(coordinator.audioAssets.isEmpty)
                Text("Stop the audio").tag(Choice.stop)
            }
            .labelsHidden()
            .frame(minWidth: 0, maxWidth: .infinity)
            switch cue {
            case .play(let track):
                AudioAssetPicker(coordinator: coordinator, assetID: Binding(
                    get: { track.assetID },
                    set: { cue = .play(AudioTrack(assetID: $0, loops: track.loops, fadeIn: track.fadeIn)) }
                ))
                AudioTrackOptions(track: Binding(get: { track }, set: { cue = .play($0) }))
            case .stop(let fadeOut):
                FadeSlider(label: "Fade Out", seconds: Binding(get: { fadeOut }, set: { cue = .stop(fadeOut: $0) }))
            case nil:
                EmptyView()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var choice: Choice {
        switch cue {
        case .play: .play
        case .stop: .stop
        case nil: .none
        }
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .none: cue = nil
        case .play: cue = coordinator.audioAssets.first.map { .play(AudioTrack(assetID: $0.id)) }
        case .stop: cue = .stop(fadeOut: PresentationCoordinator.defaultAudioFadeOut)
        }
    }

    private var caption: String {
        if coordinator.audioAssets.isEmpty {
            return "Import music in the audio bin (⌥⌘U) to play it from a slide."
        }
        return switch cue {
        case .play: "Starts when the slide is taken live. A track already playing plays on."
        case .stop: "Fades out whatever is playing when the slide is taken live."
        case nil: "Whatever is playing carries on."
        }
    }
}

/// A presentation's soundtrack, in the editor's Document settings.
struct SoundtrackControls: View {
    let coordinator: PresentationCoordinator
    @Binding var track: AudioTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle("Play a soundtrack", isOn: Binding(
                get: { track != nil },
                set: { isOn in track = isOn ? coordinator.audioAssets.first.map { AudioTrack(assetID: $0.id, loops: true) } : nil }
            ))
            .disabled(track == nil && coordinator.audioAssets.isEmpty)
            if let current = track {
                AudioAssetPicker(coordinator: coordinator, assetID: Binding(
                    get: { current.assetID },
                    set: { track = AudioTrack(assetID: $0, loops: current.loops, fadeIn: current.fadeIn) }
                ))
                AudioTrackOptions(track: Binding(get: { current }, set: { track = $0 }))
            }
            Text(coordinator.audioAssets.isEmpty
                 ? "Import music in the audio bin (⌥⌘U) to use it as a soundtrack."
                 : "Plays when you move into this presentation from another item, unless it's already playing. A slide's own audio comes first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension PresentationCoordinator {
    /// The project's audio files, oldest first.
    var audioAssets: [MediaAsset] {
        project.mediaAssets.filter { $0.kind == .audio }
    }
}

enum AudioImport {
    /// Asks for audio files and imports them. Returns the names of files that couldn't be imported.
    @MainActor
    static func run(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary) async -> [String] {
        let urls = MediaPanel.choose([.audio], multiple: true, message: "Choose music and sounds to add to the audio bin")
        var failures: [String] = []
        for url in urls {
            do {
                coordinator.addMediaAsset(try await mediaLibrary.importAudio(at: url))
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        return failures
    }
}
