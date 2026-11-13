#!/usr/bin/env swift
//
// Trim + crop a video without re-encoding audio.
// Usage: TrimCropExport <input> <output> <start> <end> <x> <y> <w> <h>
//

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 9 else {
    print("usage: TrimCropExport <input> <output> <start> <end> <x> <y> <w> <h>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let start = Double(args[3])!
let end = Double(args[4])!
let cropX = CGFloat(Double(args[5])!)
let cropY = CGFloat(Double(args[6])!)
let cropW = CGFloat(Double(args[7])!)
let cropH = CGFloat(Double(args[8])!)

try? FileManager.default.removeItem(at: outputURL)

let asset = AVURLAsset(url: inputURL)
guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
    fatalError("No video track")
}

let composition = AVMutableComposition()
guard let videoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid
) else {
    fatalError("Cannot add video track")
}
try videoTrack.insertTimeRange(
    CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: end - start, preferredTimescale: 600)),
    of: sourceVideo,
    at: .zero
)

if let sourceAudio = asset.tracks(withMediaType: .audio).first,
   let audioTrack = composition.addMutableTrack(
       withMediaType: .audio,
       preferredTrackID: kCMPersistentTrackID_Invalid
   ) {
    try? audioTrack.insertTimeRange(
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: end - start, preferredTimescale: 600)),
        of: sourceAudio,
        at: .zero
    )
}

let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = CGSize(width: cropW, height: cropH)
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
// AVVideoComposition uses a top-left origin for its render space.
layerInstruction.setTransform(
    CGAffineTransform(translationX: -cropX, y: -cropY),
    at: .zero
)
instruction.layerInstructions = [layerInstruction]
videoComposition.instructions = [instruction]

guard let exporter = AVAssetExportSession(
    asset: composition,
    presetName: AVAssetExportPresetHighestQuality
) else {
    fatalError("Cannot create exporter")
}
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.videoComposition = videoComposition
exporter.shouldOptimizeForNetworkUse = true

let semaphore = DispatchSemaphore(value: 0)
exporter.exportAsynchronously {
    semaphore.signal()
}
semaphore.wait()

if exporter.status == .completed {
    print("wrote \(outputURL.path)")
    if let track = AVURLAsset(url: outputURL).tracks(withMediaType: .video).first {
        print("size:", track.naturalSize, "duration:", AVURLAsset(url: outputURL).duration.seconds)
    }
} else {
    print("export failed:", exporter.status.rawValue, exporter.error as Any)
    exit(1)
}
