import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// Extracts visual features from sketches using contour analysis and color sampling.
///
/// Produces `SketchFeatures` that inform creature model variant selection and material tinting.
actor FeatureExtractor {
    private let visionService: VisionService
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(visionService: VisionService = VisionService()) {
        self.visionService = visionService
    }

    /// Extracts features from a normalized sketch image and its original (pre-thresholded) source.
    ///
    /// - Parameters:
    ///   - thresholdedSketch: The binarized 224×224 sketch image.
    ///   - originalCrop: The original (color) perspective-corrected crop, before thresholding.
    /// - Returns: Extracted sketch features.
    func extractFeatures(
        from thresholdedSketch: CGImage,
        originalCrop: CIImage?
    ) async throws -> SketchFeatures {
        // Contour analysis — returns Sendable ContourAnalysis
        let analysis = try await visionService.analyzeContours(in: thresholdedSketch)

        // Color sampling from the original crop
        let colors: [CGColor]
        if let originalCrop {
            colors = sampleDominantColors(from: originalCrop)
        } else {
            colors = []
        }

        let features = SketchFeatures(
            boundingAspectRatio: analysis.boundingAspectRatio,
            dominantColors: colors,
            silhouetteComplexity: analysis.silhouetteComplexity
        )

        Logger.vision.debug("Features: aspect=\(analysis.boundingAspectRatio), complexity=\(analysis.silhouetteComplexity), colors=\(colors.count)")
        return features
    }

    // MARK: - Private Helpers

    /// Samples dominant colors from the original crop using CIAreaAverage.
    private func sampleDominantColors(from image: CIImage) -> [CGColor] {
        let extent = image.extent
        let gridSize = 3
        var colors: [CGColor] = []

        let cellWidth = extent.width / CGFloat(gridSize)
        let cellHeight = extent.height / CGFloat(gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let rect = CGRect(
                    x: extent.origin.x + CGFloat(col) * cellWidth,
                    y: extent.origin.y + CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )

                let filter = CIFilter.areaAverage()
                filter.inputImage = image
                filter.extent = rect

                guard let output = filter.outputImage else { continue }

                var pixel = [Float](repeating: 0, count: 4)
                ciContext.render(
                    output,
                    toBitmap: &pixel,
                    rowBytes: 16,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBAf,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )

                let color = CGColor(
                    red: CGFloat(pixel[0]),
                    green: CGFloat(pixel[1]),
                    blue: CGFloat(pixel[2]),
                    alpha: CGFloat(pixel[3])
                )
                colors.append(color)
            }
        }

        // Deduplicate similar colors and limit to 5
        return Array(colors.prefix(5))
    }
}
