#!/usr/bin/env swift
//
// Enhance a video: optional light denoise, Lanczos upscale, mild sharpen.
// Keeps the original frame rate; audio is muxed back via passthrough.
//
// Usage: EnhanceVideo <input> <output> <scale> <sharpenRadius> <sharpenIntensity> <denoise 0/1>
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation

let args = CommandLine.arguments
guard args.count >= 7 else {
    print("usage: EnhanceVideo <input> <output> <scale> <radius> <intensity> <denoise 0/1>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let scale = CGFloat(Double(args[3])!)
let sharpenRadius = Double(args[4])!
let sharpenIntensity = Double(args[5])!
let useDenoise = args[6] == "1"
let tempVideoURL = URL(fileURLWithPath: "/tmp/enhance_video_only.mp4")

try? FileManager.default.removeItem(at: outputURL)
try? FileManager.default.removeItem(at: tempVideoURL)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [
    .workingColorSpace: colorSpace,
    .outputColorSpace: colorSpace,
    .cacheIntermediates: false,
])

let asset = AVURLAsset(url: inputURL)
guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    fatalError("No video track")
}
let sourceSize = videoTrack.naturalSize
let fps = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 24
let width = Int((sourceSize.width * scale).rounded())
let height = Int((sourceSize.height * scale).rounded())
let duration = asset.duration.seconds
print("source: \(Int(sourceSize.width))x\(Int(sourceSize.height)) \(fps)fps \(duration)s")
print("output: \(width)x\(height)")

let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(
    track: videoTrack,
    outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ]
)
output.alwaysCopiesSampleData = false
reader.add(output)
guard reader.startReading() else {
    fatalError("reader failed: \(String(describing: reader.error))")
}

let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 12_000_000 * Int(scale),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
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
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ]
)
guard writer.canAdd(input) else { fatalError("cannot add input") }
writer.add(input)
guard writer.startWriting() else { fatalError("startWriting failed") }
writer.startSession(atSourceTime: .zero)

let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
let sharpenFilter = CIFilter(name: "CIUnsharpMask")!
let colorFilter = CIFilter(name: "CIColorControls")!
let denoiseFilter = CIFilter(name: "CINoiseReduction")!

let timescale = CMTimeScale(fps.rounded())
var frameIndex = 0
let start = Date()

while let sample = output.copyNextSampleBuffer() {
    while !input.isReadyForMoreMediaData {
        usleep(2000)
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
          let pool = adaptor.pixelBufferPool else {
        continue
    }

    var image = CIImage(cvPixelBuffer: pixelBuffer)

    if useDenoise {
        denoiseFilter.setValue(image, forKey: kCIInputImageKey)
        denoiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
        denoiseFilter.setValue(0.40, forKey: "inputSharpness")
        if let out = denoiseFilter.outputImage {
            image = out
        }
    }

    scaleFilter.setValue(image, forKey: kCIInputImageKey)
    scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
    scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    if let out = scaleFilter.outputImage {
        image = out
    }

    colorFilter.setValue(image, forKey: kCIInputImageKey)
    colorFilter.setValue(1.03, forKey: kCIInputContrastKey)
    colorFilter.setValue(1.03, forKey: kCIInputSaturationKey)
    colorFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
    if let out = colorFilter.outputImage {
        image = out
    }

    if sharpenIntensity > 0 {
        sharpenFilter.setValue(image, forKey: kCIInputImageKey)
        sharpenFilter.setValue(sharpenRadius, forKey: kCIInputRadiusKey)
        sharpenFilter.setValue(sharpenIntensity, forKey: kCIInputIntensityKey)
        if let out = sharpenFilter.outputImage {
            image = out
        }
    }

    var outputBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
          let buffer = outputBuffer else {
        fatalError("no pixel buffer")
    }
    ciContext.render(
        image,
        to: buffer,
        bounds: CGRect(x: 0, y: 0, width: width, height: height),
        colorSpace: colorSpace
    )

    let time = CMTime(value: CMTimeValue(frameIndex), timescale: timescale)
    guard adaptor.append(buffer, withPresentationTime: time) else {
        fatalError("append failed: \(String(describing: writer.error))")
    }
    frameIndex += 1
    if frameIndex % 240 == 0 {
        print("frame \(frameIndex)")
    }
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
guard writer.status == .completed else {
    fatalError("writer failed: \(String(describing: writer.error))")
}
print("video done: \(frameIndex) frames in \(Int(Date().timeIntervalSince(start)))s")

// Mux the original audio back.
if let audioTrack = asset.tracks(withMediaType: .audio).first {
    let videoAsset = AVURLAsset(url: tempVideoURL)
    guard let reversedVideo = videoAsset.tracks(withMediaType: .video).first else {
        fatalError("missing video")
    }
    let composition = AVMutableComposition()
    let videoComp = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    let audioComp = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try videoComp.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoAsset.duration),
        of: reversedVideo,
        at: .zero
    )
    _ = audioTrack
    try audioComp.insertTimeRange(
        CMTimeRange(start: .zero, duration: min(asset.duration, videoAsset.duration)),
        of: audioTrack,
        at: .zero
    )

    func export(preset: String) -> Bool {
        let exporter = AVAssetExportSession(asset: composition, presetName: preset)!
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        let sem = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously { sem.signal() }
        sem.wait()
        print(preset, "status:", exporter.status.rawValue, exporter.error as Any)
        return exporter.status == .completed
    }

    if !export(preset: AVAssetExportPresetPassthrough) {
        try? FileManager.default.removeItem(at: outputURL)
        _ = export(preset: AVAssetExportPresetHighestQuality)
    }
} else {
    try? FileManager.default.removeItem(at: outputURL)
    try FileManager.default.copyItem(at: tempVideoURL, to: outputURL)
}

guard FileManager.default.fileExists(atPath: outputURL.path) else {
    fatalError("output missing")
}
let result = AVURLAsset(url: outputURL)
print("wrote \(outputURL.path) \(result.duration.seconds)s")
