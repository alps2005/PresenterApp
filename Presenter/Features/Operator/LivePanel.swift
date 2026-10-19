import SwiftUI
import PresenterCore

/// Shows exactly what the audience sees, plus what comes next and what is cued.
struct LivePanel: View {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let onEditProps: (UUID?) -> Void
    @Environment(MediaLibrary.self) private var mediaLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    PanelHeader(title: "Audience") { liveBadge }
                    // In words, here, because the toolbar's output menu shows only a warning icon.
                    ForEach(disconnectedOutputs, id: \.role) { output in
                        WarningLabel(
                            "\(output.role.title): \(output.displayName) disconnected. It comes back full screen when you reconnect it.",
                            font: .callout.bold()
                        )
                    }
                    // The output's own view, so slide and element transitions play here too.
                    AudienceOutputView(coordinator: coordinator)
                        .environment(\.showsLiveVideo, true)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .tileFrame(audienceTileState)
                        .accessibilityLabel("Audience output preview")
                    if hasMissingMedia(coordinator.state.liveBackground), !coordinator.state.isBlackout {
                        missingMediaWarning(coordinator.state.liveBackground)
                    } else if case .video = coordinator.state.liveBackground, !coordinator.state.isBlackout {
                        TransportControls()
                    }
                    AudioTransport(coordinator: coordinator)
                    AutoAdvanceStatus(coordinator: coordinator)
                    if coordinator.clearedBackgroundReturnsWithNextSlide {
                        Label("Background cleared for now. Slides with their own background bring one back. To remove it for good, use the slide's Background button.",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = coordinator.liveNotes {
                        Label(notes, systemImage: "note.text")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help("This slide's notes. The audience never sees them.")
                    }
                    if coordinator.liveSlideHasPendingEdits {
                        Label("This slide was edited after going live. Take it live again to show the changes.",
                              systemImage: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.edited)
                    }
                }

                // Shown as it will appear: a transparent slide over the background that's on screen.
                slot(title: "Up Next", slide: coordinator.upNextSlide.map { coordinator.outputPreview(of: $0) },
                     placeholder: upNextPlaceholder, tile: .idle)
                slot(title: "Cued", slide: coordinator.previewSlide, placeholder: "Nothing cued", tile: .cued)

                Divider()
                ShowControls(coordinator: coordinator, outputManager: outputManager, onEditProps: onEditProps)
            }
            .padding(Spacing.lg)
            .overflowGuard("Live panel", minimumWidth: Widths.livePanelWidths.lowerBound)
        }
        .hardScrollEdges()
        .solidPanel()
    }

    /// Outputs whose chosen display has gone. Each is hidden until its display comes back.
    private var disconnectedOutputs: [(role: OutputRole, displayName: String)] {
        OutputRole.allCases.compactMap { role in
            if case .displayMissing(let name) = outputManager.status(role) { (role, name) } else { nil }
        }
    }

    /// Red while something is on the audience output, so the preview reads as live at a glance.
    private var audienceTileState: TileState {
        let state = coordinator.state
        return !state.isBlackout && (state.live != nil || state.liveBackground != nil) ? .live : .idle
    }

    private func missingMediaWarning(_ background: SlideBackground?) -> some View {
        let kind = if case .video = background { "video" } else { "image" }
        return WarningLabel("Background \(kind) missing. The default background is showing.")
    }

    /// The background's image or video is missing or unreadable, so the default background shows instead.
    private func hasMissingMedia(_ background: SlideBackground?) -> Bool {
        guard let assetID = background?.assetID else { return false }
        return mediaLibrary.isMissing(assetID)
    }

    private var upNextPlaceholder: String {
        guard let live = coordinator.state.live else { return "Nothing live" }
        // The live slide (or its playlist item) was deleted, so there is no sequence to follow.
        if coordinator.project.slide(at: live.position) == nil { return "Live slide is no longer in the playlist" }
        return "End of playlist"
    }

    @ViewBuilder
    private var liveBadge: some View {
        if coordinator.state.isBlackout {
            StateBadge(.blackout)
        } else if coordinator.state.live != nil {
            StateBadge(.live)
        } else if coordinator.state.liveBackground != nil {
            StateBadge(.backgroundOnly)
        } else if coordinator.state.cleared != nil {
            StateBadge(.cleared)
        } else {
            StateBadge(.nothingLive)
        }
    }

    private func slot(title: String, slide: RenderedSlide?, placeholder: String, tile: TileState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.sectionHeader).foregroundStyle(.secondary)
            if let slide {
                SlideRenderView(scene: .slide(slide))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .tileFrame(tile)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("\(title) slide preview")
                if hasMissingMedia(slide.background) {
                    missingMediaWarning(slide.background)
                }
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
