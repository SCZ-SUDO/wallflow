#!/usr/bin/env swift
//
// Reverse a short video (video + audio) and write a .mov.
// Frames are decoded into memory; intended for short clips.
//
// Usage: ReverseVideo <input.mov> <output.mov>
//

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: ReverseVideo <input> <output>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let tempVideoURL = URL(fileURLWithPath: "/tmp/reverse_video_only.mp4")
let tempAudioURL = URL(fileURLWithPath: "/tmp/reverse_audio.m4a")

try? FileManager.default.removeItem(at: outputURL)
try? FileManager.default.removeItem(at: tempVideoURL)
try? FileManager.default.removeItem(at: tempAudioURL)

let asset = AVURLAsset(url: inputURL)
guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    fatalError("No video track")
}

let nominalFPS = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 24
let width = Int(videoTrack.naturalSize.width)
let height = Int(videoTrack.naturalSize.height)
let duration = asset.duration.seconds
print("input: \(width)x\(height), \(duration)s, \(nominalFPS) fps")

// MARK: - Decode all video frames

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
    fatalError("Reader failed: \(String(describing: reader.error))")
}

var frames: [CVPixelBuffer] = []
while let sample = output.copyNextSampleBuffer() {
    if let buffer = CMSampleBufferGetImageBuffer(sample) {
        frames.append(buffer)
    }
}
guard !frames.isEmpty else { fatalError("No frames decoded") }
print("decoded \(frames.count) frames")

// MARK: - Reverse audio

let audioAsset = AVURLAsset(url: inputURL)
var hasAudio = false

if let audioTrack = audioAsset.tracks(withMediaType: .audio).first {
    do {
        _ = audioTrack
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "ReverseVideo", code: 1)
        }
        try audioFile.read(into: buffer)

        let channels = Int(format.channelCount)
        let framesInBuffer = Int(buffer.frameLength)
        if let data = buffer.floatChannelData {
            for channel in 0..<channels {
                let samples = data[channel]
                for i in 0..<(framesInBuffer / 2) {
                    let j = framesInBuffer - 1 - i
                    let temp = samples[i]
                    samples[i] = samples[j]
                    samples[j] = temp
                }
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 192_000,
        ]
        let outFile = try AVAudioFile(forWriting: tempAudioURL, settings: settings)
        try outFile.write(from: buffer)
        hasAudio = true
        print("audio: \(channels) ch, \(format.sampleRate) Hz, \(buffer.frameLength) frames")
    } catch {
        print("audio reverse failed, exporting silent video:", error)
    }
}

// MARK: - Write reversed video

try? FileManager.default.removeItem(at: tempVideoURL)
let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 14_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: Int(nominalFPS),
        AVVideoAllowFrameReorderingKey: true,
    ],
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: videoInput,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ]
)
guard writer.canAdd(videoInput) else { fatalError("Cannot add video input") }
writer.add(videoInput)
guard writer.startWriting() else { fatalError("startWriting failed") }
writer.startSession(atSourceTime: .zero)

let timescale = CMTimeScale(nominalFPS.rounded())
for (index, buffer) in frames.reversed().enumerated() {
    while !videoInput.isReadyForMoreMediaData {
        usleep(2000)
    }
    let time = CMTime(value: CMTimeValue(index), timescale: timescale)
    guard adaptor.append(buffer, withPresentationTime: time) else {
        fatalError("append failed: \(String(describing: writer.error))")
    }
}
videoInput.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
guard writer.status == .completed else {
    fatalError("writer failed: \(String(describing: writer.error))")
}
print("reversed video written")

// MARK: - Mux reversed video + audio

if hasAudio {
    let videoAsset = AVURLAsset(url: tempVideoURL)
    let audioAsset = AVURLAsset(url: tempAudioURL)
    guard let reversedVideo = videoAsset.tracks(withMediaType: .video).first,
          let reversedAudio = audioAsset.tracks(withMediaType: .audio).first else {
        fatalError("Missing reversed tracks")
    }

    let composition = AVMutableComposition()
    let videoCompTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    let audioCompTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!

    let videoDuration = videoAsset.duration
    let audioDuration = min(audioAsset.duration, videoDuration)
    try videoCompTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: reversedVideo,
        at: .zero
    )
    try audioCompTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: audioDuration),
        of: reversedAudio,
        at: .zero
    )

    func export(preset: String) -> Bool {
        let exporter = AVAssetExportSession(asset: composition, presetName: preset)!
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
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
    fatalError("Output not created")
}
let result = AVURLAsset(url: outputURL)
print("wrote \(outputURL.path), duration \(result.duration.seconds)")
