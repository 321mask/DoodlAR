import simd

/// SIMD math helpers for AR positioning and creature animation.
extension simd_float4x4 {
    /// Extracts the translation (position) component from a 4×4 transform matrix.
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Creates a translation-only transform matrix.
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4(translation, 1)
    }
}

extension SIMD3 where Scalar == Float {
    /// Distance between two 3D points.
    func distance(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }
}
