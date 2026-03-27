import Foundation

/// Output of the CoreML sketch classification pipeline.
struct ClassificationResult: Sendable {
    /// The most likely creature type.
    let creatureType: CreatureType

    /// Confidence score for the top prediction (0.0–1.0).
    let confidence: Float

    /// Runner-up predictions sorted by descending confidence.
    let topAlternatives: [(CreatureType, Float)]

    /// Minimum confidence threshold below which the result is treated as `.unknown`.
    static let confidenceThreshold: Float = 0.4
}
