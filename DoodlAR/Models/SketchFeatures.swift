import CoreGraphics

/// Visual features extracted from the user's sketch via contour analysis and color sampling.
struct SketchFeatures: Sendable {
    /// Width-to-height ratio of the sketch's bounding box.
    let boundingAspectRatio: Float

    /// Dominant colors sampled from the original (pre-thresholded) sketch crop.
    /// Typically 3–5 colors extracted via `CIAreaAverage` on contour-bounded regions.
    let dominantColors: [CGColor]

    /// Ratio of contour perimeter to bounding box perimeter.
    /// Higher values indicate more detailed/complex sketches.
    let silhouetteComplexity: Float

    /// Empty placeholder features for stubs and tests.
    static let empty = SketchFeatures(
        boundingAspectRatio: 1.0,
        dominantColors: [],
        silhouetteComplexity: 0.0
    )
}
