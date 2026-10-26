import SwiftUI
import PresenterCore

/// The audience output's top layers, over the background and slide: props, a song's credits, then the message bar.
/// Drawn on the audience output and in the operator's Audience preview, so both match.
struct OverlayLayers: View {
    let coordinator: PresentationCoordinator
    /// An output's look can leave out the props or the message.
    var look = OutputLook.everything

    var body: some View {
        ZStack {
            if look.showsProps {
                ForEach(coordinator.audienceProps) { prop in
                    SlideRenderView(scene: .slide(RenderedSlide(slide: prop, background: .transparent)), transparency: .clear)
                }
            }
            if look.showsCredits, let credits = coordinator.audienceCredits {
                CreditsLine(text: credits)
            }
            if look.showsMessages, let (message, values) = coordinator.audienceMessage {
                MessageBar(coordinator: coordinator, message: message, values: values)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A message across the top or bottom of the output, sized for the 1920×1080 canvas and scaled to fit.
private struct MessageBar: View {
    let coordinator: PresentationCoordinator
    let message: MessageDefinition
    let values: [String: String]

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / SlideRenderView.canvasSize.width,
                            geometry.size.height / SlideRenderView.canvasSize.height)
            // Timer tokens tick, so the text is re-rendered every half second.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(coordinator.messageText(message, values: values, at: context.date))
                    .font(.system(size: message.fontSize * scale, weight: .semibold))
                    .foregroundStyle(message.textColor.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 40 * scale)
                    .padding(.vertical, 18 * scale)
                    .frame(maxWidth: .infinity)
                    .background(message.barColor.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: message.position == .top ? .top : .bottom)
        }
    }
}

/// A song's credits in small type at the bottom of the output, as CCLI asks for on its first and last slides. Sized
/// for the 1920×1080 canvas and scaled to fit, with a shadow so it reads over any background.
private struct CreditsLine: View {
    let text: String

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / SlideRenderView.canvasSize.width,
                            geometry.size.height / SlideRenderView.canvasSize.height)
            Text(text)
                .font(.system(size: 24 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.8), radius: 3 * scale, y: 1 * scale)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80 * scale)
                .padding(.bottom, 24 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
