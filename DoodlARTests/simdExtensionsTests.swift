import Testing
import simd
@testable import DoodlAR

/// Tests for SIMD math extensions.
struct simdExtensionsTests {

    @Test func translationExtraction() {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(1.0, 2.0, 3.0, 1.0)

        let translation = matrix.translation
        #expect(translation.x == 1.0)
        #expect(translation.y == 2.0)
        #expect(translation.z == 3.0)
    }

    @Test func translationInit() {
        let matrix = simd_float4x4(translation: SIMD3(5.0, 10.0, 15.0))
        #expect(matrix.translation.x == 5.0)
        #expect(matrix.translation.y == 10.0)
        #expect(matrix.translation.z == 15.0)
    }

    @Test func distanceBetweenPoints() {
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(3, 4, 0)
        #expect(a.distance(to: b) == 5.0)
    }
}
