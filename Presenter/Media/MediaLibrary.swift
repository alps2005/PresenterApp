import AVFoundation
import AppKit
import ImageIO
import Observation
import os
import PresenterCore

/// The app's media folder plus decoded images ready to draw. Images are decoded off the main actor
/// ahead of time, so taking a slide live never waits on (or flashes while) decoding a background.
@Observable
final class MediaLibrary {
    /// Large enough for a 4K output; bigger originals are downsampled to bound memory.
    nonisolated static let maxPixelSize = 3840

    /// `Application Support/Presenter/Media`, inside the app's sandbox container.
    static var defaultDirectory: URL {
        AppDirectories.data.appendingPathComponent("Media", isDirectory: true)
    }

    let store: MediaStore
    private(set) var images: [UUID: CGImage] = [:]
    /// Assets whose file is gone or can't be decoded. The renderer falls back to the default background.
    private(set) var missing: Set<UUID> = []
    @ObservationIgnored private var requested: Set<UUID> = []
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "Media")

    init(directory: URL = MediaLibrary.defaultDirectory) {
        store = MediaStore(directory: directory)
    }

    func image(for assetID: UUID) -> CGImage? {
        images[assetID]
    }

    func isMissing(_ assetID: UUID) -> Bool {
        missing.contains(assetID)
    }

    /// Records that an asset's file has gone since it was loaded (e.g. a video that can no longer play), and
    /// drops its picture, so previews and the output show the default background and the operator is warned.
    func markMissing(_ assetID: UUID) {
        missing.insert(assetID)
        images[assetID] = nil
    }

    /// Copies an image the operator picked into the media folder and starts decoding it.
    func importImage(at url: URL) async throws -> MediaAsset {
        let store = store
        let asset = try await Task.detached {
            // Files from the open panel are outside the sandbox until we claim access.
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            return try store.importImage(at: url)
        }.value
        logger.info("Imported \(asset.originalFilename, privacy: .public) as \(asset.id, privacy: .public)")
        preload([asset])
        return asset
    }

    /// Copies a video the operator picked into the media folder, after checking it plays, and makes its still.
    func importVideo(at url: URL) async throws -> MediaAsset {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let asset = try await store.importVideo(at: url)
        logger.info("Imported video \(asset.originalFilename, privacy: .public) as \(asset.id, privacy: .public)")
        preload([asset])
        return asset
    }

    /// Decodes any of these assets not already loaded or loading. A video's image is its first frame, used for
    /// thumbnails and previews.
    func preload(_ assets: [MediaAsset]) {
        for asset in assets where !requested.contains(asset.id) {
            requested.insert(asset.id)
            let url = store.url(for: asset)
            let kind = asset.kind
            Task {
                let image: CGImage? = switch kind {
                case .image: await Task.detached { Self.decode(url) }.value
                case .video: await Self.firstFrame(of: url)
                }
                if let image {
                    images[asset.id] = image
                } else {
                    missing.insert(asset.id)
                    logger.error("Media missing or unreadable: \(asset.originalFilename, privacy: .public) (\(asset.id, privacy: .public))")
                }
            }
        }
    }

    private nonisolated static func firstFrame(of url: URL) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
    }

    private nonisolated static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
