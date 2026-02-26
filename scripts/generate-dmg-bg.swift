#!/usr/bin/env swift
import Cocoa

// DMG background for Tokenomics
// Canvas: 1080x760 @2x (540x380pt DMG window)
// Composites install-image.png (arrow + text, designed @2x) onto #DCD3C0 background

let canvasW = 1080  // @2x pixels
let canvasH = 760

// --- Resolve paths ---
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let projectRoot = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let imagePath = projectRoot + "/Tokenomics/Resources/install-image.png"

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : projectRoot + "/Tokenomics/Resources/dmg-background.png"

// --- Load install image ---
guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
      let nsImage = NSImage(data: imageData),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("ERROR: Could not load \(imagePath)")
    exit(1)
}

// Image is 312x240 @2x pixels (156x120pt)
let imgW = CGFloat(cgImage.width)   // 312
let imgH = CGFloat(cgImage.height)  // 240

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: canvasW, height: canvasH,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("ERROR: Could not create CGContext")
    exit(1)
}

// --- Layer 1: #DCD3C0 background ---
ctx.setFillColor(red: 220/255, green: 211/255, blue: 192/255, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

// --- Layer 2: Composite install-image.png ---
// All positions in @2x pixels since the canvas is @2x.
//
// Icon positions (create-dmg uses pt, here converted to @2x):
//   App icon center:  128pt → 256px
//   Folder center:    412pt → 824px
//   Icon Y center:    185pt → 370px
//   Icon size:        128pt → 256px
//
// Image: 312x240px, centered horizontally on canvas.
let imgX = (CGFloat(canvasW) - imgW) / 2  // 384

// Vertically: arrow is roughly the top 60% of image (~144px).
// Align arrow's visual center (~72px from top) with icon center (370px from top).
// CG y-up: icon center at canvasH - 370 = 390 from bottom.
// Image top = 390 + 72 = 462 from bottom → image origin (bottom) = 462 - imgH = 222
let iconCenterY_fromBottom = CGFloat(canvasH) - 370.0
let arrowCenterFromBottom = imgH - 72.0  // 72px from top = 168px from bottom
let imgY = iconCenterY_fromBottom - arrowCenterFromBottom  // align arrow center with icon center

ctx.draw(cgImage, in: CGRect(x: imgX, y: imgY, width: imgW, height: imgH))

// --- Save ---
guard let outputImage = ctx.makeImage() else {
    print("ERROR: Could not create output image")
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: outputImage)
rep.size = NSSize(width: canvasW / 2, height: canvasH / 2) // @2x
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("ERROR: Could not encode PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    print("ERROR: Could not write file — \(error)")
    exit(1)
}
print("Saved DMG background to \(outputPath)")
