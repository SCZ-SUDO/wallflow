#!/usr/bin/env swift
//
// Generates an original Valorant-inspired tactical loop for Wallflow.
// Fan-made motion graphics only — no official artwork, characters or logos.
//
// Usage:
//   swift MakeValorantVideo.swift --preview
//   swift MakeValorantVideo.swift --scale 2 output.mp4
//

import AVFoundation
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Design space

let designWidth: CGFloat = 1920
let designHeight: CGFloat = 1080
let fps: Int32 = 30
let durationSeconds = 12
let frameCount = Int(fps) * durationSeconds

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

// MARK: - Colors

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return CGColor(colorSpace: colorSpace, components: [r, g, b, alpha])!
}

let deep = hex(0x080C11)
let navy = hex(0x0F1923)
let red = hex(0xFF4655)
let offWhite = hex(0xECE8E1)
let teal = hex(0x18E0C8)
let gray = hex(0x7C8B99)

// MARK: - Tiny deterministic RNG

struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(UInt64(1) << 31)
    }
}

// MARK: - Geometry helpers

let centerPoint = CGPoint(x: 960, y: 470)

func pointOnCircle(_ angle: Double, _ radius: CGFloat) -> CGPoint {
    CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
}

func diamondPath(halfWidth: CGFloat, halfHeight: CGFloat, rotation: CGFloat) -> CGPath {
    let local = [
        CGPoint(x: 0, y: -halfHeight),
        CGPoint(x: halfWidth, y: 0),
        CGPoint(x: 0, y: halfHeight),
        CGPoint(x: -halfWidth, y: 0),
    ]
    let c = cos(rotation), s = sin(rotation)
    let rotated = local.map { CGPoint(x: $0.x * c - $0.y * s, y: $0.x * s + $0.y * c) }
    let path = CGMutablePath()
    path.addLines(between: rotated)
    path.closeSubpath()
    return path
}

func drawGlow(
    _ ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color glowColor: CGColor,
    alpha: CGFloat,
    blend: CGBlendMode = .screen
) {
    let colors = [glowColor.copy(alpha: alpha)!, glowColor.copy(alpha: 0)!] as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else { return }
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

// MARK: - Text

enum TextAlignment { case left, center, right }

@discardableResult
func drawText(
    _ ctx: CGContext,
    _ text: String,
    fontName: String,
    size: CGFloat,
    color: CGColor,
    x: CGFloat,
    baseline: CGFloat,
    tracking: CGFloat = 0,
    alignment: TextAlignment = .left
) -> CGRect {
    let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? NSColor.white,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)

    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

    var originX = x
    switch alignment {
    case .left: break
    case .center: originX -= width / 2
    case .right: originX -= width
    }

    ctx.saveGState()
    ctx.translateBy(x: originX, y: baseline)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    return CGRect(x: originX, y: baseline - ascent, width: width, height: ascent + descent)
}

// MARK: - Grain

