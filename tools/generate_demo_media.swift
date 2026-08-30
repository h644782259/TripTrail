import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: generate_demo_media.swift <output-directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makePoster(filename: String, title: String, subtitle: String, colors: [NSColor]) throws {
    let size = NSSize(width: 1_080, height: 1_350)
    let image = NSImage(size: size)
    image.lockFocus()
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: -35)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 82, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 38, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.84),
        .paragraphStyle: paragraph
    ]
    title.draw(in: NSRect(x: 80, y: 220, width: 920, height: 220), withAttributes: titleAttributes)
    subtitle.draw(in: NSRect(x: 84, y: 125, width: 900, height: 90), withAttributes: subtitleAttributes)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("failed to render poster") }
    try png.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
}

try makePoster(
    filename: "triptrail-demo-lake.png",
    title: "西湖 · 晴",
    subtitle: "旅迹媒体备份测试照片 01",
    colors: [NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.62, alpha: 1), NSColor(calibratedRed: 0.64, green: 0.83, blue: 0.76, alpha: 1)]
)
try makePoster(
    filename: "triptrail-demo-city.png",
    title: "外滩 · 夜",
    subtitle: "旅迹跨设备分享测试照片 02",
    colors: [NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.30, alpha: 1), NSColor(calibratedRed: 0.86, green: 0.45, blue: 0.34, alpha: 1)]
)

let videoURL = outputDirectory.appendingPathComponent("triptrail-demo-motion.mov")
try? FileManager.default.removeItem(at: videoURL)
let sourceURL = URL(
    fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/Reality Composer Pro.app/Contents/Frameworks/RealityToolsFoundation.framework/Versions/A/Resources/Star_BigSurStyle_01.mp4"
)
guard FileManager.default.fileExists(atPath: sourceURL.path) else {
    fatalError("Xcode demo motion source is unavailable")
}
let asset = AVURLAsset(url: sourceURL)
guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
    fatalError("failed to create demo video exporter")
}
exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600))
try await exporter.export(to: videoURL, as: .mov)
print("Generated demo media in \(outputDirectory.path)")
