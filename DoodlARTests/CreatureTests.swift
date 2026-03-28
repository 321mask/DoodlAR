import Testing
import Foundation
import CoreGraphics
import simd
@testable import DoodlAR

/// Tests for creature models and persistence conversion.
struct CreatureTests {

    // MARK: - CreatureType.from(label:)

    @Test func fromLabelCaseInsensitive() {
        #expect(CreatureType.from(label: "Apple") == .apple)
        #expect(CreatureType.from(label: "APPLE") == .apple)
        #expect(CreatureType.from(label: "apple") == .apple)
        #expect(CreatureType.from(label: "BANANA") == .banana)
    }

    @Test func fromLabelAllKnownTypes() {
        for type in CreatureType.allCases where type != .unknown {
            #expect(CreatureType.from(label: type.rawValue) == type)
        }
    }

    @Test func fromLabelUnknownStrings() {
        #expect(CreatureType.from(label: "dragon") == .unknown)
        #expect(CreatureType.from(label: "cat") == .unknown)
        #expect(CreatureType.from(label: "unicorn") == .unknown)
        #expect(CreatureType.from(label: "") == .unknown)
    }

    // MARK: - ClassificationResult

    @Test func confidenceThresholdApplication() {
        let highConfidence = ClassificationResult(
            creatureType: .apple,
            confidence: 0.85,
            topAlternatives: []
        )
        #expect(highConfidence.confidence >= ClassificationResult.confidenceThreshold)

        let lowConfidence = ClassificationResult(
            creatureType: .apple,
            confidence: 0.2,
            topAlternatives: []
        )
        #expect(lowConfidence.confidence < ClassificationResult.confidenceThreshold)
    }

    // MARK: - SketchFeatures

    @Test func sketchFeaturesEmptyDefaults() {
        let empty = SketchFeatures.empty
        #expect(empty.boundingAspectRatio == 1.0)
        #expect(empty.silhouetteComplexity == 0.0)
        #expect(empty.dominantColors.isEmpty)
    }

    @Test func sketchFeaturesCustomValues() {
        let features = SketchFeatures(
            boundingAspectRatio: 1.5,
            dominantColors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1)],
            silhouetteComplexity: 2.3
        )
        #expect(features.boundingAspectRatio == 1.5)
        #expect(features.dominantColors.count == 1)
        #expect(features.silhouetteComplexity == 2.3)
    }

    // MARK: - SpawnState

    @Test func spawnStateShouldSpawnOnlyForDetected() {
        let states: [(SpawnState, Bool)] = [
            (.idle, false),
            (.scanning, false),
            (.detected(paperPosition: .init(translation: .zero)), true),
            (.classifying, false),
            (.morphing, false),
            (.alive(creatureID: UUID()), false),
            (.failed(.paperNotFound), false),
        ]

        for (state, expected) in states {
            #expect(state.shouldSpawn == expected)
        }
    }

    // MARK: - Creature Model

    @Test func creatureInitialization() {
        // Create a minimal 1x1 CGImage for testing
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        let creature = Creature(
            type: .apple,
            sketchImage: image,
            features: .empty,
            confidence: 0.92
        )

        #expect(creature.type == .apple)
        #expect(creature.confidence == 0.92)
        #expect(creature.nickname == nil)
    }

    // MARK: - DetectedRectangle

    @Test func detectedRectangleImageCoordinateConversion() {
        let rect = DetectedRectangle(
            topLeft: CGPoint(x: 0.0, y: 1.0),
            topRight: CGPoint(x: 1.0, y: 1.0),
            bottomRight: CGPoint(x: 1.0, y: 0.0),
            bottomLeft: CGPoint(x: 0.0, y: 0.0),
            confidence: 1.0
        )

        let coords = rect.imageCoordinates(for: CGSize(width: 100, height: 200))
        #expect(coords.topLeft == CGPoint(x: 0, y: 200))
        #expect(coords.topRight == CGPoint(x: 100, y: 200))
        #expect(coords.bottomRight == CGPoint(x: 100, y: 0))
        #expect(coords.bottomLeft == CGPoint(x: 0, y: 0))
    }

    // MARK: - ContourAnalysis

    @Test func contourAnalysisDefaults() {
        let analysis = ContourAnalysis(boundingAspectRatio: 1.0, silhouetteComplexity: 0.0)
        #expect(analysis.boundingAspectRatio == 1.0)
        #expect(analysis.silhouetteComplexity == 0.0)
    }
}
