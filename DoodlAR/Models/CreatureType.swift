import Foundation

/// Enum of all recognizable creature types, each mapping to a USDZ asset.
enum CreatureType: String, CaseIterable, Codable, Sendable {
    case apple
    case banana
    case unknown // mystery creature fallback

    /// Filename of the USDZ model (without extension).
    var modelName: String { "creature_\(rawValue)" }

    /// Human-readable display name.
    var displayName: String { rawValue.capitalized }

    /// Maps a model output label string to a `CreatureType`.
    ///
    /// Performs case-insensitive matching against raw values. Falls back to `.unknown`
    /// for unrecognized labels, allowing the system to work with any classifier model
    /// (including the test AppleBanana model during development).
    static func from(label: String) -> CreatureType {
        CreatureType(rawValue: label.lowercased()) ?? .unknown
    }
}
