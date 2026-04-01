import ScreenCaptureKit
import CoreGraphics
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "screencapture")

final class ScreenCaptureService: Sendable {
    static let shared = ScreenCaptureService()

    /// Capture the frontmost window for a given PID.
    /// Returns a CGImage, or nil if capture fails or no matching window found.
    func captureWindow(pid: pid_t) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let allWindows = content.windows
        let matchingWindows = allWindows.filter { $0.owningApplication?.processID == pid && $0.isOnScreen }

        log.debug("SCShareableContent: \(allWindows.count) total windows, \(matchingWindows.count) matching pid \(pid)")

        // Find the on-screen window belonging to this PID
        guard let window = matchingWindows
            .sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height })
            .first
        else {
            // If we got 0 total windows, it's likely a permission issue
            if allWindows.isEmpty {
                log.warning("SCShareableContent returned 0 windows — screen recording permission may not be granted")
            } else {
                log.debug("No on-screen window found for pid \(pid) among \(allWindows.count) windows")
            }
            return nil
        }

        log.debug("Capturing window: \(window.title ?? "untitled", privacy: .public) (\(Int(window.frame.width))x\(Int(window.frame.height)))")

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .automatic
        // Use 2x scale for Retina-quality OCR
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        log.debug("Captured window screenshot: \(image.width)x\(image.height)")
        return image
    }

    /// Check if screen recording permission is granted.
    static func isScreenRecordingGranted() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// Downsample a CGImage to 1x scale for VLM input.
    /// The VLM doesn't need Retina resolution for activity descriptions.
    static func downsampleForVLM(_ image: CGImage, maxDimension: Int = 1024) -> CGImage? {
        let scale: CGFloat
        if image.width > maxDimension || image.height > maxDimension {
            scale = CGFloat(maxDimension) / CGFloat(max(image.width, image.height))
        } else {
            // Already small enough (e.g. non-Retina or small window)
            return image
        }

        let newWidth = Int(CGFloat(image.width) * scale)
        let newHeight = Int(CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            log.warning("Failed to create downsample context")
            return image
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// Trigger the system permission prompt for screen recording.
    static func requestScreenRecording() {
        // Attempting to access SCShareableContent triggers the system prompt
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }
}
