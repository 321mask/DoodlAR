import Foundation
import CoreVideo
import os

/// Detects a rectangular piece of paper in the camera feed using Vision framework.
///
/// Implements stability checking — a rectangle is only considered "found" when it
/// has been consistently detected across multiple consecutive frames, preventing
/// false positives from brief misdetections.
actor PaperDetector {
    private let visionService: VisionService

    /// Number of consecutive frames a rectangle must be detected before it is considered stable.
    private let stabilityThreshold = 3

    /// Maximum allowable distance between rectangle corners across frames to be considered "same" rectangle.
    private let cornerStabilityDistance: CGFloat = 0.05

    /// Recent detection results for stability analysis.
    private var recentDetections: [DetectedRectangle] = []

    /// Whether a stable rectangle has been found.
    private(set) var isStable = false

    /// The most recent stable rectangle, or `nil` if not yet stable.
    private(set) var stableRectangle: DetectedRectangle?

    /// The most recently detected rectangle (even before stability).
    private(set) var lastSeenRectangle: DetectedRectangle?

    init(visionService: VisionService = VisionService()) {
        self.visionService = visionService
    }

    // MARK: - Public API

    /// Processes a single camera frame for paper detection.
    ///
    /// Call this at 2 fps (throttled by `DetectionPipeline`). The detector accumulates
    /// results over multiple frames and only reports a stable detection once the rectangle
    /// has been consistent for `stabilityThreshold` consecutive frames.
    ///
    /// - Parameter frame: The camera frame to analyze, wrapped for Sendable transfer.
    /// - Returns: The stable detected rectangle if one has been found, `nil` otherwise.
    func processFrame(_ frame: SendableFrame) async throws -> DetectedRectangle? {
        let detection = try await visionService.detectRectangle(in: frame)

        if let detection {
            lastSeenRectangle = detection
            addDetection(detection)
        } else {
            resetStability()
        }

        return stableRectangle
    }

    /// Resets the detector state. Call when starting a new scan session.
    func reset() {
        recentDetections.removeAll()
        isStable = false
        stableRectangle = nil
        lastSeenRectangle = nil
        Logger.vision.debug("Paper detector reset")
    }

    // MARK: - Stability Analysis

    /// Adds a new detection and checks if the rectangle is stable.
    private func addDetection(_ detection: DetectedRectangle) {
        // Check if this detection is consistent with the most recent one
        if let last = recentDetections.last, !areSimilar(last, detection) {
            // Rectangle moved too much — restart stability counting
            recentDetections.removeAll()
        }

        recentDetections.append(detection)

        // Cap the buffer size
        if recentDetections.count > stabilityThreshold * 2 {
            recentDetections.removeFirst(recentDetections.count - stabilityThreshold)
        }

        // Check stability
        if recentDetections.count >= stabilityThreshold {
            if !isStable {
                Logger.vision.info("Paper rectangle stabilized after \(self.recentDetections.count) frames")
            }
            isStable = true
            stableRectangle = detection
        }
    }

    /// Resets the stability counter (called when no rectangle is detected).
    private func resetStability() {
        if isStable {
            Logger.vision.info("Paper rectangle lost")
        }
        recentDetections.removeAll()
        isStable = false
        stableRectangle = nil
    }

    /// Checks if two rectangles are similar enough to be considered the "same" paper.
    private func areSimilar(_ a: DetectedRectangle, _ b: DetectedRectangle) -> Bool {
        let d = cornerStabilityDistance
        return distance(a.topLeft, b.topLeft) < d
            && distance(a.topRight, b.topRight) < d
            && distance(a.bottomLeft, b.bottomLeft) < d
            && distance(a.bottomRight, b.bottomRight) < d
    }

    /// Euclidean distance between two points.
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
