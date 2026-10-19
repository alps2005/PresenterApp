import SwiftUI
import PresenterCore

/// Every audio file in the project. Clicking one plays it for the audience, fading out what was playing.
/// Right-click to loop it, use it as a soundtrack or a slide's audio, or delete it.
struct AudioBin: View {
    let coordinator: PresentationCoordinator
    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var isImporting = false
    @State private var importFailures: [String] = []
    @State private var pendingDeletion: MediaAsset?

    /// The same height as the media bin, so switching between them doesn't move the slides.
    static let height: CGFloat = MediaBin.height

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            PanelHeader(title: "Audio") {
                if isImporting { ProgressView().controlSize(.small) }
                Button {
                    importAudio()
                } label: {
                    Label("Import…", systemImage: "plus")
                }
                .disabled(isImporting)
            }
            if !importFailures.isEmpty {
                WarningLabel("Couldn't import \(importFailures.joined(separator: ", ")).")
                    .lineLimit(2)
            }
            if coordinator.audioAssets.isEmpty {
                Text("Import music and sounds. Click one to play it for the audience; slides and presentations can start and stop audio too.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(coordinator.audioAssets.reversed()) { asset in
                            row(asset)
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(height: Self.height)
        .confirmDeletion("Delete “\(pendingDeletion?.originalFilename ?? "")”?",
                         message: pendingDeletion.map { deletionMessage(for: $0) } ?? "",
                         of: $pendingDeletion) { asset in
            coordinator.removeMediaAsset(asset.id)
        }
    }

    private func row(_ asset: MediaAsset) -> some View {
        let isPlaying = coordinator.state.audio?.track.assetID == asset.id
        return HStack(spacing: Spacing.md) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(isPlaying ? Palette.live : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(asset.originalFilename)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            // A badge, not colour alone.
            if isPlaying { StateBadge(.live) }
            if let duration = asset.duration {
                Text(TimeText.format(duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isPlaying ? Palette.live.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: Radius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { coordinator.playAudio(AudioTrack(assetID: asset.id)) }
        .help("Click to play for the audience. Right-click to loop it or use it in a presentation.")
        .contextMenu {
            Button("Play") { coordinator.playAudio(AudioTrack(assetID: asset.id)) }
            Button("Play Looping") { coordinator.playAudio(AudioTrack(assetID: asset.id, loops: true)) }
            Divider()
            if let cued = coordinator.state.preview, let presentation = coordinator.project.presentation(forItem: cued.itemID) {
                Button("Play When the Cued Slide Goes Live") {
                    coordinator.setAudioCue(.play(AudioTrack(assetID: asset.id)), slideID: cued.slideID, inPresentation: presentation.id)
                }
                Button("Use as Soundtrack of “\(presentation.title)”") {
                    coordinator.setSoundtrack(AudioTrack(assetID: asset.id, loops: true), presentationID: presentation.id)
                }
            } else {
                Text("Cue a slide to use this in a presentation")
            }
            Divider()
            Button("Delete…", role: .destructive) { pendingDeletion = asset }
        }
    }

    /// Names what loses the track, so the operator knows which slides change.
    private func deletionMessage(for asset: MediaAsset) -> String {
        let titles = coordinator.project.presentationsUsing(asset: asset.id).map { $0.title.isEmpty ? "Untitled" : $0.title }
        let playing = "If it's playing, it plays on until you stop it."
        guard !titles.isEmpty else { return "\(playing) You can undo this." }
        let users = titles.count > 3 ? Array(titles.prefix(2)) + ["\(titles.count - 2) other presentations"] : titles
        let list = users.count == 1 ? users[0] : users.dropLast().joined(separator: ", ") + " and " + users.last!
        return "Used in \(list), which lose this audio. \(playing) You can undo this."
    }

    private func importAudio() {
        isImporting = true
        importFailures = []
        Task {
            importFailures = await AudioImport.run(coordinator: coordinator, mediaLibrary: mediaLibrary)
            isImporting = false
        }
    }
}