func makeNoiseImage(width: Int = 960, height: Int = 540) -> CGImage? {
    var rng = LCG(seed: 0x51A7C0DE)
    var bytes = [UInt8](repeating: 0, count: width * height)
    for index in 0..<bytes.count {
        bytes[index] = UInt8(108 + Int(rng.next() * 40))
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

let noiseImage = makeNoiseImage()

// MARK: - Scene pieces

func drawBackground(_ ctx: CGContext, t: Double) {
    let full = CGRect(x: 0, y: 0, width: designWidth, height: designHeight)
    ctx.setFillColor(deep)
    ctx.fill(full)

    let sky = CGGradient(
        colorsSpace: colorSpace,
        colors: [hex(0x17232F), hex(0x0B1118), hex(0x070A0E)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawRadialGradient(
        sky,
        startCenter: centerPoint,
        startRadius: 40,
        endCenter: centerPoint,
        endRadius: 1050,
        options: [.drawsAfterEndLocation]
    )

    drawGlow(ctx, center: CGPoint(x: 260, y: 980), radius: 760, color: red, alpha: 0.11)
    drawGlow(ctx, center: CGPoint(x: 1720, y: 120), radius: 620, color: teal, alpha: 0.045)
    drawGlow(ctx, center: centerPoint, radius: 520 + 30 * sin(2 * .pi * t * 2), color: red, alpha: 0.08)

    // Large, very faint angular fragments.
    drawAmbientShards(ctx, t: t)

    // Diagonal pinstripes.
    ctx.saveGState()
    ctx.setStrokeColor(hex(0xFFFFFF, 0.018))
    ctx.setLineWidth(1)
    var x = -CGFloat(designHeight)
    while x < designWidth {
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x + designHeight, y: designHeight))
        x += 56
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Oversized watermark diamond.
    ctx.saveGState()
    ctx.setStrokeColor(hex(0xECE8E1, 0.035))
    ctx.setLineWidth(2)
    ctx.translateBy(x: centerPoint.x, y: centerPoint.y)
    ctx.addPath(diamondPath(halfWidth: 470, halfHeight: 695, rotation: 0.10))
    ctx.strokePath()
    ctx.restoreGState()

    // Faint outer ring watermark.
    ctx.setStrokeColor(hex(0xECE8E1, 0.022))
    ctx.setLineWidth(1)
    ctx.strokeEllipse(in: CGRect(x: centerPoint.x - 760, y: centerPoint.y - 760, width: 1520, height: 1520))
}

func drawScanBand(_ ctx: CGContext, t: Double) {
    let progress = (t * 2).truncatingRemainder(dividingBy: 1)
    let y = CGFloat(progress) * (designHeight + 240) - 120
    let band = CGRect(x: 0, y: y - 60, width: designWidth, height: 120)
    let colors = [
        red.copy(alpha: 0)!,
        red.copy(alpha: 0.055)!,
        red.copy(alpha: 0)!,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.5, 1]) {
        ctx.saveGState()
        ctx.clip(to: band)
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: band.minY),
            end: CGPoint(x: 0, y: band.maxY),
            options: []
        )
        ctx.setFillColor(red.copy(alpha: 0.22)!)
        ctx.fill(CGRect(x: 0, y: y, width: designWidth, height: 1))
        ctx.restoreGState()
    }
}

struct Shard {
    let angle: Double
    let radius: CGFloat
    let size: CGFloat
    let phase: Double
    let cycles: Double
    let tint: CGColor
    let filled: Bool
    let foreground: Bool
}

let shards: [Shard] = {
    var rng = LCG(seed: 0xB00B5)
    return (0..<26).map { index in
        Shard(
            angle: rng.next() * 2 * .pi,
            radius: 400 + CGFloat(rng.next()) * 420,
            size: 5 + CGFloat(rng.next()) * 20,
            phase: rng.next(),
            cycles: Double(1 + Int(rng.next() * 2)),
            tint: rng.next() > 0.45 ? red : offWhite,
            filled: rng.next() > 0.72,
            foreground: index % 4 == 0
        )
    }
}()

func drawAmbientShards(_ ctx: CGContext, t: Double) {
    let specs: [(CGPoint, CGFloat, Double, CGFloat, CGColor)] = [
        (CGPoint(x: 1500, y: 236), 126, 0.13, 0.28, red),
        (CGPoint(x: 356, y: 704), 88, 0.47, -0.18, offWhite),
        (CGPoint(x: 1672, y: 834), 66, 0.82, 0.10, red),
        (CGPoint(x: 292, y: 256), 54, 0.60, 0.42, offWhite),
    ]

    for (center, size, phase, baseRotation, tint) in specs {
        let drift = CGFloat(sin(2 * .pi * (t + phase))) * 8
        let rotation = baseRotation + CGFloat(sin(2 * .pi * (t + phase))) * 0.06
        let local = [
            CGPoint(x: 0, y: -size),
            CGPoint(x: size * 0.9, y: size * 0.6),
            CGPoint(x: -size * 0.8, y: size * 0.55),
        ]
        let c = cos(rotation), s = sin(rotation)
        let points = local.map {
            CGPoint(
                x: center.x + drift + $0.x * c - $0.y * s,
                y: center.y - drift * 0.4 + $0.x * s + $0.y * c
            )
        }
        ctx.setStrokeColor(tint.copy(alpha: 0.05)!)
        ctx.setLineWidth(1.2)
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.strokePath()
    }
}

