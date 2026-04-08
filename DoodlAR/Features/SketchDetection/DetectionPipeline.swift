import CoreVideo
import CoreImage
import CoreGraphics
import os

/// Complete detection result bundling all pipeline outputs.
struct DetectionResult: Sendable {
    let classificationResult: ClassificationResult
    let sketchFeatures: SketchFeatures
    let paperCorners: DetectedRectangle
    let normalizedSketchImage: CGImage
}

/// Result from a single pipeline frame, including partial paper detection info.
struct PipelineFrameResult: Sendable {
    /// Corners of the most recently seen rectangle (even before stability).
    let paperCorners: DetectedRectangle?
    /// Whether the paper rectangle has been stably detected across multiple frames.
    let isPaperStable: Bool
    /// Full detection result (only set when all stages succeed).
    let detectionResult: DetectionResult?
}

/// Orchestrates the full sketch detection pipeline: paper detect → correct → classify → extract features.
///
/// Coordinates all three detection stages using structured concurrency and exposes
/// a single async entry point. Implements frame throttling to process at most 2 fps.
actor DetectionPipeline {
    private let paperDetector: PaperDetector
    private let sketchClassifier: SketchClassifier
    private let featureExtractor: FeatureExtractor
    private let visionService: VisionService

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Whether the pipeline is currently processing a frame.
    private var isProcessing = false

    init() {
        let visionService = VisionService()
        self.visionService = visionService
        self.paperDetector = PaperDetector(visionService: visionService)
        self.sketchClassifier = SketchClassifier()
        self.featureExtractor = FeatureExtractor(visionService: visionService)
    }

    /// Loads the ML model. Must be called before `processFrame`.
    func loadModel() async throws {
        try await sketchClassifier.loadModel()
        Logger.ml.info("Detection pipeline model loaded")
    }

    /// Processes a single camera frame through the full detection pipeline.
    ///
    /// Always returns partial paper detection info (corners, stability) even if
    /// classification fails. The full `DetectionResult` is only set when all stages succeed.
    ///
    /// - Parameter frame: The camera frame to process, wrapped for Sendable transfer.
    /// - Returns: A `PipelineFrameResult` with paper detection info and optional full result.
    func processFrame(_ frame: SendableFrame) async throws -> PipelineFrameResult {
        guard !isProcessing else {
            let corners = await paperDetector.lastSeenRectangle
            let stable = await paperDetector.isStable
            return PipelineFrameResult(paperCorners: corners, isPaperStable: stable, detectionResult: nil)
        }
        isProcessing = true
        defer { isProcessing = false }

        // Stage 1: Paper detection
        let stableRect = try await paperDetector.processFrame(frame)
        let lastSeen = await paperDetector.lastSeenRectangle
        let isStable = await paperDetector.isStable

        guard let rectangle = stableRect else {
            return PipelineFrameResult(paperCorners: lastSeen, isPaperStable: false, detectionResult: nil)
        }

        Logger.vision.debug("Stable paper detected, running classification pipeline")

        // Stages 2–4 wrapped in do/catch so classification errors don't hide paper detection
        do {
            // Stage 2: Perspective correction + normalization
            let normalizedSketch = try await visionService.extractNormalizedSketch(
                from: frame,
                rectangle: rectangle
            )

            // Stage 3: Classification via CoreML
            let classification = try await sketchClassifier.classify(normalizedSketch)

            // Stage 4: Feature extraction
            let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
            let imageSize = ciImage.extent.size
            let corners = rectangle.imageCoordinates(for: imageSize)
            let originalCrop = ciImage.perspectiveCorrected(
                topLeft: corners.topLeft,
                topRight: corners.topRight,
                bottomLeft: corners.bottomLeft,
                bottomRight: corners.bottomRight
            )

            let features = try await featureExtractor.extractFeatures(
                from: normalizedSketch,
                originalCrop: originalCrop
            )

            Logger.ml.info("Pipeline complete: \(classification.creatureType.displayName) (\(String(format: "%.1f%%", classification.confidence * 100)))")

            let result = DetectionResult(
                classificationResult: classification,
                sketchFeatures: features,
                paperCorners: rectangle,
                normalizedSketchImage: normalizedSketch
            )
            return PipelineFrameResult(paperCorners: lastSeen, isPaperStable: isStable, detectionResult: result)
        } catch {
            Logger.ml.error("Classification/feature extraction failed: \(error.localizedDescription)")
            return PipelineFrameResult(paperCorners: lastSeen, isPaperStable: isStable, detectionResult: nil)
        }
    }

    /// Resets the pipeline state for a new scan.
    func reset() async {
        await paperDetector.reset()
        isProcessing = false
    }
}
