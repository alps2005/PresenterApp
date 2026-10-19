import AVFoundation
import Foundation
import ImageIO

public enum MediaImportError: Error, Equatable, Sendable {
    /// The file isn't an image ImageIO can decode.
    case unreadableImage
    /// The file isn't a video this Mac can play.
    case unplayableVideo
    /// The file isn't audio this Mac can play.
    case unplayableAudio
    case copyFailed(String)
}

/// Keeps copies of imported media in one folder, named by UUID, so backgrounds keep working when the
/// operator moves or deletes the original file. UI-free; the app wraps it with decoding and caching.
public struct MediaStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Checks that `source` is a readable image, copies it into the store and describes the copy.
    public func importImage(at source: URL) throws -> MediaAsset {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw MediaImportError.unreadableImage
        }

        let id = UUID()
        let fileExtension = source.pathExtension.isEmpty ? "img" : source.pathExtension.lowercased()
        let storedFilename = "\(id.uuidString).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storedFilename))
        } catch {
            throw MediaImportError.copyFailed(error.localizedDescription)
        }

        return MediaAsset(
            id: id,
            kind: .image,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    /// Checks that `source` is a playable video, copies it into the store and describes the copy.
    public func importVideo(at source: URL) async throws -> MediaAsset {
        let asset = AVURLAsset(url: source)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration), duration.seconds > 0 else {
            throw MediaImportError.unplayableVideo
        }
        // Width and height as shown, after any rotation the file asks for.
        let shown = size.applying(transform)
        let id = UUID()
        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let storedFilename = "\(id.uuidString).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storedFilename))
        } catch {
            throw MediaImportError.copyFailed(error.localizedDescription)
        }
        return MediaAsset(
            id: id,
            kind: .video,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: Int(abs(shown.width).rounded()),
            pixelHeight: Int(abs(shown.height).rounded()),
            duration: duration.seconds
        )
    }

    /// Checks that `source` is playable audio, copies it into the store and describes the copy.
    public func importAudio(at source: URL) async throws -> MediaAsset {
        let asset = AVURLAsset(url: source)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable,
              let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let duration = try? await asset.load(.duration), duration.seconds > 0 else {
            throw MediaImportError.unplayableAudio
        }
        let id = UUID()
        let fileExtension = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let storedFilename = "\(id.uuidString).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storedFilename))
        } catch {
            throw MediaImportError.copyFailed(error.localizedDescription)
        }
        return MediaAsset(
            id: id,
            kind: .audio,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: 0,
            pixelHeight: 0,
            duration: duration.seconds
        )
    }

    public func url(for asset: MediaAsset) -> URL {
        directory.appendingPathComponent(asset.storedFilename)
    }

    public func fileExists(for asset: MediaAsset) -> Bool {
        FileManager.default.fileExists(atPath: url(for: asset).path)
    }

    /// The names of the files in the media folder.
    public func filenames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Deletes the files among `candidates` not named in `storedFilenames`, for media deleted from the project.
    /// Returns the names removed. Failures are skipped; an extra file is harmless.
    @discardableResult
    public func removeFiles(among candidates: [String], keeping storedFilenames: Set<String>) -> [String] {
        candidates.filter { name in
            guard !storedFilenames.contains(name) else { return false }
            return (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil
        }
    }
}
