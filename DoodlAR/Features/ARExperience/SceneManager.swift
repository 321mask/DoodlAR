import RealityKit
import ARKit
import os

/// Manages the AR scene mesh for creature interaction, occlusion, and lighting.
///
/// Responsibilities:
/// - Enable scene reconstruction (LiDAR mesh) with collision shapes
/// - Enable environment occlusion so creatures appear behind real furniture
/// - Manage lighting estimation for realistic creature materials
/// - Expose mesh query capabilities for creature navigation
@MainActor
final class SceneManager {
    /// The AR view — exposed for scene raycasting by CreatureNavigator.
    let arView: ARView

    /// Whether scene reconstruction is available (LiDAR devices only).
    private(set) var isSceneReconstructionAvailable = false

    init(arView: ARView) {
        self.arView = arView
        self.isSceneReconstructionAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Configures the scene for creature interaction.
    ///
    /// Enables scene mesh collisions, occlusion, and environment lighting.
    func configureScene() {
        // Enable occlusion from real-world geometry
        arView.environment.sceneUnderstanding.options.insert(.occlusion)

        // Enable physics on scene mesh so creatures can collide with surfaces
        arView.environment.sceneUnderstanding.options.insert(.physics)

        // Enable collision on scene mesh for raycasting (creature navigation)
        arView.environment.sceneUnderstanding.options.insert(.collision)

        // Enable scene mesh visualization for debug (can be toggled)
        #if DEBUG
        // arView.debugOptions.insert(.showSceneUnderstanding)
        #endif

        Logger.ar.info("Scene configured: occlusion=true, physics=true, collision=true, sceneReconstruction=\(self.isSceneReconstructionAvailable)")
    }

    /// Adds debug visualization options.
    func enableDebugVisualization() {
        arView.debugOptions = [
            .showSceneUnderstanding,
            .showWorldOrigin,
            .showAnchorOrigins
        ]
        Logger.ar.debug("Debug visualization enabled")
    }

    /// Removes debug visualization.
    func disableDebugVisualization() {
        arView.debugOptions = []
    }
}
