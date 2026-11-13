#!/usr/bin/env swift
//
// Slow-motion + crop + 2x Lanczos upscale + sharpen.
// Reads a source video, crops the player UI, scales 2x, blends adjacent
// frames for smooth slow motion, sharpens, and writes a 60 fps H.264 file.
//
// Usage:
//   SlowClearExport <input> <output> <start> <end> <speed> <scale>
//   e.g. SlowClearExport in.mp4 out.mp4 6.0 29.8 0.5 2
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation

let args = CommandLine.arguments
guard args.count >= 7 else {
    print("usage: SlowClearExport <input> <output> <start> <end> <speed> <scale>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let startSeconds = Double(args[3])!
let endSeconds = Double(args[4])!
let speed = Double(args[5])!
let scale = CGFloat(Double(args[6])!)
let sharpenRadius = args.count > 7 ? Double(args[7])! : 1.6
let sharpenIntensity = args.count > 8 ? Double(args[8])! : 0.55
let outputFPS: Int32 = 60
let sourceFPS: Double = 30

// Crop inside the 960x448 source, top-left coordinates.
let cropX: CGFloat = 40
let cropY: CGFloat = 80
let cropW: CGFloat = 880
let cropH: CGFloat = 312
let sourceHeight: CGFloat = 448

let outputWidth = Int(cropW * scale)
let outputHeight = Int(cropH * scale)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [
    .workingColorSpace: colorSpace,
    .outputColorSpace: colorSpace,
    .cacheIntermediates: false,
])

let asset = AVURLAsset(url: URL(fileURLWithPath: inputURL.path))
guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    fatalError("No video track")
}

let reader = try AVAssetReader(asset: asset)
reader.timeRange = CMTimeRange(
    start: CMTime(seconds: startSeconds, preferredTimescale: 600),
    duration: CMTime(seconds: endSeconds - startSeconds, preferredTimescale: 600)
)
let readerOutput = AVAssetReaderTrackOutput(
    track: videoTrack,
    outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ]
)
readerOutput.alwaysCopiesSampleData = false
reader.add(readerOutput)
guard reader.startReading() else {
    fatalError("Reader failed: \(String(describing: reader.error))")
}

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outputWidth,
    AVVideoHeightKey: outputHeight,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 9_000_000,
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
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: outputWidth,
        kCVPixelBufferHeightKey as String: outputHeight,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ]
)
guard writer.canAdd(input) else { fatalError("Cannot add input") }
writer.add(input)
guard writer.startWriting() else { fatalError("startWriting failed") }
writer.startSession(atSourceTime: .zero)

// MARK: - Frame buffering

struct BufferedFrame {
    let index: Int
    let image: CIImage
    let sample: CMSampleBuffer
}

var sourceIndex = 0
var frames: [BufferedFrame] = []

func lanczos(_ image: CIImage, scale: CGFloat) -> CIImage {
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(scale, forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return filter.outputImage ?? image
}

func process(_ pixelBuffer: CVPixelBuffer) -> CIImage {
    var image = CIImage(cvPixelBuffer: pixelBuffer)
    let cropRect = CGRect(
        x: cropX,
        y: sourceHeight - cropY - cropH,
        width: cropW,
        height: cropH
    )
    image = image.cropped(to: cropRect)
    image = image.transformed(
        by: CGAffineTransform(
            translationX: -cropX,
            y: -(sourceHeight - cropY - cropH)
        )
    )
    return lanczos(image, scale: scale)
}

func readNext() -> BufferedFrame? {
    guard let sample = readerOutput.copyNextSampleBuffer(),
          let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
        return nil
    }
    let image = process(pixelBuffer)
    let frame = BufferedFrame(index: sourceIndex, image: image, sample: sample)
    sourceIndex += 1
    return frame
}

func ensureFrame(_ target: Int) {
    while (frames.last?.index ?? -1) < target {
        guard let frame = readNext() else { break }
        frames.append(frame)
    }
    if let last = frames.last, last.index - 6 > target {
        frames.removeAll { $0.index < target - 2 }
    }
}

func frame(at index: Int) -> BufferedFrame? {
    ensureFrame(index)
    return frames.first { $0.index == index }
}

// MARK: - Filters

let dissolve = CIFilter(name: "CIDissolveTransition")!
let sharpen = CIFilter(name: "CIUnsharpMask")!
let colorControls = CIFilter(name: "CIColorControls")!

func renderFrame(index: Int, fraction: Double) -> CIImage? {
    guard let a = frame(at: index) else { return nil }
    var image = a.image

    if fraction > 0.02, let b = frame(at: index + 1) {
        dissolve.setValue(a.image, forKey: kCIInputImageKey)
        dissolve.setValue(b.image, forKey: kCIInputTargetImageKey)
        dissolve.setValue(fraction, forKey: kCIInputTimeKey)
        if let blended = dissolve.outputImage {
            image = blended
        }
    }

    colorControls.setValue(image, forKey: kCIInputImageKey)
    colorControls.setValue(1.04, forKey: kCIInputContrastKey)
    colorControls.setValue(1.05, forKey: kCIInputSaturationKey)
    colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
    if let adjusted = colorControls.outputImage {
        image = adjusted
    }

    sharpen.setValue(image, forKey: kCIInputImageKey)
    sharpen.setValue(sharpenRadius, forKey: kCIInputRadiusKey)
    sharpen.setValue(sharpenIntensity, forKey: kCIInputIntensityKey)
    return sharpen.outputImage ?? image
}

// MARK: - Render loop

let sourceDuration = endSeconds - startSeconds
let outputDuration = sourceDuration / speed
let outputFrameCount = Int((outputDuration * Double(outputFPS)).rounded())
print("output: \(outputWidth)x\(outputHeight), \(outputDuration)s, \(outputFrameCount) frames")

let start = Date()
for frameIndex in 0..<outputFrameCount {
    while !input.isReadyForMoreMediaData {
        usleep(2000)
    }
    guard let pool = adaptor.pixelBufferPool else { fatalError("No pool") }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let pixelBuffer = buffer else {
        fatalError("No pixel buffer")
    }

    let sourcePosition = Double(frameIndex) / Double(outputFPS) * speed * sourceFPS
    let index = Int(floor(sourcePosition))
    let fraction = sourcePosition - Double(index)

    guard let image = renderFrame(index: index, fraction: fraction) else {
        break
    }

    ciContext.render(
        image,
        to: pixelBuffer,
        bounds: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
        colorSpace: colorSpace
    )

    let time = CMTime(value: CMTimeValue(frameIndex), timescale: outputFPS)
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
        fatalError("append failed: \(String(describing: writer.error))")
    }

    if frameIndex % 300 == 0 {
        print("frame \(frameIndex)/\(outputFrameCount)")
    }
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()

guard writer.status == .completed else {
    fatalError("writer failed: \(String(describing: writer.error))")
}

let elapsed = Date().timeIntervalSince(start)
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
print(String(format: "wrote %@ — %.1f MB in %.1fs", outputURL.path, bytes / 1_048_576, elapsed))
