#!/usr/bin/env swift
//
// Generates Wallflow's bundled demo wallpaper: a seamlessly looping aurora
// animation rendered with Core Graphics and encoded with AVAssetWriter.
//
// Usage:
//   swift MakeDemoVideo.swift [output.mp4]
//   swift MakeDemoVideo.swift --preview
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1920
let height = 1080
let fps: Int32 = 30
let durationSeconds = 12
let frameCount = Int(fps) * durationSeconds

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

// MARK: - Deterministic randomness

struct LCG {
    var state: UInt64 = 0x9E3779B97F4A7C15
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(UInt64(1) << 31)
    }
}

struct Star {
    let x: Double
    let y: Double
    let radius: Double
    let phase: Double
    let alpha: Double
    let cycles: Double
}

struct Bokeh {
    let x: Double
    let y: Double
    let radius: Double
    let phase: Double
    let alpha: Double
}

var rng = LCG()
let stars: [Star] = (0..<170).map { _ in
    Star(
        x: rng.next(),
        y: pow(rng.next(), 1.25) * 0.82,
        radius: 0.5 + rng.next() * 1.4,
        phase: rng.next(),
        alpha: 0.18 + rng.next() * 0.55,
        cycles: Double(1 + Int(rng.next() * 3))
    )
}
let bokeh: [Bokeh] = (0..<22).map { _ in
    Bokeh(
        x: rng.next(),
        y: 0.35 + rng.next() * 0.6,
        radius: 8 + rng.next() * 26,
        phase: rng.next(),
        alpha: 0.02 + rng.next() * 0.05
    )
}

// MARK: - Colors

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

let auroraColors: [CGColor] = [
    color(0.16, 0.94, 0.68),
    color(0.25, 0.72, 1.00),
    color(0.62, 0.42, 1.00),
    color(1.00, 0.40, 0.68),
]

// MARK: - Drawing helpers

func drawGlow(
    _ ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color glowColor: CGColor,
    alpha: CGFloat,
    blend: CGBlendMode = .screen
) {
    let colors = [glowColor.copy(alpha: alpha)!, glowColor.copy(alpha: 0)!] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: colors,
        locations: [0, 1]
    ) else { return }

    ctx.saveGState()
    ctx.setBlendMode(blend)
    ctx.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
    ctx.restoreGState()
}

