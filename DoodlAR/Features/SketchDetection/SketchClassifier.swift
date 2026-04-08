import CoreGraphics
import CoreML
import Vision
import os

/// Wraps the CoreML sketch classification model with a clean async interface.
///
/// Uses Vision's `VNCoreMLRequest` for inference, which handles image preprocessing
/// (resize, crop, normalization) automatically. Accepts any image classifier model —
/// the model file will be replaced with a trained `SketchClassifier.mlmodel` later.
actor SketchClassifier {
    private var vnModel: VNCoreMLModel?
    private var modelName: String = ""

    /// Loads the CoreML model from the app bundle.
    ///
    /// - Parameter modelName: The model filename without extension. Default: "SketchClassifier".
    func loadModel(named modelName: String = "SketchClassifierModel") async throws {
        self.modelName = modelName

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw DoodlARError.modelLoadFailed(modelName: modelName, underlying: "Model file not found in bundle")
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Prefer Neural Engine

        do {
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            vnModel = try VNCoreMLModel(for: mlModel)
            Logger.ml.info("Loaded ML model: \(modelName)")
        } catch {
            throw DoodlARError.modelLoadFailed(modelName: modelName, underlying: error.localizedDescription)
        }
    }

    /// Classifies a sketch image and returns the predicted creature type with confidence.
    ///
    /// - Parameter image: A `CGImage` (ideally 224×224 grayscale from the normalization pipeline).
    /// - Returns: The classification result with creature type, confidence, and alternatives.
    func classify(_ image: CGImage) throws -> ClassificationResult {
        guard let vnModel else {
            throw DoodlARError.classificationFailed(underlying: "Model not loaded. Call loadModel() first.")
        }

        var observations: [VNClassificationObservation] = []
        var requestError: Error?

        let request = VNCoreMLRequest(model: vnModel) { request, error in
            requestError = error
            observations = request.results as? [VNClassificationObservation] ?? []
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw DoodlARError.classificationFailed(underlying: error.localizedDescription)
        }

        if let requestError {
            throw DoodlARError.classificationFailed(underlying: requestError.localizedDescription)
        }

        guard let top = observations.first else {
            throw DoodlARError.classificationFailed(underlying: "No classification results")
        }

        let creatureType = CreatureType.from(label: top.identifier)
        let confidence = top.confidence

        let alternatives: [(CreatureType, Float)] = observations.dropFirst().prefix(4).map {
            (CreatureType.from(label: $0.identifier), $0.confidence)
        }

        // Apply confidence threshold — below 0.4 becomes .unknown
        let finalType = confidence >= ClassificationResult.confidenceThreshold
            ? creatureType
            : .unknown

        Logger.ml.info("Classification: \(top.identifier) → \(finalType.displayName) (\(String(format: "%.1f%%", confidence * 100)))")

        return ClassificationResult(
            creatureType: finalType,
            confidence: confidence,
            topAlternatives: alternatives
        )
    }
}
