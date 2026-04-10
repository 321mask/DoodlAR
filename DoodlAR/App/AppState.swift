import Foundation
import CoreGraphics
import RealityKit
import simd

/// The current phase of the creature spawn lifecycle.
enum SpawnState: Sendable {
    case idle
    case scanning
    case detected(paperPosition: simd_float4x4)
    case triggerSpawn
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

    /// All creatures discovered in this session (persisted via SwiftData separately).
    var discoveredCreatures: [Creature] = []

    /// Whether the onboarding entry screen is presented.
    var isEntryPresented = true

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

    // MARK: - Alive Creature

    /// The type of the currently alive creature (set after spawn completes).
    var aliveCreatureType: CreatureType?

    /// Whether the dog walk animation is active (toggled by the walk button).
    var isDogWalking = false

    // MARK: - Scene Objects & Radial Menu

    /// All creature/object types currently alive in the scene.
    var sceneObjectTypes: Set<CreatureType> = []

    /// Whether the radial menu is currently shown above the dog.
    var isRadialMenuVisible = false

    /// Screen position for the radial menu overlay.
    var radialMenuScreenPosition: CGPoint?

    /// The selected dog action from the radial menu (consumed by CameraView).
    var selectedDogAction: DogAction?

    // MARK: - Audio

    /// Whether all spatial audio is muted.
    var isMuted = false

    // MARK: - Entry / Onboarding

    /// Dismisses the onboarding entry screen.
    func dismissEntry() {
        isEntryPresented = false
    }
}
