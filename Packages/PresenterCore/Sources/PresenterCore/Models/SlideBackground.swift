import Foundation

/// What is drawn behind a slide's text. A presentation sets a default; a slide can override it.
public enum SlideBackground: Codable, Hashable, Sendable {
    case color(RGBAColor)
    case image(ImageBackground)
    /// No background of its own, like ProPresenter's empty (checkerboard) background: taking the slide live
    /// leaves whatever background is already on the audience output.
    case transparent

    /// The media asset this background needs, if any.
    public var assetID: UUID? {
        if case .image(let image) = self { return image.assetID }
        return nil
    }
}

public struct ImageBackground: Codable, Hashable, Sendable {
    public static let dimmingRange: ClosedRange<Double> = 0...0.8

    public var assetID: UUID
    public var scaling: ImageScaling
    /// Opacity of a black layer over the image, so text stays readable on busy pictures.
    public var dimming: Double

    public init(assetID: UUID, scaling: ImageScaling = .fill, dimming: Double = 0) {
        self.assetID = assetID
        self.scaling = scaling
        self.dimming = dimming
    }
}

public enum ImageScaling: String, Codable, Hashable, Sendable, CaseIterable {
    /// Cover the whole canvas, cropping the image if needed.
    case fill
    /// Show the whole image, letterboxed if needed.
    case fit
    /// Distort the image to exactly cover the canvas.
    case stretch
}
