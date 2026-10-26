import AppKit
import PDFKit

/// Renders a PDF's pages as pictures for slides: a sermon deck exported from Keynote, PowerPoint or Google Slides.
enum PDFPages {
    enum Failure: LocalizedError {
        case unreadable
        case noPages
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "That PDF couldn't be opened. It may be damaged or password-protected."
            case .noPages: "That PDF has no pages."
            case .writeFailed: "The pages couldn't be saved as pictures."
            }
        }
    }

    /// Writes each page as a PNG into `folder`, at most `maxPixels` on its long side, on white like paper. Returns
    /// the files in page order. `progress` gets the number of pages done and the total.
    nonisolated static func render(_ url: URL, into folder: URL, maxPixels: Int,
                                   progress: @Sendable (Int, Int) -> Void) throws -> [URL] {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        guard document.pageCount > 0 else { throw Failure.noPages }
        if document.isLocked { throw Failure.unreadable }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.deletingPathExtension().lastPathComponent
        var files: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .cropBox)
            // A page turned on its side is drawn turned.
            let turned = page.rotation % 180 != 0
            let width = turned ? bounds.height : bounds.width
            let height = turned ? bounds.width : bounds.height
            guard width > 0, height > 0 else { continue }
            let scale = Double(maxPixels) / max(width, height)
            let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
            let image = page.thumbnail(of: size, for: .cropBox)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.writeFailed }
            let file = folder.appendingPathComponent("\(name) page \(index + 1).png")
            do {
                try png.write(to: file)
            } catch {
                throw Failure.writeFailed
            }
            files.append(file)
            progress(index + 1, document.pageCount)
        }
        return files
    }
}
