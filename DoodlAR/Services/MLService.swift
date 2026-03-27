import CoreML
import CoreGraphics
import os

/// High-level CoreML model management service.
///
/// Handles model loading, caching, and provides a simplified inference interface.
/// Wraps `SketchClassifier` for use by the detection pipeline.
actor MLService {
    private let classifier = SketchClassifier()
    private var isLoaded = false

    /// Loads the sketch classification model.
    func loadModel() async throws {
        guard !isLoaded else { return }
        try await classifier.loadModel()
        isLoaded = true
        Logger.ml.info("MLService: model loaded")
    }

    /// Classifies a normalized sketch image.
    ///
    /// - Parameter image: A 224×224 grayscale CGImage.
    /// - Returns: The classification result.
    func classify(_ image: CGImage) async throws -> ClassificationResult {
        guard isLoaded else {
            throw DoodlARError.classificationFailed(underlying: "Model not loaded")
        }
        return try await classifier.classify(image)
    }
}
