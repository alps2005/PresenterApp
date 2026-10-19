import SwiftUI
import PresenterCore

/// Draws a stage layout: each region in its box, filled with what's live now. Used by the stage display and, at a
/// smaller size, by the layout editor's preview, so both look the same.
struct StageLayoutView: View {
    let coordinator: PresentationCoordinator
    let layout: StageLayout
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            // Sizes are designed for a 1080-point-tall screen and scale with the window.
            let scale = max(geometry.size.height / 1080, 0.05)
            ZStack(alignment: .topLeading) {
                ForEach(layout.regions) { region in
                    StageRegionView(coordinator: coordinator, region: region, now: now, scale: scale)
                        .frame(width: region.frame.width * geometry.size.width,
                               height: region.frame.height * geometry.size.height,
                               alignment: region.contentAlignment)
                        .clipped()
                        .offset(x: region.frame.x * geometry.size.width, y: region.frame.y * geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(layout.background.color)
    }
}

/// One region's content, filling its box.
struct StageRegionView: View {
    let coordinator: PresentationCoordinator
    let region: StageRegion
    let now: Date
    let scale: CGFloat

    private var size: CGFloat { region.fontSize * scale }

    var body: some View {
        switch region.kind {
        case .liveText:
            words(coordinator.state.live.map { StageText.words($0.slide, coordinator: coordinator, at: now) })
        case .nextText:
            if let next = coordinator.upNextSlide?.slide {
                VStack(alignment: region.alignment.horizontalAlignment, spacing: size * 0.1) {
                    if region.showsLabel {
                        label("NEXT" + (next.label.map { " · \($0.uppercased())" } ?? ""))
                    }
                    words(StageText.words(next, coordinator: coordinator, at: now))
                }
            }
        case .liveSlide:
            slide(coordinator.state.live.map { coordinator.outputPreview(of: $0.rendered) })
        case .nextSlide:
            slide(coordinator.upNextSlide.map { coordinator.outputPreview(of: $0) })
        case .clock:
            Text(now, format: .dateTime.hour().minute().second())
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(region.color.color)
                .minimumScaleFactor(0.2)
                .lineLimit(1)
        case .timer:
            if let timerID = region.timerID(stageTimerID: coordinator.project.stage.timerID),
               let timer = coordinator.timer(withID: timerID),
               let seconds = coordinator.timerSeconds(timerID, at: now) {
                VStack(alignment: region.alignment.horizontalAlignment, spacing: 0) {
                    if region.showsLabel { label(timer.name.uppercased()) }
                    Text(TimerDefinition.format(seconds))
                        .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(seconds < 0 && timer.isCountdown ? Color.red : region.color.color)
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                }
            }
        case .notes:
            words(coordinator.liveNotes, placeholder: nil)
        case .message:
            if let message = coordinator.state.stageMessage {
                Text(message)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(region.color.color)
                    .multilineTextAlignment(region.alignment.textAlignment)
                    .minimumScaleFactor(0.3)
                    .padding(.horizontal, size * 0.45)
                    .padding(.vertical, size * 0.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: region.contentAlignment)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: size * 0.22))
            }
        case .text(let text):
            words(text, placeholder: nil)
        }
    }

    /// Words that shrink to fit the box. Nil shows a dash, so an empty live slide doesn't look like a fault.
    private func words(_ text: String?, placeholder: String? = "—") -> some View {
        Text(text ?? placeholder ?? "")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(region.color.color)
            .multilineTextAlignment(region.alignment.textAlignment)
            .minimumScaleFactor(0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: region.contentAlignment)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(size * 0.36, 10 * scale), weight: .bold))
            .foregroundStyle(.gray)
            .lineLimit(1)
    }

    @ViewBuilder
    private func slide(_ rendered: RenderedSlide?) -> some View {
        if coordinator.state.isBlackout {
            Color.black
        } else if let rendered {
            SlideRenderView(scene: .slide(rendered))
                .aspectRatio(16 / 9, contentMode: .fit)
        }
    }
}

/// The words the stage shows for a slide.
enum StageText {
    static func words(_ slide: SlideDocument, coordinator: PresentationCoordinator, at date: Date) -> String {
        let text = slide.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }
}

extension StageRegion {
    /// Where the content sits in its box: at the top, on the region's side.
    var contentAlignment: Alignment {
        Alignment(horizontal: alignment.horizontalAlignment, vertical: .top)
    }
}
