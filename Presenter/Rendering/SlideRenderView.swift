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
            SlideBackground()
        case .slide(let slide):
            ZStack {
                SlideBackground()
                SlideContent(slide: slide)
            }
        }
    }
}

/// Placeholder for themes, which arrive in a later milestone.
private struct SlideBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct SlideContent: View {
    let slide: SlideDocument

    var body: some View {
        VStack(spacing: 48) {
            ForEach(slide.elements) { element in
                switch element {
                case .text(let text):
                    Text(text.text)
                        .font(font(for: text.role))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.25)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
        .padding(120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func font(for role: TextRole) -> Font {
        switch role {
        case .title: .system(size: 140, weight: .bold)
        case .body: .system(size: 96, weight: .semibold)
        case .caption: .system(size: 56, weight: .regular)
        }
    }
}
