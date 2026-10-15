import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PresenterCore

/// Like ProPresenter's media bin: every image and video in the project. Clicking one puts it straight on the
/// audience output's background layer; the words on screen stay. Right-click to use it as a slide's or a
/// presentation's background instead.
struct MediaBin: View {
    let coordinator: PresentationCoordinator
    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var isImporting = false
    @State private var importErrors: [String] = []

    static let height: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Media") {
                if isImporting { ProgressView().controlSize(.small) }
                Button {
                    importMedia()
                } label: {
                    Label("Import…", systemImage: "plus")
                }
                .disabled(isImporting)
            }
            if !importErrors.isEmpty {
                WarningLabel(importErrors.joined(separator: " "))
                    .lineLimit(2)
            }
            if coordinator.project.mediaAssets.isEmpty {
                Text("Import images and videos to use as backgrounds. Click one to show it behind the words on screen.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(coordinator.project.mediaAssets.reversed()) { asset in
                            tile(asset)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(height: Self.height)
    }

    private func tile(_ asset: MediaAsset) -> some View {
        let background = Self.background(for: asset)
        let isLive = coordinator.state.liveBackground?.assetID == asset.id
        return VStack(alignment: .leading, spacing: 3) {
            ZStack {
                Color.black
                if let image = mediaLibrary.image(for: asset.id) {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else if mediaLibrary.isMissing(asset.id) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                        .accessibilityLabel("Missing file")
                }
                if asset.kind == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "film")
                            Spacer()
                            if let duration = asset.duration {
                                Text(TimeText.format(duration)).monospacedDigit()
                            }
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5))
                    }
                }
            }
            .frame(width: 160, height: 90)
            .tileFrame(TileState(isLive: isLive))
            .overlay(alignment: .topTrailing) {
                if isLive { StateBadge(.live).padding(Spacing.xs) }
            }
            Text(asset.originalFilename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 160, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { coordinator.showBackground(background) }
        .help("Click to show on the audience output, behind the words")
        .contextMenu {
            Button("Show on Output") { coordinator.showBackground(background) }
            Divider()
            if let cued = coordinator.state.preview, let presentation = coordinator.project.presentation(forItem: cued.itemID) {
                Button("Use as Background of the Cued Slide") {
                    coordinator.setSlideBackground(background, slideID: cued.slideID, inPresentation: presentation.id)
                }
                Button("Use as Background of “\(presentation.title)”") {
                    coordinator.setPresentationBackground(background, presentationID: presentation.id)
                }
            } else {
                Text("Cue a slide to use this as its background")
            }
        }
    }

    static func background(for asset: MediaAsset) -> SlideBackground {
        switch asset.kind {
        case .image: .image(ImageBackground(assetID: asset.id))
        case .video: .video(VideoBackground(assetID: asset.id))
        }
    }

    private func importMedia() {
        let urls = MediaPanel.choose([.image, .movie], multiple: true, message: "Choose images and videos to add to the media bin")
        guard !urls.isEmpty else { return }
        isImporting = true
        importErrors = []
        Task {
            defer { isImporting = false }
            for url in urls {
                do {
                    let isMovie = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
                    let asset = isMovie ? try await mediaLibrary.importVideo(at: url) : try await mediaLibrary.importImage(at: url)
                    coordinator.addMediaAsset(asset)
                } catch {
                    importErrors.append("Couldn't import \(url.lastPathComponent).")
                }
            }
        }
    }
}
