import SwiftUI
import PresenterCore

/// Shows exactly what the audience sees, plus what comes next and what is cued.
struct LivePanel: View {
    let coordinator: PresentationCoordinator
    @Environment(MediaLibrary.self) private var mediaLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Audience").font(.headline)
                        Spacer()
                        liveBadge
                    }
                    SlideRenderView(scene: coordinator.audienceScene)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(coordinator.state.live == nil ? Color.secondary.opacity(0.4) : .red, lineWidth: 2)
                        }
                    if hasMissingImage(coordinator.state.live?.rendered) {
                        missingImageWarning
                    }
                    if coordinator.liveSlideHasPendingEdits {
                        Label("This slide was edited after going live. Take it live again to show the changes.",
                              systemImage: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                slot(title: "Up Next", slide: coordinator.upNextSlide, placeholder: upNextPlaceholder)
                slot(title: "Cued", slide: coordinator.previewSlide, placeholder: "Nothing cued")
            }
            .padding(16)
        }
    }

    private var missingImageWarning: some View {
        Label("Background image missing. The default background is showing.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func hasMissingImage(_ slide: RenderedSlide?) -> Bool {
        guard let assetID = slide?.background?.assetID else { return false }
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
            StateBadge(text: "BLACKOUT", color: .black)
        } else if coordinator.state.live != nil {
            StateBadge(text: "LIVE", color: .red)
        } else if coordinator.state.cleared != nil {
            StateBadge(text: "CLEARED", color: .gray)
        } else {
            StateBadge(text: "NOTHING LIVE", color: .gray)
        }
    }

    private func slot(title: String, slide: RenderedSlide?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            if let slide {
                SlideRenderView(scene: .slide(slide))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 220)
                if hasMissingImage(slide) {
                    missingImageWarning
                }
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