func drawShards(_ ctx: CGContext, t: Double, foreground: Bool) {
    for shard in shards where shard.foreground == foreground {
        let drift = sin(2 * .pi * (t * shard.cycles + shard.phase))
        let angle = shard.angle + drift * 0.02
        let radius = shard.radius + CGFloat(drift) * 14
        let center = CGPoint(
            x: centerPoint.x + cos(angle) * radius,
            y: centerPoint.y + sin(angle) * radius
        )
        let rotation = CGFloat(2 * .pi * (t * shard.cycles * 0.5 + shard.phase))
        let s = shard.size
        let local = [
            CGPoint(x: 0, y: -s),
            CGPoint(x: s * 0.85, y: s * 0.55),
            CGPoint(x: -s * 0.75, y: s * 0.6),
        ]
        let c = cos(rotation), sn = sin(rotation)
        let points = local.map {
            CGPoint(x: center.x + $0.x * c - $0.y * sn, y: center.y + $0.x * sn + $0.y * c)
        }

        ctx.saveGState()
        if shard.filled {
            ctx.setFillColor(shard.tint.copy(alpha: foreground ? 0.16 : 0.06)!)
            ctx.addLines(between: points)
            ctx.closePath()
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(shard.tint.copy(alpha: foreground ? 0.28 : 0.10)!)
            ctx.setLineWidth(1)
            ctx.addLines(between: points)
            ctx.closePath()
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

func drawReticle(_ ctx: CGContext, t: Double, glitch: Double) {
    let jitter = CGFloat(glitch) * 5
    ctx.saveGState()
    ctx.translateBy(
        x: centerPoint.x + sin(t * 91) * jitter,
        y: centerPoint.y + cos(t * 77) * jitter
    )

    drawGlow(ctx, center: .zero, radius: 220, color: red, alpha: 0.16)
    drawGlow(ctx, center: .zero, radius: 70, color: red, alpha: 0.28)

    let rotation = CGFloat(2 * .pi * t)

    // Outer tick ring.
    let tickCount = 120
    for index in 0..<tickCount {
        let angle = CGFloat(index) / CGFloat(tickCount) * 2 * .pi + rotation
        let major = index % 10 == 0
        let accent = index % 30 == 0
        let inner: CGFloat = 318
        let outer: CGFloat = major ? 346 : 330
        ctx.setStrokeColor((accent ? red : offWhite).copy(alpha: accent ? 0.9 : 0.32)!)
        ctx.setLineWidth(accent ? 2.4 : (major ? 1.8 : 1.1))
        ctx.move(to: pointOnCircle(Double(angle), inner))
        ctx.addLine(to: pointOnCircle(Double(angle), outer))
        ctx.strokePath()
    }

    // Broken outer arcs.
    ctx.setStrokeColor(hex(0xECE8E1, 0.20))
    ctx.setLineWidth(2)
    for index in 0..<4 {
        let start = -rotation * 0.5 + CGFloat(index) * .pi / 2 + 0.18
        ctx.addArc(center: .zero, radius: 366, startAngle: start, endAngle: start + .pi / 3, clockwise: false)
        ctx.strokePath()
    }

    // Dashed middle ring, opposite direction.
    let dashes = 36
    for index in 0..<dashes {
        let start = CGFloat(index) / CGFloat(dashes) * 2 * .pi - rotation * 1.5
        let end = start + 0.055
        ctx.setStrokeColor(hex(0xECE8E1, 0.22))
        ctx.setLineWidth(1.4)
        ctx.addArc(center: .zero, radius: 254, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
    }

    // Thin inner ring.
    ctx.setStrokeColor(hex(0xECE8E1, 0.10))
    ctx.setLineWidth(1)
    ctx.strokeEllipse(in: CGRect(x: -196, y: -196, width: 392, height: 392))

    // Rotating square outline.
    ctx.saveGState()
    ctx.rotate(by: -rotation)
    ctx.setStrokeColor(hex(0xECE8E1, 0.06))
    ctx.setLineWidth(1)
    ctx.stroke(CGRect(x: -158, y: -158, width: 316, height: 316))
    ctx.restoreGState()

    // Crosshair axes.
    for index in 0..<4 {
        let angle = CGFloat(index) * .pi / 2
        let direction = pointOnCircle(Double(angle), 1)
        let start = CGPoint(x: direction.x * 390, y: direction.y * 390)
        let end = CGPoint(x: direction.x * 880, y: direction.y * 880)
        ctx.setStrokeColor(hex(0xECE8E1, 0.10))
        ctx.setLineWidth(1)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        ctx.setStrokeColor(red.copy(alpha: 0.55)!)
        ctx.setLineWidth(2)
        ctx.move(to: start)
        ctx.addLine(to: CGPoint(x: direction.x * 430, y: direction.y * 430))
        ctx.strokePath()
    }

    // Center diamond.
    let pulse = 1 + 0.035 * CGFloat(sin(2 * .pi * 2 * t))
    let tilt = CGFloat(0.05 * sin(2 * .pi * 2 * t + 0.4))
    let diamond = diamondPath(halfWidth: 120 * pulse, halfHeight: 190 * pulse, rotation: tilt)

    ctx.setFillColor(red.copy(alpha: 0.045)!)
    ctx.addPath(diamond)
    ctx.fillPath()

    let glowLayers: [(CGFloat, CGFloat)] = [(34, 0.045), (16, 0.09), (7, 0.20), (3, 0.95)]
    for (width, alpha) in glowLayers {
        ctx.setStrokeColor(red.copy(alpha: alpha)!)
        ctx.setLineWidth(width)
        ctx.addPath(diamond)
        ctx.strokePath()
    }

    // Inner diamond detail.
    let inner = diamondPath(halfWidth: 78 * pulse, halfHeight: 126 * pulse, rotation: tilt)
    ctx.setStrokeColor(hex(0xECE8E1, 0.28))
    ctx.setLineWidth(1)
    ctx.addPath(inner)
    ctx.strokePath()

    // Horizontal seam.
    ctx.setStrokeColor(hex(0xECE8E1, 0.45))
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: -150, y: 0))
    ctx.addLine(to: CGPoint(x: -28, y: 0))
    ctx.move(to: CGPoint(x: 28, y: 0))
    ctx.addLine(to: CGPoint(x: 150, y: 0))
    ctx.strokePath()

    // Orbiting signal dots.
    for index in 0..<3 {
        let angle = 2 * .pi * (t + Double(index) / 3) + 0.6
        let p = pointOnCircle(angle, 330)
        drawGlow(ctx, center: p, radius: 22, color: red, alpha: 0.25)
        ctx.setFillColor(red)
        ctx.fillEllipse(in: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4))
    }

    // Tiny center dot.
    ctx.setFillColor(offWhite)
    ctx.fillEllipse(in: CGRect(x: -2, y: -2, width: 4, height: 4))

    ctx.restoreGState()
}

func drawTitle(_ ctx: CGContext, t: Double, glitch: Double) {
    let x: CGFloat = 112
    let titleBaseline: CGFloat = 900

    // Red slash motif.
    ctx.saveGState()
    ctx.translateBy(x: 96, y: 792)
    ctx.rotate(by: -0.055)
    ctx.setFillColor(red.copy(alpha: 0.95)!)
    ctx.fill(CGRect(x: 0, y: 0, width: 476, height: 9))
    ctx.setFillColor(red.copy(alpha: 0.65)!)
    ctx.fill(CGRect(x: 0, y: 21, width: 292, height: 3))
    ctx.restoreGState()

    // Small tactical caption.
    ctx.setFillColor(red)
    ctx.fill(CGRect(x: 112, y: 758, width: 7, height: 7))
    drawText(
        ctx, "SITE B // SECURED", fontName: "Menlo-Bold", size: 11,
        color: hex(0xECE8E1, 0.48), x: 130, baseline: 767, tracking: 2.2
    )

    // Chromatic glitch copies.
    if glitch > 0.02 {
        let offset = CGFloat(glitch) * 7
        drawText(
            ctx, "无畏契约", fontName: "PingFangSC-Semibold", size: 88,
            color: red.copy(alpha: 0.55)!, x: x - offset, baseline: titleBaseline,
            tracking: 8
        )
        drawText(
            ctx, "无畏契约", fontName: "PingFangSC-Semibold", size: 88,
            color: teal.copy(alpha: 0.35)!, x: x + offset, baseline: titleBaseline,
            tracking: 8
        )
    }

    // Soft red shadow, then the main title.
    drawText(
        ctx, "无畏契约", fontName: "PingFangSC-Semibold", size: 88,
        color: red.copy(alpha: 0.35)!, x: x + 3, baseline: titleBaseline + 2,
        tracking: 8
    )
    drawText(
        ctx, "无畏契约", fontName: "PingFangSC-Semibold", size: 88,
        color: offWhite, x: x, baseline: titleBaseline, tracking: 8
    )

    // Subtitle.
    drawText(
        ctx, "VALORANT", fontName: "DINCondensed-Bold", size: 27,
        color: red, x: x + 1, baseline: 960, tracking: 11
    )
    drawText(
        ctx, "/ FAN MADE", fontName: "Menlo", size: 9.5,
        color: hex(0xECE8E1, 0.32), x: x + 176, baseline: 958, tracking: 2
    )
}

func drawHUD(_ ctx: CGContext, t: Double) {
    let margin: CGFloat = 48
    let bracket: CGFloat = 38
    ctx.setStrokeColor(hex(0xECE8E1, 0.24))
    ctx.setLineWidth(1.6)

    // Corner brackets.
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: margin, y: margin + bracket), CGPoint(x: margin, y: margin), CGPoint(x: margin + bracket, y: margin)),
        (CGPoint(x: designWidth - margin - bracket, y: margin), CGPoint(x: designWidth - margin, y: margin), CGPoint(x: designWidth - margin, y: margin + bracket)),
        (CGPoint(x: margin, y: designHeight - margin - bracket), CGPoint(x: margin, y: designHeight - margin), CGPoint(x: margin + bracket, y: designHeight - margin)),
        (CGPoint(x: designWidth - margin - bracket, y: designHeight - margin), CGPoint(x: designWidth - margin, y: designHeight - margin), CGPoint(x: designWidth - margin, y: designHeight - margin - bracket)),
    ]
    for (a, b, c) in corners {
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.addLine(to: c)
        ctx.strokePath()
    }

    // Top-left readout.
    ctx.setFillColor(red)
    ctx.fill(CGRect(x: margin + 8, y: 92, width: 6, height: 6))
    drawText(
        ctx, "TACTICAL // 01", fontName: "Menlo-Bold", size: 10,
        color: hex(0xECE8E1, 0.38), x: margin + 22, baseline: 99, tracking: 1.6
    )

    // Top-right readout.
    drawText(
        ctx, "13:04", fontName: "Menlo-Bold", size: 14,
        color: hex(0xECE8E1, 0.55), x: designWidth - margin - 8, baseline: 100,
        tracking: 1.5, alignment: .right
    )
    drawText(
        ctx, "ROUND 13 / 24", fontName: "Menlo", size: 9,
        color: hex(0xECE8E1, 0.26), x: designWidth - margin - 8, baseline: 116,
        tracking: 1.4, alignment: .right
    )

    // Bottom ruler.
    let rulerY: CGFloat = 1028
    ctx.setStrokeColor(hex(0xECE8E1, 0.12))
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: margin, y: rulerY))
    ctx.addLine(to: CGPoint(x: designWidth - margin, y: rulerY))
    ctx.strokePath()

    var index = 0
    var x = margin
    while x <= designWidth - margin {
        let tall = index % 4 == 0
        ctx.setStrokeColor(index % 12 == 0 ? red.copy(alpha: 0.45)! : hex(0xECE8E1, 0.18))
        ctx.setLineWidth(tall ? 1.4 : 1)
        ctx.move(to: CGPoint(x: x, y: rulerY))
        ctx.addLine(to: CGPoint(x: x, y: rulerY + (tall ? 8 : 4)))
        ctx.strokePath()
        x += 48
        index += 1
    }

    // Bottom-right coordinate chip.
    drawText(
        ctx, "X 960 // Y 470", fontName: "Menlo", size: 9,
        color: hex(0xECE8E1, 0.22), x: designWidth - margin, baseline: 1006,
        tracking: 1.2, alignment: .right
    )
}

