#if canImport(AVFoundation) && canImport(ImageIO)
import AVFoundation
import Foundation
import ImageIO

/// The Mac's media checks: ImageIO decodes the image's header, AVFoundation says whether a video or sound plays.
public struct AppleMediaProbe: MediaProbe {
    public init() {}

    public func imageSize(at url: URL) -> (width: Int, height: Int)? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    public func video(at url: URL) async -> (width: Int, height: Int, duration: Double)? {
        let asset = AVURLAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else {
            return nil
        }
        // Width and height as shown, after any rotation the file asks for.
        let shown = size.applying(transform)
        return (Int(abs(shown.width).rounded()), Int(abs(shown.height).rounded()), duration.seconds)
    }

    public func audioDuration(at url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable,
              let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let duration = try? await asset.load(.duration) else {
            return nil
        }
        return duration.seconds
    }
}
#endif
