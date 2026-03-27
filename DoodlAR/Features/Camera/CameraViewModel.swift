import Foundation
import CoreGraphics
import CoreVideo
import QuartzCore
import os

/// Manages the camera feed processing loop and coordinates with the detection pipeline.
///
/// Receives frames from `ARViewModel` and throttles them to the detection pipeline
/// at ~2 fps to avoid wasting resources on redundant processing.
@Observable
@MainActor
final class CameraViewModel {
    private let detectionPipeline = DetectionPipeline()

    /// The last time a frame was sent to the detection pipeline.
    private var lastProcessedTime: CFTimeInterval = 0

    /// Minimum interval between processed frames (0.5s = 2 fps).
    private let processingInterval: CFTimeInterval = 0.5

    /// Whether the pipeline is actively scanning for paper.
    private var isScanning = true

    /// Whether paper has been stably detected.
    var isPaperDetected = false

    /// Corners of the detected rectangle in normalized coordinates (for overlay drawing).
    var detectedCorners: DetectedRectangle?

    /// The most recent extracted sketch image (for debug display).
    var extractedSketchImage: CGImage?

    /// The most recent full detection result.
    var lastDetectionResult: DetectionResult?

    /// User-facing guidance message.
    var guidanceMessage: String = "Draw a creature on paper, then point your camera at it"

    /// Whether the ML model has been loaded.
    private(set) var isModelLoaded = false

    /// Loads the ML classification model.
    func loadModel() async {
        do {
            try await detectionPipeline.loadModel()
            isModelLoaded = true
            Logger.ml.info("CameraViewModel: model loaded")
        } catch {
            Logger.ml.error("CameraViewModel: model load failed: \(error.localizedDescription)")
        }
    }

    /// Sets up the frame callback on the AR view model.
    func bind(to arViewModel: ARViewModel) {
        arViewModel.onFrameReceived = { [weak self] pixelBuffer in
            guard let self else { return }
            let frame = SendableFrame(pixelBuffer: pixelBuffer)
            Task { @MainActor in
                await self.handleFrame(frame)
            }
        }
    }

    // MARK: - Frame Processing

    /// Handles an incoming camera frame with throttling.
    private func handleFrame(_ frame: SendableFrame) async {
        guard isScanning else { return }

        let now = CACurrentMediaTime()
        guard now - lastProcessedTime >= processingInterval else { return }
        lastProcessedTime = now

        do {
            let result = try await detectionPipeline.processFrame(frame)

            if let result {
                detectedCorners = result.paperCorners
                extractedSketchImage = result.normalizedSketchImage
                isPaperDetected = true
                lastDetectionResult = result

                let name = result.classificationResult.creatureType.displayName
                let pct = Int(result.classificationResult.confidence * 100)
                guidanceMessage = "\(name) detected (\(pct)%)"
                Logger.camera.info("Full pipeline result: \(name) at \(pct)%")
            } else {
                // Paper detector hasn't stabilized yet — show scanning state
                if !isPaperDetected {
                    guidanceMessage = "Point your camera at your drawing"
                }
            }
        } catch {
            Logger.camera.error("Frame processing error: \(error.localizedDescription)")
            if !isPaperDetected {
                guidanceMessage = "Point your camera at your drawing"
            }
        }
    }

    /// Stops scanning (e.g., when classification is accepted and spawn begins).
    func stopScanning() {
        isScanning = false
    }

    /// Resets the detector for a new scan.
    func resetDetection() async {
        await detectionPipeline.reset()
        isPaperDetected = false
        detectedCorners = nil
        extractedSketchImage = nil
        lastDetectionResult = nil
        isScanning = true
        guidanceMessage = "Draw a creature on paper, then point your camera at it"
    }
}
