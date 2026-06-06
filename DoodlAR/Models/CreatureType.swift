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
    /// Performs case-insensitive matching against raw values, with a small alias table
    /// so common label variants ("ball", "puppy", "shelter") still resolve to the right
    /// creature. Falls back to `.unknown` for anything we can't match.
    static func from(label: String) -> CreatureType {
        let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let direct = CreatureType(rawValue: normalized) {
            return direct
        }

        switch normalized {
        case "ball", "balls", "baseballs":
            return .baseball
        case "tents", "shelter", "camp":
            return .tent
        case "puppy", "dogs":
            return .dog
        case "kitten", "cats":
            return .cat
        case "birds":
            return .bird
        case "apples":
            return .apple
        case "bananas":
            return .banana
        default:
            return .unknown
        }
    }
}
