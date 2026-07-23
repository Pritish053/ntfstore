// make-icon.swift — builds NTFStore's app icon from the source artwork.
// It takes the full-bleed squircle source (scripts/icon-source.png), applies
// macOS-standard padding and a rounded-rect mask (transparent corners), and
// writes every required size into an .iconset directory.
//
// Usage:   swift make-icon.swift <output.iconset-dir> [source.png]
// Then:    iconutil -c icns <output.iconset-dir> -o AppIcon.icns
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let srcPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "scripts/icon-source.png"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard let srcData = try? Data(contentsOf: URL(fileURLWithPath: srcPath)),
      let srcRep = NSBitmapImageRep(data: srcData) else {
    FileHandle.standardError.write("error: cannot read source image at \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}
let srcImg = NSImage(size: NSSize(width: srcRep.pixelsWide, height: srcRep.pixelsHigh))
srcImg.addRepresentation(srcRep)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS content area: squircle inset from the canvas so corners stay transparent.
    let inset = size * 0.075
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.2237
    let mask = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft contact shadow beneath the tile for depth in the Dock/Finder.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.03,
                  color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(mask); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Clip to the squircle and draw the source slightly over-scaled so its own
    // dark outer rim falls outside the mask, leaving clean transparent corners.
    ctx.addPath(mask); ctx.clip()
    let over = rect.width * 0.02
    let dst = rect.insetBy(dx: -over, dy: -over)
    srcImg.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in variants {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("Wrote \(variants.count) icon sizes to \(outDir)")