func drawAurora(
    _ ctx: CGContext,
    t: Double,
    base: CGFloat,
    amplitude: CGFloat,
    wavelength: CGFloat,
    thickness: CGFloat,
    phase: Double,
    cycles: Double,
    tint: CGColor
) {
    let path = CGMutablePath()
    var x: CGFloat = -80
    var first = true
    while x <= CGFloat(width) + 80 {
        let u = Double(x / wavelength) * 2 * Double.pi
        let v = t * 2 * Double.pi * cycles
        let y = base
            + amplitude * CGFloat(sin(u + v + phase))
            + amplitude * 0.34 * CGFloat(sin(u * 2.7 - v * 1.7 + phase * 1.3))
        if first {
            path.move(to: CGPoint(x: x, y: y))
            first = false
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
        x += 8
    }

    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let layers: [(CGFloat, CGFloat)] = [
        (thickness * 1.0, 0.045),
        (thickness * 0.62, 0.07),
        (thickness * 0.32, 0.10),
        (thickness * 0.14, 0.16),
        (thickness * 0.05, 0.45),
    ]

    for (lineWidth, alpha) in layers {
        ctx.setStrokeColor(tint.copy(alpha: alpha)!)
        ctx.setLineWidth(max(lineWidth, 1))
        ctx.addPath(path)
        ctx.strokePath()
    }

    // Hot core.
    ctx.setStrokeColor(color(1, 1, 1, 0.55).copy(alpha: 0.30)!)
    ctx.setLineWidth(max(thickness * 0.018, 1.5))
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(_ ctx: CGContext, t: Double) {
    // Work in top-left coordinates.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    let w = CGFloat(width)
    let h = CGFloat(height)

    // Deep night sky.
    let sky = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0.020, 0.024, 0.055),
            color(0.027, 0.035, 0.095),
            color(0.043, 0.048, 0.135),
            color(0.016, 0.014, 0.040),
        ] as CFArray,
        locations: [0, 0.42, 0.78, 1]
    )!
    ctx.drawLinearGradient(
        sky,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: h),
        options: []
    )

    // Broad atmospheric glow near the aurora band.
    drawGlow(
        ctx,
        center: CGPoint(x: w * 0.32 + 90 * sin(2 * .pi * t), y: h * 0.74),
        radius: w * 0.62,
        color: auroraColors[0],
        alpha: 0.13
    )
    drawGlow(
        ctx,
        center: CGPoint(x: w * 0.70 - 70 * sin(2 * .pi * t), y: h * 0.70),
        radius: w * 0.55,
        color: auroraColors[2],
        alpha: 0.11
    )
    drawGlow(
        ctx,
        center: CGPoint(x: w * 0.52, y: h * 0.52),
        radius: w * 0.42,
        color: color(0.20, 0.28, 0.75),
        alpha: 0.07
    )

    // Stars.
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    for star in stars {
        let twinkle = 0.5 + 0.5 * sin(2 * .pi * (t * star.cycles + star.phase))
        let alpha = star.alpha * (0.25 + 0.75 * pow(twinkle, 1.6))
        ctx.setFillColor(color(0.82, 0.90, 1.0, alpha))
        let sx = star.x * Double(w)
        let sy = star.y * Double(h)
        ctx.fillEllipse(in: CGRect(x: sx - star.radius, y: sy - star.radius, width: star.radius * 2, height: star.radius * 2))
    }
    ctx.restoreGState()

    // Aurora curtains.
    drawAurora(ctx, t: t, base: h * 0.70, amplitude: 54, wavelength: 1250, thickness: 210,
               phase: 0.2, cycles: 1, tint: auroraColors[0])
    drawAurora(ctx, t: t, base: h * 0.76, amplitude: 76, wavelength: 1680, thickness: 170,
               phase: 2.1, cycles: 2, tint: auroraColors[1])
    drawAurora(ctx, t: t, base: h * 0.64, amplitude: 40, wavelength: 980, thickness: 110,
               phase: 4.0, cycles: 3, tint: auroraColors[2])
    drawAurora(ctx, t: t, base: h * 0.815, amplitude: 58, wavelength: 1450, thickness: 150,
               phase: 5.1, cycles: 2, tint: auroraColors[3])

    // Floating dust.
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    for mote in bokeh {
        let drift = sin(2 * .pi * (t + mote.phase))
        let center = CGPoint(
            x: CGFloat(mote.x) * w + CGFloat(drift * 30),
            y: CGFloat(mote.y) * h + CGFloat(drift * 18)
        )
        drawGlow(
            ctx,
            center: center,
            radius: CGFloat(mote.radius),
            color: auroraColors[1],
            alpha: CGFloat(mote.alpha * (0.5 + 0.5 * drift)),
            blend: .screen
        )
    }
    ctx.restoreGState()

    // Vignette and top/bottom falloff for menu bar and Dock legibility.
    let vignette = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0, 0, 0, 0), color(0, 0, 0, 0.55)] as CFArray,
        locations: [0.45, 1.0]
    )!
    ctx.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: w / 2, y: h / 2),
        startRadius: 0,
        endCenter: CGPoint(x: w / 2, y: h / 2),
        endRadius: w * 0.72,
        options: [.drawsAfterEndLocation]
    )

    let topFade = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0, 0, 0, 0.34), color(0, 0, 0, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        topFade,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: 170),
        options: []
    )

    let bottomFade = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0, 0, 0, 0), color(0.005, 0.004, 0.015, 0.55)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bottomFade,
        start: CGPoint(x: 0, y: h * 0.72),
        end: CGPoint(x: 0, y: h),
        options: []
    )

    ctx.restoreGState()
}

// MARK: - Still previews

func makeBitmapContext() -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

if CommandLine.arguments.contains("--preview") {
    for frame in [0, 90, 180, 270] {
        let ctx = makeBitmapContext()
        render(ctx, t: Double(frame) / Double(frameCount))
        if let image = ctx.makeImage() {
            let path = "/tmp/wallflow_preview_\(frame).png"
            writePNG(image, to: path)
            print("wrote \(path)")
        }
    }
    exit(0)
}

// MARK: - Encode

let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    outputPath = "Resources/Demo/Aurora.mp4"
}
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 7_500_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 60,
        AVVideoAllowFrameReorderingKey: true,
    ],
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
]

let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
input.expectsMediaDataInRealTime = false

let sourceAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: sourceAttributes
)

guard writer.canAdd(input) else {
    fatalError("Cannot add video input")
}
writer.add(input)
guard writer.startWriting() else {
    fatalError("startWriting failed: \(String(describing: writer.error))")
}
writer.startSession(atSourceTime: .zero)

let start = Date()
for frame in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
        usleep(2000)
    }
    guard let pool = adaptor.pixelBufferPool else {
        fatalError("No pixel buffer pool")
    }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let pixelBuffer = buffer else {
        fatalError("Could not create pixel buffer")
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    render(ctx, t: Double(frame) / Double(frameCount))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    let time = CMTime(value: CMTimeValue(frame), timescale: fps)
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
        fatalError("append failed at frame \(frame): \(String(describing: writer.error))")
    }

    if frame % 30 == 0 {
        print("frame \(frame)/\(frameCount)")
    }
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()

guard writer.status == .completed else {
    fatalError("finishWriting failed: \(String(describing: writer.error))")
}

let elapsed = Date().timeIntervalSince(start)
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
print(String(format: "wrote %@ — %.1f MB in %.1fs", outputURL.path, bytes / 1_048_576, elapsed))
