import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import os

/// Core Image helpers for the sketch detection pipeline.
extension CIImage {

    // MARK: - Perspective Correction

    /// Applies perspective correction to extract a rectangular region as a top-down image.
    ///
    /// - Parameters:
    ///   - topLeft: Top-left corner in image coordinates.
    ///   - topRight: Top-right corner in image coordinates.
    ///   - bottomLeft: Bottom-left corner in image coordinates.
    ///   - bottomRight: Bottom-right corner in image coordinates.
    /// - Returns: A corrected, rectangular `CIImage`, or `nil` if the filter fails.
    func perspectiveCorrected(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) -> CIImage? {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = self
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight
        return filter.outputImage
    }

    // MARK: - Contrast Boost

    /// Increases contrast to make dark sketch strokes stand out against the paper.
    ///
    /// - Parameter amount: Contrast multiplier (1.0 = unchanged, 2.0 = double contrast). Default 1.8.
    /// - Returns: A contrast-boosted `CIImage`, or `nil` if the filter fails.
    func contrastBoosted(amount: Float = 1.8) -> CIImage? {
        let filter = CIFilter.colorControls()
        filter.inputImage = self
        filter.contrast = amount
        filter.brightness = 0.0
        filter.saturation = 0.0 // desaturate to grayscale
        return filter.outputImage
    }

    // MARK: - Binarization (Thresholding)

    /// Applies binary thresholding to produce clean black strokes on a white background.
    ///
    /// Pixels brighter than the threshold become white; darker pixels become black.
    /// - Parameter threshold: The luminance cutoff (0.0–1.0). Default 0.5.
    /// - Returns: A binarized `CIImage`, or `nil` if the filter fails.
    func binarized(threshold: Float = 0.5) -> CIImage? {
        // CIColorThreshold is available from iOS 17+
        let filter = CIFilter.colorThreshold()
        filter.inputImage = self
        filter.threshold = threshold
        return filter.outputImage
    }

    // MARK: - Full Sketch Normalization Pipeline

    /// Runs the complete sketch normalization pipeline: perspective correct → contrast boost → binarize → resize.
    ///
    /// - Parameters:
    ///   - corners: The four corners of the detected paper rectangle in image coordinates
    ///              ordered as (topLeft, topRight, bottomRight, bottomLeft).
    ///   - outputSize: Target output size. Default 224×224 for CoreML input.
    ///   - context: A reusable `CIContext` for rendering. Caller should cache this.
    /// - Returns: A clean, square `CGImage` ready for classification.
    /// - Throws: `DoodlARError` if any pipeline stage fails.
    static func normalizeSketch(
        from source: CIImage,
        corners: (topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint),
        outputSize: CGSize = CGSize(width: 224, height: 224),
        context: CIContext
    ) throws(DoodlARError) -> CGImage {
        // Step 1: Perspective correction
        guard let corrected = source.perspectiveCorrected(
            topLeft: corners.topLeft,
            topRight: corners.topRight,
            bottomLeft: corners.bottomLeft,
            bottomRight: corners.bottomRight
        ) else {
            throw .perspectiveCorrectionFailed
        }

        // Step 2: Contrast boost + desaturation
        guard let boosted = corrected.contrastBoosted() else {
            throw .perspectiveCorrectionFailed
        }

        // Step 3: Binary thresholding
        guard let binarized = boosted.binarized() else {
            throw .perspectiveCorrectionFailed
        }

        // Step 4: Resize to target dimensions
        let scaleX = outputSize.width / binarized.extent.width
        let scaleY = outputSize.height / binarized.extent.height
        let resized = binarized.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Step 5: Render to CGImage
        let renderRect = CGRect(origin: .zero, size: outputSize)
        guard let cgImage = context.createCGImage(resized, from: renderRect) else {
            throw .perspectiveCorrectionFailed
        }

        Logger.vision.debug("Sketch normalized to \(Int(outputSize.width))×\(Int(outputSize.height))")
        return cgImage
    }
}
