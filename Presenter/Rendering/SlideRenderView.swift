import SwiftUI
import PresenterCore

/// Draws a scene on a fixed 1920×1080 canvas scaled to fit, so thumbnails, the live preview and the
/// audience output all lay text out identically.
struct SlideRenderView: View {
    static let canvasSize = CGSize(width: 1920, height: 1080)

    /// How a transparent background is drawn: a checkerboard in the operator's previews, nothing at all on the
    /// audience output's slide layer (the background layer underneath shows through).
    enum Transparency {
        case checkerboard
        case clear
    }

    let scene: AudienceScene
    var transparency: Transparency = .checkerboard

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
        // Letterboxing: black, except on a transparent layer, where the layer below provides it.
        .background(transparency == .clear ? Color.clear : Color.black)
        .clipped()
        .environment(\.slideTransparency, transparency)
    }

    @ViewBuilder
    private var canvas: some View {
        switch scene {
        case .black:
            Color.black
        case .empty:
            DefaultBackground()
        case .background(let background):
            BackgroundLayer(background: background)
        case .slide(let rendered):
            ZStack {
                BackgroundLayer(background: rendered.background)
                SlideContent(slide: rendered.slide)
            }
        }
    }
}

/// How operator previews show a transparent background, as ProPresenter does.
private struct Checkerboard: View {
    private static let square: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.82)))
            let columns = Int((size.width / Self.square).rounded(.up))
            let rows = Int((size.height / Self.square).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * Self.square, y: CGFloat(row) * Self.square,
                                      width: Self.square, height: Self.square)
                    context.fill(Path(rect), with: .color(Color(white: 0.62)))
                }
            }
        }
    }
}

private struct ShowsLiveVideoKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SlideTransparencyKey: EnvironmentKey {
    static let defaultValue = SlideRenderView.Transparency.checkerboard
}

extension EnvironmentValues {
    /// True on the audience output and its preview: video backgrounds show the playing video, not a still.
    var showsLiveVideo: Bool {
        get { self[ShowsLiveVideoKey.self] }
        set { self[ShowsLiveVideoKey.self] = newValue }
    }

    var slideTransparency: SlideRenderView.Transparency {
        get { self[SlideTransparencyKey.self] }
        set { self[SlideTransparencyKey.self] = newValue }
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
    @Environment(MediaPlaybackController.self) private var playback: MediaPlaybackController?
    @Environment(\.slideTransparency) private var transparency
    @Environment(\.showsLiveVideo) private var showsLiveVideo

    var body: some View {
        switch background {
        case nil:
            DefaultBackground()
        case .transparent:
            if transparency == .checkerboard {
                Checkerboard()
            } else {
                Color.clear
            }
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
        case .video(let video):
            // The audience output and the Audience preview show the playing video; everything else shows its
            // first frame. A missing file shows the default background.
            ZStack {
                Color.black
                if showsLiveVideo, let playback, playback.assetID == video.assetID {
                    VideoPlayerLayerView(player: playback.player, scaling: video.scaling)
                        .frame(width: SlideRenderView.canvasSize.width, height: SlideRenderView.canvasSize.height)
                } else if let poster = mediaLibrary?.image(for: video.assetID) {
                    scaled(Image(decorative: poster, scale: 1), scaling: video.scaling)
                } else {
                    DefaultBackground()
                }
                Color.black.opacity(video.dimming)
            }
            .clipped()
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
