import AppKit
import AVFoundation
import CryptoKit

/// Generates and caches 16:9 poster frames for videos.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base
            .appendingPathComponent("com.shizhengchen.wallflow", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedThumbnail(for url: URL) -> NSImage? {
        NSImage(contentsOf: cacheFile(for: url))
    }

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cachedThumbnail(for: url) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

        var cgImage: CGImage?
        if let (image, _) = try? await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)) {
            cgImage = image
        } else if let (image, _) = try? await generator.image(at: .zero) {
            cgImage = image
        }

        guard let cgImage else { return nil }

        if let data = jpegData(from: cgImage) {
            try? data.write(to: cacheFile(for: url), options: .atomic)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Cache

    private func cacheFile(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: url)).appendingPathExtension("jpg")
    }

    private func cacheKey(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let raw = "\(url.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func jpegData(from image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
