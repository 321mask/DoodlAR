import ARKit
import RealityKit
import Combine
import os

/// Manages the AR session lifecycle, frame delivery, and tracking state.
///
/// Acts as the `ARSessionDelegate` to receive camera frames for the Vision pipeline
/// and tracking status updates for user guidance.
@Observable
@MainActor
final class ARViewModel: NSObject, @unchecked Sendable {

    /// The RealityKit AR view — created once and reused.
    @ObservationIgnored
    let arView: ARView = {
        let view = ARView(frame: .zero)
        view.renderOptions = [.disableMotionBlur]
        return view
    }()

    /// Manages scene mesh, occlusion, and physics.
    @ObservationIgnored
    private(set) var sceneManager: SceneManager!

    /// Handles creature spawn sequences.
    @ObservationIgnored
    private(set) var creatureSpawner: CreatureSpawner!

    /// Reference to global app state (set externally after init).
    @ObservationIgnored
    weak var appState: AppState? {
        didSet { creatureSpawner?.appState = appState }
    }

    override init() {
        super.init()
        sceneManager = SceneManager(arView: arView)
        creatureSpawner = CreatureSpawner(arView: arView)
    }

    /// Current AR tracking state for UI guidance messages.
    var trackingMessage: String?

    /// Whether the AR session is running.
    private(set) var isSessionRunning = false

    /// Callback invoked on each new camera frame (on ARSession's delegate queue).
    /// Set by the detection pipeline to receive frames for processing.
    /// Uses `@ObservationIgnored` since this is infrastructure, not observable state.
    @ObservationIgnored
    nonisolated(unsafe) var onFrameReceived: (@Sendable (CVPixelBuffer) -> Void)?

    // MARK: - Session Lifecycle

    /// Configures and starts the AR session with plane detection and scene reconstruction.
    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.frameSemantics = [.personSegmentationWithDepth]

        // Enable scene reconstruction on LiDAR devices
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        // Enable environment texturing for realistic lighting
        configuration.environmentTexturing = .automatic

        arView.session.delegate = self
        arView.session.run(configuration)
        isSessionRunning = true

        // Configure scene understanding
        sceneManager.configureScene()

        // Let the spawner know if mesh navigation is possible
        creatureSpawner.isSceneReconstructionAvailable = sceneManager.isSceneReconstructionAvailable

        Logger.ar.info("AR session started with plane detection and scene reconstruction")
    }

    /// Pauses the AR session.
    func pauseSession() {
        arView.session.pause()
        isSessionRunning = false
        Logger.ar.info("AR session paused")
    }

    /// Performs a raycast from a screen point to find a world-space surface position.
    ///
    /// - Parameter screenPoint: The screen-space point to raycast from.
    /// - Returns: The world transform of the hit point, or `nil` if no surface was found.
    func raycastFromPoint(_ screenPoint: CGPoint) -> simd_float4x4? {
        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        return results.first?.worldTransform
    }

    /// Raycasts from the center of the screen.
    func raycastFromCenter() -> simd_float4x4? {
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        if let hit = raycastFromPoint(center) {
            return hit
        }
        
        // [MODIFICA] Fallback di emergenza: se l'ARKit non capisce la profondità 
        // a causa del vetro dell'iPad o del tavolo uniforme, spawna la creatura a 40cm dalla telecamera.
        // Calcolato in coordinate mondo orizzontali per evitare che si infili SOTTO il tavolo se guardi in giù!
        let cameraMatrix = arView.cameraTransform.matrix
        var newTransform = matrix_identity_float4x4
        let forwardZ = cameraMatrix.columns.2.z
        let forwardX = cameraMatrix.columns.2.x
        let length = sqrt(forwardX * forwardX + forwardZ * forwardZ)
        
        if length > 0.001 {
            newTransform.columns.3.x = cameraMatrix.columns.3.x - (forwardX / length) * 0.4
            newTransform.columns.3.z = cameraMatrix.columns.3.z - (forwardZ / length) * 0.4
            newTransform.columns.3.y = cameraMatrix.columns.3.y - 0.2 // 20cm più in basso della fotocamera
        } else {
            newTransform.columns.3 = cameraMatrix.columns.3
            newTransform.columns.3.y -= 0.4
        }
        return newTransform
    }

    /// Spawns a creature at the given world position.
    func spawnCreature(
        type: CreatureType,
        at worldTransform: simd_float4x4,
        sketchImage: CGImage,
        features: SketchFeatures
    ) async throws -> Entity {
        try await creatureSpawner.spawn(
            creatureType: type,
            at: worldTransform,
            sketchImage: sketchImage,
            features: features
        )
    }
}

// MARK: - ARSessionDelegate

extension ARViewModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        onFrameReceived?(pixelBuffer)
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String? = switch camera.trackingState {
        case .notAvailable:
            "AR not available on this device"
        case .limited(.initializing):
            "Initializing AR..."
        case .limited(.excessiveMotion):
            "Move the device more slowly"
        case .limited(.insufficientFeatures):
            "Point at a textured surface"
        case .limited(.relocalizing):
            "Relocalizing..."
        case .limited:
            "Limited tracking"
        case .normal:
            nil
        }

        Task { @MainActor in
            self.trackingMessage = message
            if let message {
                Logger.ar.info("Tracking state: \(message)")
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Logger.ar.error("AR session failed: \(error.localizedDescription)")
        Task { @MainActor in
            self.trackingMessage = "AR session error"
        }
    }
}