// MARK: - Glitch

func glitchAmount(_ t: Double) -> Double {
    let centers = [0.18, 0.52, 0.83]
    var amount = 0.0
    for c in centers {
        var distance = abs(t - c)
        distance = min(distance, 1 - distance)
        if distance < 0.009 {
            amount = max(amount, 1 - distance / 0.009)
        }
    }
    return amount
}

func drawGlitch(_ ctx: CGContext, t: Double, amount: Double, frame: Int) {
    guard amount > 0.05 else { return }
    var rng = LCG(seed: UInt64(frame) &* 0x9E3779B97F4A7C15 &+ 0xA5A5)

    for index in 0..<9 {
        let y = CGFloat(rng.next()) * designHeight
        let height = 1 + CGFloat(rng.next()) * 18 * CGFloat(amount)
        let fill: CGColor
        switch index % 3 {
        case 0: fill = red
        case 1: fill = teal
        default: fill = offWhite
        }
        ctx.setFillColor(fill.copy(alpha: 0.03 + 0.08 * CGFloat(rng.next()) * CGFloat(amount))!)
        let inset = CGFloat(rng.next() * 60 - 30) * CGFloat(amount)
        ctx.fill(CGRect(x: inset, y: y, width: designWidth, height: height))
    }

    for _ in 0..<3 {
        let x = CGFloat(rng.next()) * designWidth
        ctx.setFillColor(hex(0xECE8E1, 0.08))
        ctx.fill(CGRect(x: x, y: 0, width: 1, height: designHeight))
    }
}

