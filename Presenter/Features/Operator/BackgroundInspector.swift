import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PresenterCore

/// Which background the inspector edits: one slide's override, a presentation's default, or a theme's.
enum BackgroundTarget: Equatable {
    case slide(UUID, presentationID: UUID)
    case presentation(UUID)
    case theme(UUID)
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

    private var background: SlideBackground? {
        switch target {
        case .slide(let slideID, let presentationID):
            coordinator.project.presentation(withID: presentationID)?.slide(withID: slideID)?.background
        case .presentation(let presentationID):
            coordinator.project.presentation(withID: presentationID)?.background
        case .theme(let themeID):
            coordinator.project.theme(withID: themeID)?.background
        }
    }

    private var inheritLabel: String {
        switch target {
        case .slide: "Presentation"
        case .presentation: hasThemeBackground ? "Theme" : "Default"
        case .theme: "Default"
        }
    }

    /// The presentation follows a theme with a background, which its slides get when it sets none.
    private var hasThemeBackground: Bool {
        guard case .presentation(let presentationID) = target,
              let presentation = coordinator.project.presentation(withID: presentationID) else { return false }
        return coordinator.project.theme(for: presentation)?.background != nil
    }

    private var inheritedText: String {
        switch target {
        case .slide: "This slide uses its presentation's background."
        case .presentation: hasThemeBackground ? "Slides use the theme's background." : "Slides use the app's default background."
        case .theme: "Slides use their presentation's background, or the app's default."
        }
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Five segments only just fit a narrow inspector; past that, a menu, so the row never pushes the
            // panel wider than its column (docs/adr/0002-spacing-and-panel-padding.md).
            ViewThatFits(in: .horizontal) {
                modePicker
                    .pickerStyle(.segmented)
                    .fixedSize()
                modePicker
                    .pickerStyle(.menu)
                    .fixedSize()
            }

            switch background {
            case nil:
                Text(inheritedText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                WarningLabel(importError)
            }
        }
        .controlSize(.small)
    }

    private var modePicker: some View {
        // A closure, not `set: select`: Xcode 26's compiler crashes converting the method reference.
        Picker("Background", selection: Binding(get: { mode }, set: { select($0) })) {
            Text(inheritLabel).tag(Mode.inherit)
            Text("Color").tag(Mode.color)
            Text("Image").tag(Mode.image)
            Text("Video").tag(Mode.video)
            Text("None").tag(Mode.transparent)
        }
        .labelsHidden()
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
            WarningLabel("The image file is missing or unreadable. Slides show the default background instead.")
        }
        let scaling = Binding(
            get: { image.scaling },
            set: { scaling in apply(.image(ImageBackground(assetID: image.assetID, scaling: scaling, dimming: image.dimming))) }
        )
        let dimming = Binding(
            get: { image.dimming },
            set: { dimming in apply(.image(ImageBackground(assetID: image.assetID, scaling: image.scaling, dimming: dimming))) }
        )
        // One row where there's room (Quick Edit), two in a narrow inspector.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.lg) {
                scalingPicker(scaling)
                dimRow(dimming).frame(width: Widths.dimRow)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                scalingPicker(scaling)
                dimRow(dimming)
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
            WarningLabel("The video file is missing or unreadable. Slides show the default background instead.")
        }
        let scaling = Binding(get: { video.scaling }, set: { value in
            var updated = video
            updated.scaling = value
            apply(.video(updated))
        })
        let toggles = HStack(spacing: Spacing.lg) {
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
        .fixedSize()
        // One row where there's room (Quick Edit), two in a narrow inspector.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.lg) {
                scalingPicker(scaling)
                toggles
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                scalingPicker(scaling)
                toggles
            }
        }
        dimRow(Binding(get: { video.dimming }, set: { value in
            var updated = video
            updated.dimming = value
            apply(.video(updated))
        }))
        .frame(maxWidth: Widths.inspectorContentWidth, alignment: .leading)
    }

    private func scalingPicker(_ scaling: Binding<ImageScaling>) -> some View {
        Picker("Scaling", selection: scaling) {
            Text("Fit").tag(ImageScaling.fit)
            Text("Fill").tag(ImageScaling.fill)
            Text("Stretch").tag(ImageScaling.stretch)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Scaling")
    }

    /// "Dim" and a slider that takes the rest of the row.
    private func dimRow(_ dimming: Binding<Double>) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("Dim")
            Slider(value: dimming, in: ImageBackground.dimmingRange)
                .frame(minWidth: Widths.compactSlider)
        }
    }

    /// Asks for a video, checks it plays, copies it into the media library and uses it.
    private func chooseVideo() {
        guard let url = MediaPanel.choose([.movie], message: "Choose a background video").first else { return }

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
        guard let url = MediaPanel.choose([.image], message: "Choose a background image").first else { return }

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
        case .theme(let themeID):
            guard var theme = coordinator.project.theme(withID: themeID) else { return }
            theme.background = background
            coordinator.updateTheme(theme)
        }
    }
}
