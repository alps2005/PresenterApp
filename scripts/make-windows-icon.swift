// Makes the Windows app's icon from the Mac app's, so both apps look the same. Renders Presenter/AppIcon.icon with
// Icon Composer's ictool, which draws it filling the square (no Mac margin), and writes an .ico with the sizes Windows
// asks for.
//
// The sizes up to 64 are plain bitmaps and 256 is a PNG, which is how Windows' own icons are stored. CI builds on
// Windows without ictool, so the .ico is committed: run this again when the Mac icon changes.
//
// Usage: swift scripts/make-windows-icon.swift Presenter/AppIcon.icon Windows/Presenter.Windows/Assets/Presenter.ico
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: make-windows-icon.swift <AppIcon.icon> <output.ico>")
    exit(2)
}
let sizes = [16, 20, 24, 32, 40, 48, 64, 256]

func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

func render(_ iconBundle: String) -> CGImage {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("icon.png")

    let ictool = Process()
    // Icon Composer's own ictool: `xcrun ictool` finds a different tool of that name, which can't export images.
    // Design generation 26 is what the Mac release's Xcode draws, so both apps get the same picture.
    ictool.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")
    ictool.arguments = [iconBundle, "--export-image", "--output-file", output.path,
                        "--platform", "macOS", "--rendition", "Default",
                        "--width", "1024", "--height", "1024", "--scale", "1", "--design-generation", "26"]
    ictool.standardOutput = FileHandle.nullDevice
    do { try ictool.run() } catch { fail("Couldn't run ictool: \(error)") }
    ictool.waitUntilExit()
    // Read into memory first: the image decodes when it's first used, after the temporary file has gone.
    guard ictool.terminationStatus == 0,
          let data = try? Data(contentsOf: output),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("ictool didn't render \(iconBundle).") }
    return image
}

/// Straight (not premultiplied) RGBA isn't a format CoreGraphics draws into, so drawing is premultiplied and
/// `bitmap(_:)` undoes that where a file needs it.
func context(_ width: Int, _ height: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("Couldn't make a \(width)×\(height) drawing context.") }
    context.interpolationQuality = .high
    return context
}

/// Halves step by step, because one big jump to 16×16 would lose the thin lines and leave them speckled.
func scaled(_ image: CGImage, to size: Int) -> CGContext {
    var current = image
    while current.width / 2 >= size {
        let half = context(current.width / 2, current.height / 2)
        half.draw(current, in: CGRect(x: 0, y: 0, width: half.width, height: half.height))
        guard let next = half.makeImage() else { fail("Couldn't scale the icon.") }
        current = next
    }
    let final = context(size, size)
    final.draw(current, in: CGRect(x: 0, y: 0, width: size, height: size))
    return final
}

func png(_ canvas: CGContext) -> Data {
    let data = NSMutableData()
    guard let image = canvas.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { fail("Couldn't make the PNG.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Couldn't write the PNG.") }
    return data as Data
}

extension Data {
    mutating func append(littleEndian value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(littleEndian value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}

/// An icon's bitmap: a header, the pixels from the bottom row up as BGRA, and a one-bit mask (unused with alpha, but
/// the format requires it). The header gives twice the height because it counts the mask too.
func bitmap(_ canvas: CGContext) -> Data {
    guard let pixels = canvas.data?.assumingMemoryBound(to: UInt8.self) else { fail("Couldn't read the scaled icon.") }
    let size = canvas.width
    let maskRowBytes = ((size + 31) / 32) * 4

    var data = Data()
    data.append(littleEndian: UInt32(40))                       // Header size.
    data.append(littleEndian: UInt32(size))
    data.append(littleEndian: UInt32(size * 2))
    data.append(littleEndian: UInt16(1))                        // Planes.
    data.append(littleEndian: UInt16(32))                       // Bits per pixel.
    data.append(littleEndian: UInt32(0))                        // No compression.
    data.append(littleEndian: UInt32(size * size * 4 + size * maskRowBytes))
    for _ in 0 ..< 4 { data.append(littleEndian: UInt32(0)) }   // Resolution and palette, unused.

    // The canvas's first row in memory is the top of the picture, so the file's order is the reverse.
    for y in stride(from: size - 1, through: 0, by: -1) {
        for x in 0 ..< size {
            let pixel = pixels + (y * size + x) * 4
            let alpha = Int(pixel[3])
            func straight(_ value: UInt8) -> UInt8 {
                alpha == 0 ? 0 : UInt8(Swift.min(255, (Int(value) * 255 + alpha / 2) / alpha))
            }
            data.append(contentsOf: [straight(pixel[2]), straight(pixel[1]), straight(pixel[0]), pixel[3]])
        }
    }
    data.append(Data(count: size * maskRowBytes))
    return data
}

let icon = render(arguments[1])
let images = sizes.map { size -> (size: Int, data: Data) in
    let canvas = scaled(icon, to: size)
    return (size, size == 256 ? png(canvas) : bitmap(canvas))
}

var file = Data()
file.append(littleEndian: UInt16(0))            // Reserved.
file.append(littleEndian: UInt16(1))            // 1 = icon.
file.append(littleEndian: UInt16(images.count))
var offset = 6 + 16 * images.count
for image in images {
    file.append(UInt8(image.size == 256 ? 0 : image.size))  // 0 means 256.
    file.append(UInt8(image.size == 256 ? 0 : image.size))
    file.append(UInt8(0))                                   // No palette.
    file.append(UInt8(0))                                   // Reserved.
    file.append(littleEndian: UInt16(1))                    // Planes.
    file.append(littleEndian: UInt16(32))                   // Bits per pixel.
    file.append(littleEndian: UInt32(image.data.count))
    file.append(littleEndian: UInt32(offset))
    offset += image.data.count
}
for image in images { file.append(image.data) }

let output = URL(fileURLWithPath: arguments[2])
do {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try file.write(to: output)
} catch {
    fail("Couldn't write \(output.path): \(error)")
}
print("Wrote \(output.path): \(file.count) bytes, sizes \(sizes.map(String.init).joined(separator: ", ")).")
