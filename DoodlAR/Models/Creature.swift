import Foundation
import CoreGraphics

/// A discovered creature — the user's drawing classified and brought to life.
@Observable
final class Creature: Identifiable, @unchecked Sendable {
    let id: UUID
    let type: CreatureType
    let sketchImage: CGImage
    let features: SketchFeatures
    let confidence: Float
    let discoveredAt: Date
    var nickname: String?

    init(
        id: UUID = UUID(),
        type: CreatureType,
        sketchImage: CGImage,
        features: SketchFeatures,
        confidence: Float,
        discoveredAt: Date = Date(),
        nickname: String? = nil
    ) {
        self.id = id
        self.type = type
        self.sketchImage = sketchImage
        self.features = features
        self.confidence = confidence
        self.discoveredAt = discoveredAt
        self.nickname = nickname
    }
}
