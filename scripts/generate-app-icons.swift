import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: "StudyMate/Resources/Assets.xcassets/AppIcon.appiconset")

struct IconImage {
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(filename: "icon_16x16.png", pixels: 16),
    IconImage(filename: "icon_16x16@2x.png", pixels: 32),
    IconImage(filename: "icon_32x32.png", pixels: 32),
    IconImage(filename: "icon_32x32@2x.png", pixels: 64),
    IconImage(filename: "icon_128x128.png", pixels: 128),
    IconImage(filename: "icon_128x128@2x.png", pixels: 256),
    IconImage(filename: "icon_256x256.png", pixels: 256),
    IconImage(filename: "icon_256x256@2x.png", pixels: 512),
    IconImage(filename: "icon_512x512.png", pixels: 512),
    IconImage(filename: "icon_512x512@2x.png", pixels: 1024)
]

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, scale: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func point(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> NSPoint {
    NSPoint(x: x * scale, y: y * scale)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat, scale: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height, scale: scale), xRadius: radius * scale, yRadius: radius * scale)
}

func drawIcon(size: Int) -> NSImage {
    let dimension = CGFloat(size)
    let scale = dimension / 1024
    let image = NSImage(size: NSSize(width: dimension, height: dimension))

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    NSColor(calibratedRed: 0.122, green: 0.137, blue: 0.157, alpha: 1).setFill()
    roundedRect(0, 0, 1024, 1024, radius: 224, scale: scale).fill()

    let foreground = NSColor(calibratedRed: 0.969, green: 0.969, blue: 0.941, alpha: 1)
    let background = NSColor(calibratedRed: 0.122, green: 0.137, blue: 0.157, alpha: 1)

    foreground.setFill()

    let book = NSBezierPath()
    book.move(to: point(515, 205, scale: scale))
    book.curve(to: point(390, 280, scale: scale), controlPoint1: point(480, 260, scale: scale), controlPoint2: point(430, 280, scale: scale))
    book.line(to: point(250, 280, scale: scale))
    book.curve(to: point(155, 375, scale: scale), controlPoint1: point(197, 280, scale: scale), controlPoint2: point(155, 322, scale: scale))
    book.line(to: point(155, 705, scale: scale))
    book.curve(to: point(250, 800, scale: scale), controlPoint1: point(155, 758, scale: scale), controlPoint2: point(197, 800, scale: scale))
    book.line(to: point(320, 800, scale: scale))
    book.curve(to: point(512, 720, scale: scale), controlPoint1: point(418, 800, scale: scale), controlPoint2: point(480, 770, scale: scale))
    book.curve(to: point(704, 800, scale: scale), controlPoint1: point(544, 770, scale: scale), controlPoint2: point(606, 800, scale: scale))
    book.line(to: point(774, 800, scale: scale))
    book.curve(to: point(869, 705, scale: scale), controlPoint1: point(827, 800, scale: scale), controlPoint2: point(869, 758, scale: scale))
    book.line(to: point(869, 375, scale: scale))
    book.curve(to: point(774, 280, scale: scale), controlPoint1: point(869, 322, scale: scale), controlPoint2: point(827, 280, scale: scale))
    book.line(to: point(634, 280, scale: scale))
    book.curve(to: point(509, 205, scale: scale), controlPoint1: point(594, 280, scale: scale), controlPoint2: point(545, 260, scale: scale))
    book.curve(to: point(515, 205, scale: scale), controlPoint1: point(511, 202, scale: scale), controlPoint2: point(513, 202, scale: scale))
    book.close()
    book.fill()

    background.setFill()
    roundedRect(240, 360, 245, 330, radius: 36, scale: scale).fill()
    roundedRect(539, 360, 245, 330, radius: 36, scale: scale).fill()

    foreground.setFill()
    roundedRect(285, 585, 155, 58, radius: 29, scale: scale).fill()
    roundedRect(285, 470, 155, 58, radius: 29, scale: scale).fill()
    roundedRect(590, 585, 122, 58, radius: 29, scale: scale).fill()

    let spine = NSBezierPath()
    spine.move(to: point(512, 220, scale: scale))
    spine.line(to: point(512, 724, scale: scale))
    spine.lineWidth = 64 * scale
    spine.lineCapStyle = .round
    foreground.setStroke()
    spine.stroke()

    let star = NSBezierPath()
    star.move(to: point(775, 862, scale: scale))
    star.curve(to: point(800, 837, scale: scale), controlPoint1: point(784, 862, scale: scale), controlPoint2: point(793, 853, scale: scale))
    star.line(to: point(818, 755, scale: scale))
    star.line(to: point(900, 737, scale: scale))
    star.curve(to: point(925, 712, scale: scale), controlPoint1: point(916, 733, scale: scale), controlPoint2: point(925, 724, scale: scale))
    star.curve(to: point(900, 687, scale: scale), controlPoint1: point(925, 700, scale: scale), controlPoint2: point(916, 691, scale: scale))
    star.line(to: point(818, 669, scale: scale))
    star.line(to: point(800, 587, scale: scale))
    star.curve(to: point(775, 562, scale: scale), controlPoint1: point(796, 571, scale: scale), controlPoint2: point(787, 562, scale: scale))
    star.curve(to: point(750, 587, scale: scale), controlPoint1: point(763, 562, scale: scale), controlPoint2: point(754, 571, scale: scale))
    star.line(to: point(732, 669, scale: scale))
    star.line(to: point(650, 687, scale: scale))
    star.curve(to: point(625, 712, scale: scale), controlPoint1: point(634, 691, scale: scale), controlPoint2: point(625, 700, scale: scale))
    star.curve(to: point(650, 737, scale: scale), controlPoint1: point(625, 724, scale: scale), controlPoint2: point(634, 733, scale: scale))
    star.line(to: point(732, 755, scale: scale))
    star.line(to: point(750, 837, scale: scale))
    star.curve(to: point(775, 862, scale: scale), controlPoint1: point(754, 853, scale: scale), controlPoint2: point(766, 862, scale: scale))
    star.close()
    star.fill()

    image.unlockFocus()
    return image
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for icon in images {
    let image = drawIcon(size: icon.pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(icon.filename)")
    }

    try png.write(to: outputDirectory.appendingPathComponent(icon.filename))
}
