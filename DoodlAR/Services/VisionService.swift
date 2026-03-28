import Vision
import CoreImage
import CoreGraphics
import os

/// Detected rectangle corners in normalized Vision coordinates (0–1, origin bottom-left).
struct DetectedRectangle: Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    let confidence: Float

    /// Converts Vision normalized coordinates to CIImage coordinates for a given image size.
    func imageCoordinates(for imageSize: CGSize) -> (
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        (
            topLeft: CGPoint(x: topLeft.x * imageSize.width, y: topLeft.y * imageSize.height),
            topRight: CGPoint(x: topRight.x * imageSize.width, y: topRight.y * imageSize.height),
            bottomRight: CGPoint(x: bottomRight.x * imageSize.width, y: bottomRight.y * imageSize.height),
            bottomLeft: CGPoint(x: bottomLeft.x * imageSize.width, y: bottomLeft.y * imageSize.height)
        )
    }
}

/// Sendable summary of contour analysis results.
struct ContourAnalysis: Sendable {
    let boundingAspectRatio: Float
    let silhouetteComplexity: Float
}

/// Handles all Vision framework requests on a background actor.
actor VisionService {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Rectangle Detection

    /// Detects the most prominent rectangle in the given pixel buffer.
    ///
    /// - Parameter pixelBuffer: Camera frame to analyze.
    /// - Returns: The detected rectangle, or `nil` if no rectangle was found.
    func detectRectangle(in frame: SendableFrame) throws -> DetectedRectangle? {
        let request = VNDetectRectanglesRequest()
        // [MODIFICA] Parametri molto più rilassati per trovare subito il foglio anche in condizioni non ottimali
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.05
        request.minimumConfidence = 0.2
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Logger.vision.error("Rectangle detection failed: \(error.localizedDescription)")
            throw DoodlARError.visionRequestFailed(underlying: error.localizedDescription)
        }

        guard let observation = request.results?.first else {
            return nil
        }

        return DetectedRectangle(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft,
            confidence: observation.confidence
        )
    }

    // MARK: - Perspective Correction + Thresholding

    /// Extracts a normalized sketch image from the source using detected rectangle corners.
    ///
    /// Runs the full normalization pipeline: perspective correction → contrast → binarization → resize to 224×224.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The source camera frame.
    ///   - rectangle: The detected paper rectangle with normalized coordinates.
    /// - Returns: A clean 224×224 CGImage ready for classification.
    func extractNormalizedSketch(
        from frame: SendableFrame,
        rectangle: DetectedRectangle
    ) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let imageSize = ciImage.extent.size
        let corners = rectangle.imageCoordinates(for: imageSize)

        return try CIImage.normalizeSketch(
            from: ciImage,
            corners: corners,
            context: ciContext
        )
    }

    // MARK: - Contour Analysis

    /// Detects contours and computes analysis metrics from a binarized sketch image.
    ///
    /// Returns a Sendable `ContourAnalysis` instead of raw `VNContoursObservation`
    /// to allow safe cross-actor access.
    ///
    /// - Parameter cgImage: A thresholded (black-on-white) sketch image.
    /// - Returns: Contour analysis metrics.
    func analyzeContours(in cgImage: CGImage) throws -> ContourAnalysis {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Logger.vision.error("Contour detection failed: \(error.localizedDescription)")
            throw DoodlARError.contourExtractionFailed(underlying: error.localizedDescription)
        }

        guard let firstContour = request.results?.first else {
            return ContourAnalysis(boundingAspectRatio: 1.0, silhouetteComplexity: 0.0)
        }

        // Compute aspect ratio
        let boundingBox = firstContour.normalizedPath.boundingBox
        let aspectRatio: Float = boundingBox.height > 0
            ? Float(boundingBox.width / boundingBox.height)
            : 1.0

        // Compute complexity
        let boxPerimeter = 2 * (boundingBox.width + boundingBox.height)
        let complexity: Float
        if boxPerimeter > 0 {
            let pointCount = firstContour.contourCount
            let estimatedPerimeter = Float(pointCount) * 0.01
            complexity = min(estimatedPerimeter / Float(boxPerimeter), 5.0)
        } else {
            complexity = 0.0
        }

        return ContourAnalysis(
            boundingAspectRatio: aspectRatio,
            silhouetteComplexity: complexity
        )
    }
}
