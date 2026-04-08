import Foundation

/// Enum of all recognizable creature types, each mapping to a USDZ asset.
enum CreatureType: String, CaseIterable, Codable, Sendable {
    case dragon
    case bird
    case cat
    case dog
    case spider
    case fish
    case snake
    case frog
    case butterfly
    case rabbit
    case tent
    case baseball
    case apple
    case banana
    case unknown // mystery creature fallback

    /// Filename of the 3D model (without extension).
    var modelName: String {
        switch self {
        case .tent:     return "dog_tent"
        case .baseball: return "dog_baseball"
        default:        return "creature_\(rawValue)"
        }
    }

    /// Human-readable display name.
    var displayName: String { rawValue.capitalized }

    /// Whether this type is a static prop (no creature animations, no idle bob, no navigator).
    var isStaticObject: Bool {
        self == .tent || self == .baseball
    }

    /// Maps a model output label string to a `CreatureType`.
    ///
    /// Performs case-insensitive matching against raw values. Falls back to `.unknown`
    /// for unrecognized labels, allowing the system to work with any classifier model
    /// (including the test AppleBanana model during development).
    static func from(label: String) -> CreatureType {
        CreatureType(rawValue: label.lowercased()) ?? .unknown
    }
}
