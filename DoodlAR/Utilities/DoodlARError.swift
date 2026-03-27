import Foundation
import CoreGraphics

/// Typed errors for all DoodlAR subsystems.
enum DoodlARError: LocalizedError, Sendable {

    // MARK: - Camera

    /// Camera access was denied or restricted by the user.
    case cameraAccessDenied

    /// The AR session failed to start or encountered a fatal error.
    case arSessionFailed(underlying: String)

    // MARK: - Vision / Paper Detection

    /// No rectangular paper region was found in the camera frame.
    case paperNotFound

    /// The detected paper rectangle has too much perspective distortion to correct.
    case excessivePerspectiveDistortion

    /// Vision request failed with an underlying error.
    case visionRequestFailed(underlying: String)

    /// Perspective correction produced an invalid image.
    case perspectiveCorrectionFailed

    // MARK: - ML Classification

    /// The CoreML model file could not be loaded.
    case modelLoadFailed(modelName: String, underlying: String)

    /// Classification inference failed.
    case classificationFailed(underlying: String)

    /// Classification confidence is below the usable threshold.
    case lowConfidence(confidence: Float)

    // MARK: - Feature Extraction

    /// Contour detection failed on the thresholded sketch.
    case contourExtractionFailed(underlying: String)

    /// Color sampling produced no valid results.
    case colorSamplingFailed

    // MARK: - Creature / Model Loading

    /// The USDZ model file for a creature type could not be found.
    case modelNotFound(creatureType: String)

    /// Entity loading from USDZ failed.
    case entityLoadFailed(modelName: String, underlying: String)

    // MARK: - Persistence

    /// SwiftData save or fetch failed.
    case persistenceFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:
            return "Camera access is required. Please enable it in Settings."
        case .arSessionFailed(let underlying):
            return "AR session failed: \(underlying)"
        case .paperNotFound:
            return "No paper detected. Hold the camera over your drawing."
        case .excessivePerspectiveDistortion:
            return "Paper is at too steep an angle. Try a more overhead view."
        case .visionRequestFailed(let underlying):
            return "Vision processing failed: \(underlying)"
        case .perspectiveCorrectionFailed:
            return "Could not correct the paper perspective."
        case .modelLoadFailed(let name, let underlying):
            return "Failed to load ML model '\(name)': \(underlying)"
        case .classificationFailed(let underlying):
            return "Classification failed: \(underlying)"
        case .lowConfidence(let confidence):
            return "Classification confidence too low (\(String(format: "%.1f%%", confidence * 100)))."
        case .contourExtractionFailed(let underlying):
            return "Contour extraction failed: \(underlying)"
        case .colorSamplingFailed:
            return "Could not sample colors from the sketch."
        case .modelNotFound(let type):
            return "3D model not found for creature type '\(type)'."
        case .entityLoadFailed(let name, let underlying):
            return "Failed to load entity '\(name)': \(underlying)"
        case .persistenceFailed(let underlying):
            return "Data persistence error: \(underlying)"
        }
    }
}
