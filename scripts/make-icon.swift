#!/usr/bin/env swift
//
// make-icon.swift — generates MyTime's app icon (a distinctive hourglass).
//
// Usage: swift scripts/make-icon.swift <output-dir>
//   Writes <output-dir>/AppIcon.icns and <output-dir>/AppIcon-preview.png
//
// The icon is drawn entirely in code (no external art): a warm "sand" squircle
// with a clean white hourglass and amber sand pouring through. The same hourglass
// motif is used in the menu-bar status item, so the brand stays cohesive.

import AppKit
import Foundation

// MARK: - Palette

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let bgTop    = rgb(255, 196, 92)   // warm sand, light
let bgBottom = rgb(232, 130, 28)   // deep amber
let glassWhite = rgb(255, 252, 247)
let glassFill  = rgb(255, 255, 255, 0.30)  // frosted interior so the sand reads against it
let sand     = rgb(214, 110, 18)   // deep amber sand, clearly darker than the frosted glass
let sandDeep = rgb(176, 86, 10)

// MARK: - Drawing

/// Draws the icon into a 1024×1024 logical space (CoreGraphics, origin bottom-left).
func draw(in cg: CGContext) {
    let canvas: CGFloat = 1024

    // --- Squircle background ---
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    cg.saveGState()
    squircle.setClip()
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
                          colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                          locations: [0, 1])!
    cg.drawLinearGradient(grad,
                          start: CGPoint(x: 0, y: canvas),
                          end: CGPoint(x: 0, y: 0),
                          options: [])
    // Soft top-left sheen for depth.
    let sheen = CGGradient(colorsSpace: space,
                           colors: [rgb(255, 255, 255, 0.28).cgColor, rgb(255, 255, 255, 0).cgColor] as CFArray,
                           locations: [0, 1])!
    cg.drawRadialGradient(sheen,
                          startCenter: CGPoint(x: 330, y: 760), startRadius: 0,
                          endCenter: CGPoint(x: 330, y: 760), endRadius: 520,
                          options: [])
    cg.restoreGState()

    // --- Hourglass geometry ---
    let cx: CGFloat = 512
    let neckY: CGFloat = 512
    let neckHalf: CGFloat = 16

    let barW: CGFloat = 320
    let barH: CGFloat = 56
    let barR: CGFloat = barH / 2
    let topBarBottom: CGFloat = 716   // interior edge the glass attaches to
    let bottomBarTop: CGFloat = 308
    let bulbHalf: CGFloat = barW / 2 - 28   // glass is a touch narrower than the bars

    func bar(centerY: CGFloat) -> NSBezierPath {
        let r = CGRect(x: cx - barW / 2, y: centerY - barH / 2, width: barW, height: barH)
        return NSBezierPath(roundedRect: r, xRadius: barR, yRadius: barR)
    }

    // Top bulb (wide at top, narrow at neck) and bottom bulb (mirror).
    let topBulb = NSBezierPath()
    topBulb.move(to: CGPoint(x: cx - bulbHalf, y: topBarBottom))
    topBulb.line(to: CGPoint(x: cx + bulbHalf, y: topBarBottom))
    topBulb.line(to: CGPoint(x: cx + neckHalf, y: neckY))
    topBulb.line(to: CGPoint(x: cx - neckHalf, y: neckY))
    topBulb.close()

    let bottomBulb = NSBezierPath()
    bottomBulb.move(to: CGPoint(x: cx - bulbHalf, y: bottomBarTop))
    bottomBulb.line(to: CGPoint(x: cx + bulbHalf, y: bottomBarTop))
    bottomBulb.line(to: CGPoint(x: cx + neckHalf, y: neckY))
    bottomBulb.line(to: CGPoint(x: cx - neckHalf, y: neckY))
    bottomBulb.close()

    // --- Frosted glass interior (so the amber sand stands out) ---
    glassFill.setFill()
    topBulb.fill()
    bottomBulb.fill()

    // --- Sand (drawn first, then clipped by the glass) ---
    cg.saveGState()
    bottomBulb.setClip()
    // A settled pile at the bottom: wide at the base bar, narrowing upward.
    let pile = NSBezierPath()
    let pileTop: CGFloat = 470
    pile.move(to: CGPoint(x: cx - bulbHalf, y: bottomBarTop))
    pile.line(to: CGPoint(x: cx + bulbHalf, y: bottomBarTop))
    pile.line(to: CGPoint(x: cx + 14, y: pileTop))
    pile.line(to: CGPoint(x: cx - 14, y: pileTop))
    pile.close()
    sand.setFill(); pile.fill()
    cg.restoreGState()

    // A small remnant of sand in the upper bulb, funneling toward the neck.
    cg.saveGState()
    topBulb.setClip()
    let upper = NSBezierPath()
    let upperTop: CGFloat = 596
    upper.move(to: CGPoint(x: cx - (bulbHalf * 0.62), y: upperTop))
    upper.line(to: CGPoint(x: cx + (bulbHalf * 0.62), y: upperTop))
    upper.line(to: CGPoint(x: cx + neckHalf, y: neckY))
    upper.line(to: CGPoint(x: cx - neckHalf, y: neckY))
    upper.close()
    sand.setFill(); upper.fill()
    cg.restoreGState()

    // Falling stream from the neck down to the pile.
    let stream = NSBezierPath(rect: CGRect(x: cx - 7, y: pileTop - 6, width: 14, height: neckY - pileTop + 6))
    sandDeep.setFill(); stream.fill()

    // --- Glass frame (white outline over the sand) ---
    glassWhite.setStroke()
    topBulb.lineWidth = 30
    topBulb.lineJoinStyle = .round
    topBulb.stroke()
    bottomBulb.lineWidth = 30
    bottomBulb.lineJoinStyle = .round
    bottomBulb.stroke()

    // --- Caps ---
    glassWhite.setFill()
    bar(centerY: topBarBottom).fill()
    bar(centerY: bottomBarTop).fill()
}

// MARK: - Rasterization

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let scale = CGFloat(size) / 1024
    cg.scaleBy(x: scale, y: scale)
    cg.interpolationQuality = .high
    draw(in: cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

// MARK: - Main

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "build"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 1024 preview for eyeballing the design.
let preview = render(size: 1024)
writePNG(preview, to: URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-preview.png"))

// Build a .iconset and convert to .icns via iconutil.
let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",     32),
    ("icon_32x32",      32),  ("icon_32x32@2x",     64),
    ("icon_128x128",   128),  ("icon_128x128@2x",  256),
    ("icon_256x256",   256),  ("icon_256x256@2x",  512),
    ("icon_512x512",   512),  ("icon_512x512@2x", 1024),
]
for v in variants {
    writePNG(render(size: v.size), to: iconset.appendingPathComponent("\(v.name).png"))
}

let icns = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try? proc.run()
proc.waitUntilExit()
try? fm.removeItem(at: iconset)

print("Wrote \(icns.path)")
print("Preview \(URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-preview.png").path)")
