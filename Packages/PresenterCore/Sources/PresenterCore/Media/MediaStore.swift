import Foundation

public enum MediaImportError: Error, Equatable, Sendable {
    /// The file isn't an image this computer can decode.
    case unreadableImage
    /// The file isn't a video this computer can play.
    case unplayableVideo
    /// The file isn't audio this computer can play.
    case unplayableAudio
    case copyFailed(String)
}

/// Looks inside a media file before it's copied in: whether this computer can show or play it, and its size and
/// length. Each platform answers with its own frameworks: ImageIO and AVFoundation on a Mac (`AppleMediaProbe`).
public protocol MediaProbe: Sendable {
    /// The image's width and height in pixels, or nil if it isn't an image this computer can decode.
    func imageSize(at url: URL) -> (width: Int, height: Int)?
    /// The video's width and height as shown (after any rotation the file asks for) and its length in seconds, or
    /// nil if it isn't a video this computer can play.
    func video(at url: URL) async -> (width: Int, height: Int, duration: Double)?
    /// The audio's length in seconds, or nil if it isn't audio this computer can play.
    func audioDuration(at url: URL) async -> Double?
}

/// Keeps copies of imported media in one folder, named by UUID, so backgrounds keep working when the
/// operator moves or deletes the original file. UI-free; the app wraps it with decoding and caching.
public struct MediaStore: Sendable {
    public let directory: URL
    private let probe: any MediaProbe

#if canImport(AVFoundation) && canImport(ImageIO)
    public init(directory: URL, probe: any MediaProbe = AppleMediaProbe()) {
        self.directory = directory
        self.probe = probe
    }
#else
    /// Off Apple platforms the app passes the probe, from the frameworks it plays media with.
    public init(directory: URL, probe: any MediaProbe) {
        self.directory = directory
        self.probe = probe
    }
#endif

    /// Checks that `source` is a readable image, copies it into the store and describes the copy.
    public func importImage(at source: URL) throws -> MediaAsset {
        guard let size = probe.imageSize(at: source) else { throw MediaImportError.unreadableImage }
        let id = UUID()
        let storedFilename = try copyIn(source, as: id, defaultExtension: "img")
        return MediaAsset(
            id: id,
            kind: .image,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: size.width,
            pixelHeight: size.height
        )
    }

    /// Checks that `source` is a playable video, copies it into the store and describes the copy.
    public func importVideo(at source: URL) async throws -> MediaAsset {
        guard let video = await probe.video(at: source), video.duration > 0 else {
            throw MediaImportError.unplayableVideo
        }
        let id = UUID()
        let storedFilename = try copyIn(source, as: id, defaultExtension: "mov")
        return MediaAsset(
            id: id,
            kind: .video,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: video.width,
            pixelHeight: video.height,
            duration: video.duration
        )
    }

    /// Checks that `source` is playable audio, copies it into the store and describes the copy.
    public func importAudio(at source: URL) async throws -> MediaAsset {
        guard let duration = await probe.audioDuration(at: source), duration > 0 else {
            throw MediaImportError.unplayableAudio
        }
        let id = UUID()
        let storedFilename = try copyIn(source, as: id, defaultExtension: "m4a")
        return MediaAsset(
            id: id,
            kind: .audio,
            originalFilename: source.lastPathComponent,
            storedFilename: storedFilename,
            pixelWidth: 0,
            pixelHeight: 0,
            duration: duration
        )
    }

    /// Copies `source` into the folder named by the asset's ID, keeping its extension (lowercased), and returns the name.
    private func copyIn(_ source: URL, as id: UUID, defaultExtension: String) throws -> String {
        let fileExtension = source.pathExtension.isEmpty ? defaultExtension : source.pathExtension.lowercased()
        let storedFilename = "\(id.uuidString).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storedFilename))
        } catch {
            throw MediaImportError.copyFailed(error.localizedDescription)
        }
        return storedFilename
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
