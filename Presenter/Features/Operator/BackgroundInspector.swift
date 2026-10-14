import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PresenterCore

/// Which background the inspector edits: one slide's override, or a presentation's default.
enum BackgroundTarget: Equatable {
    case slide(UUID, presentationID: UUID)
    case presentation(UUID)
}

/// Picks a colour or an imported image as a background, clears it so it inherits, or makes it transparent so
/// the background already on the audience output stays.
struct BackgroundInspector: View {
    private enum Mode: Hashable {
        case inherit
        case color
        case image
        case video
        case transparent
    }

    private static let defaultColor = RGBAColor(red: 0.11, green: 0.23, blue: 0.36)

    let coordinator: PresentationCoordinator
    let target: BackgroundTarget
    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var importError: String?
    @State private var isImporting = false

    private var presentationID: UUID {
        switch target {
        case .slide(_, let presentationID), .presentation(let presentationID): presentationID
        }
    }

    private var background: SlideBackground? {
        let presentation = coordinator.project.presentation(withID: presentationID)
        switch target {
        case .slide(let slideID, _): return presentation?.slide(withID: slideID)?.background
        case .presentation: return presentation?.background
        }
    }

    private var inheritLabel: String {
        if case .slide = target { "Presentation" } else { "Default" }
    }

    private var mode: Mode {
        switch background {
        case nil: .inherit
        case .color: .color
        case .image: .image
        case .video: .video
        case .transparent: .transparent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A closure, not `set: select`: Xcode 26's compiler crashes converting the method reference.
            Picker("Background", selection: Binding(get: { mode }, set: { select($0) })) {
                Text(inheritLabel).tag(Mode.inherit)
                Text("Color").tag(Mode.color)
                Text("Image").tag(Mode.image)
                Text("Video").tag(Mode.video)
                Text("None").tag(Mode.transparent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch background {
            case nil:
                Text(target == .presentation(presentationID)
                     ? "Slides use the app's default background."
                     : "This slide uses its presentation's background.")
                    .foregroundStyle(.secondary)
            case .color(let color):
                ColorPicker("Color", selection: Binding(
                    get: { color.color },
                    set: { apply(.color(RGBAColor($0))) }
                ), supportsOpacity: false)
            case .image(let image):
                imageControls(image)
            case .video(let video):
                videoControls(video)
            case .transparent:
                Text("Transparent: when this slide goes live, whatever background is already on screen stays, like ProPresenter's empty background.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func imageControls(_ image: ImageBackground) -> some View {
        HStack {
            Label(coordinator.project.asset(withID: image.assetID)?.originalFilename ?? "Unknown image",
                  systemImage: "photo")
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose Image…") { chooseImage() }
                .disabled(isImporting)
        }
        if mediaLibrary.isMissing(image.assetID) {
            Label("The image file is missing or unreadable. Slides show the default background instead.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        HStack(spacing: 16) {
            Picker("Scaling", selection: Binding(
                get: { image.scaling },
                set: { scaling in apply(.image(ImageBackground(assetID: image.assetID, scaling: scaling, dimming: image.dimming))) }
            )) {
                Text("Fill").tag(ImageScaling.fill)
                Text("Fit").tag(ImageScaling.fit)
                Text("Stretch").tag(ImageScaling.stretch)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            HStack(spacing: 4) {
                Text("Dim")
                Slider(value: Binding(
                    get: { image.dimming },
                    set: { dimming in apply(.image(ImageBackground(assetID: image.assetID, scaling: image.scaling, dimming: dimming))) }
                ), in: ImageBackground.dimmingRange)
                .frame(width: 100)
            }
        }
    }

    private func select(_ mode: Mode) {
        guard mode != self.mode else { return }
        importError = nil
        switch mode {
        case .inherit: apply(nil)
        case .color: apply(.color(Self.defaultColor))
        case .image: chooseImage()
        case .video: chooseVideo()
        case .transparent: apply(.transparent)
        }
    }

    @ViewBuilder
    private func videoControls(_ video: VideoBackground) -> some View {
        HStack {
            Label(coordinator.project.asset(withID: video.assetID)?.originalFilename ?? "Unknown video",
                  systemImage: "film")
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose Video…") { chooseVideo() }
                .disabled(isImporting)
        }
        if mediaLibrary.isMissing(video.assetID) {
            Label("The video file is missing or unreadable. Slides show the default background instead.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        HStack(spacing: 16) {
            Picker("Scaling", selection: Binding(get: { video.scaling }, set: { value in
                var updated = video
                updated.scaling = value
                apply(.video(updated))
            })) {
                Text("Fill").tag(ImageScaling.fill)
                Text("Fit").tag(ImageScaling.fit)
                Text("Stretch").tag(ImageScaling.stretch)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Toggle("Loop", isOn: Binding(get: { video.loops }, set: { value in
                var updated = video
                updated.loops = value
                apply(.video(updated))
            }))
            Toggle("Mute", isOn: Binding(get: { video.isMuted }, set: { value in
                var updated = video
                updated.isMuted = value
                apply(.video(updated))
            }))
        }
        HStack(spacing: 4) {
            Text("Dim")
            Slider(value: Binding(get: { video.dimming }, set: { value in
                var updated = video
                updated.dimming = value
                apply(.video(updated))
            }), in: ImageBackground.dimmingRange)
            .frame(width: 100)
        }
    }

    /// Asks for a video, checks it plays, copies it into the media library and uses it.
    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background video"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let previous = background
        isImporting = true
        importError = nil
        Task {
            defer { isImporting = false }
            do {
                let asset = try await mediaLibrary.importVideo(at: url)
                coordinator.addMediaAsset(asset)
                var video = VideoBackground(assetID: asset.id)
                if case .video(let old) = previous {
                    video.scaling = old.scaling
                    video.loops = old.loops
                    video.isMuted = old.isMuted
                    video.dimming = old.dimming
                }
                apply(.video(video))
            } catch {
                importError = "Couldn't import \(url.lastPathComponent). Choose a video this Mac can play (MP4, MOV, M4V…)."
            }
        }
    }

    /// Asks for an image, copies it into the media library and uses it. Cancelling changes nothing.
    private func chooseImage() {
        // NSOpenPanel rather than `.fileImporter`: this view can live in a popover that closes
        // when the panel takes focus, which would drop a SwiftUI importer's callback.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background image"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let previous = background
        isImporting = true
        importError = nil
        Task {
            defer { isImporting = false }
            do {
                let asset = try await mediaLibrary.importImage(at: url)
                coordinator.addMediaAsset(asset)
                // Keep the scaling and dimming the operator already chose when replacing an image.
                var image = ImageBackground(assetID: asset.id)
                if case .image(let old) = previous {
                    image.scaling = old.scaling
                    image.dimming = old.dimming
                }
                apply(.image(image))
            } catch {
                importError = "Couldn't import \(url.lastPathComponent). Choose a JPEG, PNG, HEIC or other image file."
            }
        }
    }

    private func apply(_ background: SlideBackground?) {
        switch target {
        case .slide(let slideID, let presentationID):
            coordinator.setSlideBackground(background, slideID: slideID, inPresentation: presentationID)
        case .presentation(let presentationID):
            coordinator.setPresentationBackground(background, presentationID: presentationID)
        }
    }
}
