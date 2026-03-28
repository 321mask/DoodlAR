import Testing
import CoreGraphics
import simd
@testable import DoodlAR

/// Tests for the paper detection pipeline components.
struct PaperDetectorTests {

    // MARK: - DetectedRectangle

    @Test func detectedRectangleConvertsToImageCoordinates() {
        let rect = DetectedRectangle(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1),
            confidence: 0.95
        )

        let imageSize = CGSize(width: 1920, height: 1080)
        let coords = rect.imageCoordinates(for: imageSize)

        #expect(coords.topLeft.x == 1920 * 0.1)
        #expect(coords.topLeft.y == 1080 * 0.9)
        #expect(coords.bottomRight.x == 1920 * 0.9)
        #expect(coords.bottomRight.y == 1080 * 0.1)
    }

    // MARK: - CreatureType

    @Test func creatureTypeModelNames() {
        #expect(CreatureType.apple.modelName == "creature_apple")
        #expect(CreatureType.unknown.modelName == "creature_unknown")
    }

    @Test func creatureTypeDisplayNames() {
        #expect(CreatureType.apple.displayName == "Apple")
        #expect(CreatureType.banana.displayName == "Banana")
    }

    @Test func allCreatureTypesExist() {
        // 2 known types + unknown
        #expect(CreatureType.allCases.count == 3)
    }

    // MARK: - ClassificationResult

    @Test func lowConfidenceThreshold() {
        #expect(ClassificationResult.confidenceThreshold == 0.4)
    }

    // MARK: - SketchFeatures

    @Test func emptySketchFeaturesDefaults() {
        let empty = SketchFeatures.empty
        #expect(empty.boundingAspectRatio == 1.0)
        #expect(empty.dominantColors.isEmpty)
        #expect(empty.silhouetteComplexity == 0.0)
    }

    // MARK: - CreatureType.from(label:)

    @Test func creatureTypeFromLabelMatchesKnownTypes() {
        #expect(CreatureType.from(label: "apple") == .apple)
        #expect(CreatureType.from(label: "Apple") == .apple)
        #expect(CreatureType.from(label: "BANANA") == .banana)
    }

    @Test func creatureTypeFromLabelReturnsUnknownForUnrecognized() {
        #expect(CreatureType.from(label: "dragon") == .unknown)
        #expect(CreatureType.from(label: "cat") == .unknown)
        #expect(CreatureType.from(label: "") == .unknown)
    }

    // MARK: - SpawnState

    @Test func spawnStateShouldSpawn() {
        let idle: SpawnState = .idle
        let scanning: SpawnState = .scanning
        let detected: SpawnState = .detected(paperPosition: .init(translation: .zero))
        let classifying: SpawnState = .classifying

        #expect(idle.shouldSpawn == false)
        #expect(scanning.shouldSpawn == false)
        #expect(detected.shouldSpawn == true)
        #expect(classifying.shouldSpawn == false)
    }
}
