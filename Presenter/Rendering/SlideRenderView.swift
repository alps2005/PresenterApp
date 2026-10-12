import SwiftUI
import PresenterCore

/// Draws a scene on a fixed 1920×1080 canvas scaled to fit, so thumbnails, the live preview and the
/// audience output all lay text out identically.
struct SlideRenderView: View {
    static let canvasSize = CGSize(width: 1920, height: 1080)

    let scene: AudienceScene

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / Self.canvasSize.width,
                proxy.size.height / Self.canvasSize.height
            )
            canvas
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .clipped()
    }

    @ViewBuilder
    private var canvas: some View {
        switch scene {
        case .black:
            Color.black
        case .empty:
            DefaultBackground()
        case .slide(let rendered):
            ZStack {
                BackgroundLayer(background: rendered.background)
                SlideContent(slide: rendered.slide)
            }
        }
    }
}

/// The app's background when neither the slide nor its presentation sets one.
private struct DefaultBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A slide's resolved background. An image that is missing or still decoding shows the default background.
private struct BackgroundLayer: View {
    let background: SlideBackground?
    @Environment(MediaLibrary.self) private var mediaLibrary: MediaLibrary?

    var body: some View {
        switch background {
        case nil:
            DefaultBackground()
        case .color(let color):
            color.color
        case .image(let image):
            if let cgImage = mediaLibrary?.image(for: image.assetID) {
                ZStack {
                    Color.black
                    scaled(Image(decorative: cgImage, scale: 1), scaling: image.scaling)
                    Color.black.opacity(image.dimming)
                }
                .clipped()
            } else {
                DefaultBackground()
            }
        }
    }

    @ViewBuilder
    private func scaled(_ image: Image, scaling: ImageScaling) -> some View {
        switch scaling {
        case .fill:
            image.resizable().aspectRatio(contentMode: .fill)
                .frame(width: SlideRenderView.canvasSize.width, height: SlideRenderView.canvasSize.height)
        case .fit:
            image.resizable().aspectRatio(contentMode: .fit)
        case .stretch:
            image.resizable()
        }
    }
}

private struct SlideContent: View {
    let slide: SlideDocument

    /// Text without a box keeps the original centred, stacked layout.
    private var flowElements: [TextElement] {
        slide.elements.compactMap { if case .text(let text) = $0, text.box == nil { text } else { nil } }
    }

    private var boxedElements: [(TextElement, TextBox)] {
        slide.elements.compactMap { if case .text(let text) = $0, let box = text.box { (text, box) } else { nil } }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 48) {
                ForEach(flowElements) { text in
                    StyledText(element: text)
                }
            }
            .padding(120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(boxedElements, id: \.0.id) { text, box in
                let size = SlideRenderView.canvasSize
                let frame = CGRect(
                    x: box.frame.x * size.width,
                    y: box.frame.y * size.height,
                    width: box.frame.width * size.width,
                    height: box.frame.height * size.height
                )
                StyledText(element: text)
                    .frame(
                        width: frame.width,
                        height: frame.height,
                        alignment: Alignment(
                            horizontal: text.style.alignment.horizontalAlignment,
                            vertical: box.verticalAlignment.verticalAlignment
                        )
                    )
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: SlideRenderView.canvasSize.width, height: SlideRenderView.canvasSize.height, alignment: .topLeading)
    }
}

private struct StyledText: View {
    let element: TextElement

    var body: some View {
        let style = element.style
        Text(element.text)
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .multilineTextAlignment(style.alignment.textAlignment)
            .foregroundStyle(style.color.color)
            .shadow(color: .black.opacity(style.hasShadow ? 0.6 : 0), radius: 6, y: 3)
            .minimumScaleFactor(0.25)
    }
}
