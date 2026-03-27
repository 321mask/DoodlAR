import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// SwiftData model for persisting discovered creatures across app launches.
@Model
final class PersistedCreature {
    @Attribute(.unique) var id: UUID
    var creatureTypeRaw: String
    var sketchImageData: Data
    var confidence: Float
    var discoveredAt: Date
    var nickname: String?

    // Feature data
    var boundingAspectRatio: Float
    var silhouetteComplexity: Float

    init(
        id: UUID = UUID(),
        creatureTypeRaw: String,
        sketchImageData: Data,
        confidence: Float,
        discoveredAt: Date = Date(),
        nickname: String? = nil,
        boundingAspectRatio: Float = 1.0,
        silhouetteComplexity: Float = 0.0
    ) {
        self.id = id
        self.creatureTypeRaw = creatureTypeRaw
        self.sketchImageData = sketchImageData
        self.confidence = confidence
        self.discoveredAt = discoveredAt
        self.nickname = nickname
        self.boundingAspectRatio = boundingAspectRatio
        self.silhouetteComplexity = silhouetteComplexity
    }

    /// The creature type enum value.
    var creatureType: CreatureType {
        CreatureType(rawValue: creatureTypeRaw) ?? .unknown
    }

    /// Converts a `Creature` to a persistable model.
    convenience init(from creature: Creature) {
        self.init(
            id: creature.id,
            creatureTypeRaw: creature.type.rawValue,
            sketchImageData: Self.imageToData(creature.sketchImage),
            confidence: creature.confidence,
            discoveredAt: creature.discoveredAt,
            nickname: creature.nickname,
            boundingAspectRatio: creature.features.boundingAspectRatio,
            silhouetteComplexity: creature.features.silhouetteComplexity
        )
    }

    /// Converts back to a `Creature` domain model.
    func toDomainModel() -> Creature? {
        guard let cgImage = Self.dataToImage(sketchImageData) else { return nil }
        let features = SketchFeatures(
            boundingAspectRatio: boundingAspectRatio,
            dominantColors: [],
            silhouetteComplexity: silhouetteComplexity
        )
        return Creature(
            id: id,
            type: creatureType,
            sketchImage: cgImage,
            features: features,
            confidence: confidence,
            discoveredAt: discoveredAt,
            nickname: nickname
        )
    }

    // MARK: - Image Conversion

    private static func imageToData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func dataToImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