// MARK: - Frame

func render(_ ctx: CGContext, t: Double, frame: Int) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: designHeight)
    ctx.scaleBy(x: 1, y: -1)

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let glitch = glitchAmount(t)

    drawBackground(ctx, t: t)

    if glitch > 0.05 {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(glitch) * 4 * sin(Double(frame) * 0.9), y: 0)
        drawShards(ctx, t: t, foreground: false)
        ctx.restoreGState()
    } else {
        drawShards(ctx, t: t, foreground: false)
    }

    drawScanBand(ctx, t: t)
    drawReticle(ctx, t: t, glitch: glitch)
    drawShards(ctx, t: t, foreground: true)
    drawTitle(ctx, t: t, glitch: glitch)
    drawHUD(ctx, t: t)

    drawGlitch(ctx, t: t, amount: glitch, frame: frame)

    // Vignette.
    let vignetteColors = [hex(0x000000, 0), hex(0x000000, 0.62)] as CFArray
    if let vignette = CGGradient(colorsSpace: colorSpace, colors: vignetteColors, locations: [0.42, 1]) {
        ctx.drawRadialGradient(
            vignette,
            startCenter: centerPoint,
            startRadius: 180,
            endCenter: centerPoint,
            endRadius: 1120,
            options: [.drawsAfterEndLocation]
        )
    }

    // Top / bottom falloff for menu bar and Dock.
    if let top = CGGradient(
        colorsSpace: colorSpace,
        colors: [hex(0x000000, 0.35), hex(0x000000, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(top, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 110), options: [])
    }
    if let bottom = CGGradient(
        colorsSpace: colorSpace,
        colors: [hex(0x000000, 0), hex(0x000000, 0.55)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(bottom, start: CGPoint(x: 0, y: 980), end: CGPoint(x: 0, y: designHeight), options: [])
    }

    // Grain.
    if let noise = noiseImage {
        ctx.saveGState()
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(0.05)
        ctx.draw(noise, in: CGRect(x: 0, y: 0, width: designWidth, height: designHeight))
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

// MARK: - Still previews

func makeBitmapContext(width: Int, height: Int) -> CGContext {
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
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

if CommandLine.arguments.contains("--preview") {
    let previewSizes: [(Int, Double)] = [(0, 0.0), (90, 0.25), (180, 0.5), (300, 0.8333)]
    for (frame, t) in previewSizes {
        let ctx = makeBitmapContext(width: Int(designWidth), height: Int(designHeight))
        render(ctx, t: t, frame: frame)
        if let image = ctx.makeImage() {
            let path = "/tmp/valorant_preview_\(frame).png"
            writePNG(image, to: path)
            print("wrote \(path)")
        }
    }
    exit(0)
}

// MARK: - Encode

var outputPath = "Valorant-Wallpaper.mp4"
var scale = 1
var argumentIndex = 1
while argumentIndex < CommandLine.arguments.count {
    let argument = CommandLine.arguments[argumentIndex]
    if argument == "--scale", argumentIndex + 1 < CommandLine.arguments.count {
        scale = max(1, Int(CommandLine.arguments[argumentIndex + 1]) ?? 1)
        argumentIndex += 2
        continue
    }
    outputPath = argument
    argumentIndex += 1
}

let outputWidth = Int(designWidth) * scale
let outputHeight = Int(designHeight) * scale
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outputWidth,
    AVVideoHeightKey: outputHeight,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 15_000_000 * scale,
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
    kCVPixelBufferWidthKey as String: outputWidth,
    kCVPixelBufferHeightKey as String: outputHeight,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: sourceAttributes
)

guard writer.canAdd(input) else { fatalError("Cannot add video input") }
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
    guard let pool = adaptor.pixelBufferPool else { fatalError("No pixel buffer pool") }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let pixelBuffer = buffer else {
        fatalError("Could not create pixel buffer")
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    render(ctx, t: Double(frame) / Double(frameCount), frame: frame)
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
print(String(format: "wrote %@ (%dx%d) — %.1f MB in %.1fs", outputURL.path, outputWidth, outputHeight, bytes / 1_048_576, elapsed))
