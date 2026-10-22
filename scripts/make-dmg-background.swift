// Draws the DMG window's background: an arrow from the app to the Applications shortcut and a line saying what to
// do. Writes background.png (600×420) and background@2x.png into a folder; combine them for Retina with
// `tiffutil -cathidpicheck background.png background@2x.png -out background.tiff`. The icon positions in
// scripts/dmg-settings.py must match the ones here.
//
// Finder draws the icon names in black in Light Mode and in white in Dark Mode, whatever the picture, so the
// background is a mid-tone blue that both stay readable on.
//
// Usage: swift scripts/make-dmg-background.swift <output folder>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("Usage: make-dmg-background.swift <output folder>")
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1])

let size = CGSize(width: 600, height: 420)
let appCenter = CGPoint(x: 160, y: 145)          // From the top left, like Finder's icon positions.
let applicationsCenter = CGPoint(x: 440, y: 145)

func draw(in context: CGContext) {
    // Flip to top-left coordinates so the numbers match the icon positions.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)

    let colors = [CGColor(srgbRed: 0.24, green: 0.51, blue: 0.93, alpha: 1),
                  CGColor(srgbRed: 0.17, green: 0.42, blue: 0.85, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // The arrow, between the two 128-point icons.
    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let y = appCenter.y
    let start = appCenter.x + 84, end = applicationsCenter.x - 84
    context.setAlpha(0.9)
    context.beginTransparencyLayer(auxiliaryInfo: nil)   // So the line doesn't show through the head.
    context.setStrokeColor(white)
    context.setLineWidth(6)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: start, y: y))
    context.addLine(to: CGPoint(x: end - 10, y: y))
    context.strokePath()
    context.setFillColor(white)
    context.move(to: CGPoint(x: end + 4, y: y))
    context.addLine(to: CGPoint(x: end - 20, y: y - 16))
    context.addLine(to: CGPoint(x: end - 20, y: y + 16))
    context.closePath()
    context.fillPath()
    context.endTransparencyLayer()
    context.setAlpha(1)

    // Text, drawn unflipped by AppKit in a flipped graphics context.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    func line(_ text: String, top: CGFloat, font: NSFont, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: centered,
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(in: CGRect(x: 0, y: top, width: size.width, height: 30))
    }
    line("Drag Presenter to Applications", top: 258, font: .systemFont(ofSize: 20, weight: .semibold), alpha: 1)
    line("Then eject this disk and open Presenter from Applications.", top: 288,
         font: .systemFont(ofSize: 13), alpha: 0.85)
    NSGraphicsContext.current = nil
}

for scale in [1, 2] {
    let context = CGContext(data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw(in: context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    bitmap.size = size   // 72 dpi at 1×, 144 dpi at 2×, so tiffutil pairs them.
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
print("Wrote background.png and background@2x.png to \(folder.path)")
