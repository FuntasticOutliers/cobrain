import CoreGraphics
import Accelerate
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "changedetection")

final class ChangeDetectionService: Sendable {
    static let shared = ChangeDetectionService()

    /// Thumbnail size for comparison (small = fast).
    private static let thumbSize = 64

    /// Compare two CGImages and return the fraction of pixels that differ.
    /// Returns a value in 0...1 where 0 = identical screens, 1 = completely different.
    /// Returns nil if either image cannot be processed.
    func difference(between current: CGImage, and previous: CGImage) -> Double? {
        guard let currentGray = grayscaleThumbnail(current),
              let previousGray = grayscaleThumbnail(previous) else {
            return nil
        }

        let count = Self.thumbSize * Self.thumbSize
        assert(currentGray.count == count && previousGray.count == count)

        // Compute mean absolute difference of pixel intensities (0-255).
        var diffCount = 0
        let threshold: UInt8 = 20 // per-pixel noise tolerance
        for i in 0..<count {
            let diff = abs(Int(currentGray[i]) - Int(previousGray[i]))
            if diff > Int(threshold) {
                diffCount += 1
            }
        }

        let ratio = Double(diffCount) / Double(count)
        return ratio
    }

    // MARK: - Private

    /// Downsample a CGImage to a small grayscale pixel buffer.
    private func grayscaleThumbnail(_ image: CGImage) -> [UInt8]? {
        let size = Self.thumbSize
        let bytesPerRow = size
        var pixels = [UInt8](repeating: 0, count: size * size)

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            log.error("Failed to create grayscale context")
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return pixels
    }
}
