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
    /// Stages:
    /// 1. Paper detection (rectangle finding + stability check)
    /// 2. Perspective correction + thresholding → normalized 224×224 sketch
    /// 3. Classification via CoreML
    /// 4. Feature extraction (contours, colors, complexity)
    ///
    /// - Parameter frame: The camera frame to process, wrapped for Sendable transfer.
    /// - Returns: The full detection result, or `nil` if no stable paper was found.
    func processFrame(_ frame: SendableFrame) async throws -> DetectionResult? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        // Stage 1: Paper detection
        guard let rectangle = try await paperDetector.processFrame(frame) else {
            return nil
        }

        Logger.vision.debug("Stable paper detected, running classification pipeline")

        // Stage 2: Perspective correction + normalization
        let normalizedSketch = try await visionService.extractNormalizedSketch(
            from: frame,
            rectangle: rectangle
        )

        // Stage 3: Classification via CoreML
        let classification = try await sketchClassifier.classify(normalizedSketch)

        // Stage 4: Feature extraction
        // Get original color crop for feature extraction
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

        return DetectionResult(
            classificationResult: classification,
            sketchFeatures: features,
            paperCorners: rectangle,
            normalizedSketchImage: normalizedSketch
        )
    }

    /// Resets the pipeline state for a new scan.
    func reset() async {
        await paperDetector.reset()
        isProcessing = false
    }
}
