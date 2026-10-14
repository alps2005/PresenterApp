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
                // Slides lay out the same wherever they're shown: a host list's one-line limit
                // (the editor's thumbnail sidebar) mustn't truncate slide text.
                .lineLimit(nil)
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

    /// Text without a box keeps the original centred, stacked layout, underneath everything placed in a frame.
    private var flowElements: [TextElement] {
        slide.elements.compactMap { if case .text(let text) = $0, text.box == nil { text } else { nil } }
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

            // Framed elements in list order, so later ones draw on top.
            ForEach(slide.elements) { element in
                if let frame = element.frame {
                    let rect = SlideRenderView.canvasRect(for: frame)
                    SlideElementView(element: element)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(width: SlideRenderView.canvasSize.width, height: SlideRenderView.canvasSize.height, alignment: .topLeading)
    }
}

extension SlideRenderView {
    /// A unit-coordinate frame in canvas points.
    static func canvasRect(for frame: NormalizedRect) -> CGRect {
        CGRect(
            x: frame.x * canvasSize.width,
            y: frame.y * canvasSize.height,
            width: frame.width * canvasSize.width,
            height: frame.height * canvasSize.height
        )
    }
}

/// One framed element, filling the frame it is given. Shared by the renderer and the slide editor's canvas.
struct SlideElementView: View {
    let element: SlideElement

    var body: some View {
        switch element {
        case .text(let text):
            StyledText(element: text)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: Alignment(
                        horizontal: text.style.alignment.horizontalAlignment,
                        vertical: (text.box?.verticalAlignment ?? .center).verticalAlignment
                    )
                )
        case .shape(let shape):
            ShapeElementView(shape: shape)
        case .image(let image):
            ImageElementView(image: image)
        }
    }
}

private struct ShapeElementView: View {
    let shape: ShapeElement

    var body: some View {
        switch shape.kind {
        case .rectangle: styled(Rectangle())
        case .roundedRectangle: styled(RoundedRectangle(cornerRadius: shape.cornerRadius))
        case .ellipse: styled(Ellipse())
        }
    }

    /// The outline is drawn inside the frame, so a thick stroke never spills past the element's bounds.
    private func styled(_ base: some InsettableShape) -> some View {
        base
            .fill(shape.fill?.color ?? .clear)
            .overlay {
                if let stroke = shape.stroke, shape.strokeWidth > 0 {
                    base.strokeBorder(stroke.color, lineWidth: shape.strokeWidth)
                }
            }
    }
}

/// An image element. A missing or still-decoding image shows a placeholder instead of nothing.
private struct ImageElementView: View {
    let image: ImageElement
    @Environment(MediaLibrary.self) private var mediaLibrary: MediaLibrary?

    var body: some View {
        Group {
            if let cgImage = mediaLibrary?.image(for: image.assetID) {
                let picture = Image(decorative: cgImage, scale: 1).resizable()
                switch image.scaling {
                case .fit: picture.aspectRatio(contentMode: .fit)
                case .fill: picture.aspectRatio(contentMode: .fill)
                case .stretch: picture
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.35)
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 96))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(image.opacity)
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
