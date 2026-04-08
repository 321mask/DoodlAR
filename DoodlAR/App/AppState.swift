import Foundation
import CoreGraphics
import RealityKit
import simd

/// The current phase of the creature spawn lifecycle.
enum SpawnState: Sendable {
    case idle
    case scanning
    case detected(paperPosition: simd_float4x4)
    case classifying
    case morphing
    case alive(creatureID: UUID)
    case failed(DoodlARError)
}

/// Global app state shared across all features.
@Observable
@MainActor
final class AppState {
    /// Current spawn lifecycle phase.
    var spawnState: SpawnState = .idle

    /// Whether the animated welcome entry screen is currently shown.
    var isEntryPresented = true

    /// All creatures discovered in this session (persisted via SwiftData separately).
    var discoveredCreatures: [Creature] = []

    /// Whether the collection gallery is presented.
    var isCollectionPresented = false

    /// Debug mode — shows detection overlays and classification info.
    var isDebugMode = false

    /// The most recently extracted and thresholded sketch image (for debug display).
    var debugSketchImage: CGImage?

    /// The most recent classification result (for debug display).
    var debugClassificationResult: ClassificationResult?

    // MARK: - Haptic Triggers (toggled to fire .sensoryFeedback)

    /// Toggled when classification completes successfully.
    var hapticClassification = false

    /// Toggled when a creature spawns.
    var hapticSpawn = false

    /// Toggled when an error occurs.
    var hapticError = false

    // MARK: - Audio

    /// Whether all spatial audio is muted.
    var isMuted = false

    /// Dismisses the welcome entry screen for the current launch.
    func dismissEntry() {
        isEntryPresented = false
    }

    /// Re-shows the welcome entry screen.
    func presentEntry() {
        isEntryPresented = true
    }
}
