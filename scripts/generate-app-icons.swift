import AppKit
import Foundation
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: "StudyMate/Resources/Assets.xcassets/AppIcon.appiconset")

struct IconImage {
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(filename: "icon_20x20.png", pixels: 20),
    IconImage(filename: "icon_20x20@2x.png", pixels: 40),
    IconImage(filename: "icon_20x20@3x.png", pixels: 60),
    IconImage(filename: "icon_29x29.png", pixels: 29),
    IconImage(filename: "icon_29x29@2x.png", pixels: 58),
    IconImage(filename: "icon_29x29@3x.png", pixels: 87),
    IconImage(filename: "icon_40x40.png", pixels: 40),
    IconImage(filename: "icon_40x40@2x.png", pixels: 80),
    IconImage(filename: "icon_40x40@3x.png", pixels: 120),
    IconImage(filename: "icon_60x60@2x.png", pixels: 120),
    IconImage(filename: "icon_60x60@3x.png", pixels: 180),
    IconImage(filename: "icon_76x76.png", pixels: 76),
    IconImage(filename: "icon_76x76@2x.png", pixels: 152),
    IconImage(filename: "icon_83_5x83_5@2x.png", pixels: 167),
    IconImage(filename: "icon_1024x1024.png", pixels: 1024),
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

    let background = NSColor(calibratedRed: 0.126, green: 0.192, blue: 0.400, alpha: 1)
    let foreground = NSColor(calibratedRed: 0.980, green: 0.965, blue: 0.905, alpha: 1)
    let pageAccent = NSColor(calibratedRed: 0.745, green: 0.855, blue: 1.000, alpha: 1)
    let lineAccent = NSColor(calibratedRed: 0.380, green: 0.565, blue: 0.940, alpha: 1)
    let starAccent = NSColor(calibratedRed: 1.000, green: 0.780, blue: 0.255, alpha: 1)

    background.setFill()
    roundedRect(0, 0, 1024, 1024, radius: 224, scale: scale).fill()

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

    pageAccent.setFill()
    roundedRect(240, 360, 245, 330, radius: 36, scale: scale).fill()
    roundedRect(539, 360, 245, 330, radius: 36, scale: scale).fill()

    lineAccent.setFill()
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

    starAccent.setFill()
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

func flattenedPNGData(from image: NSImage, size: Int) -> Data? {
    let dimension = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return nil
    }

    let background = NSColor(calibratedRed: 0.126, green: 0.192, blue: 0.400, alpha: 1)
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))

    guard let flattenedImage = context.makeImage() else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }

    CGImageDestinationAddImage(destination, flattenedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }

    return data as Data
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for icon in images {
    let image = drawIcon(size: icon.pixels)
    guard let png = flattenedPNGData(from: image, size: icon.pixels) else {
        fatalError("Failed to render \(icon.filename)")
    }

    try png.write(to: outputDirectory.appendingPathComponent(icon.filename))
}
