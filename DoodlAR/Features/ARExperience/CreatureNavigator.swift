import Foundation
import RealityKit
import simd
import os

/// Navigates a creature entity on the real-world scene mesh detected by LiDAR.
///
/// Uses a simple state machine (idle → walking → idle) to move creatures
/// to random nearby points on the mesh surface via raycasting.
/// Creatures stay grounded by raycasting downward to find surface height.
@MainActor
final class CreatureNavigator {

    enum NavigationState {
        case idle
        case walking
    }

    private let anchor: AnchorEntity
    private let entity: Entity
    private weak var arView: ARView?
    private var navigationTask: Task<Void, Never>?
    private(set) var state: NavigationState = .idle

    private let walkSpeed: Float = 0.03 // m/s
    private let idlePauseRange: ClosedRange<Double> = 2...5
    private let wanderRadius: ClosedRange<Float> = 0.05...0.2

    init(anchor: AnchorEntity, entity: Entity, arView: ARView) {
        self.anchor = anchor
        self.entity = entity
        self.arView = arView
    }

    /// Starts the navigation loop. The creature will alternate between idle pauses and walking.
    func start() {
        navigationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.entity.parent != nil else { return }

                // Idle pause
                self.state = .idle
                let idleDuration = Double.random(in: self.idlePauseRange)
                try? await Task.sleep(for: .seconds(idleDuration))

                guard !Task.isCancelled, self.entity.parent != nil else { return }

                // Try to find a target on the mesh and walk there
                if let target = self.findTargetOnMesh() {
                    self.state = .walking
                    await self.walkTo(target)
                }
            }
        }
    }

    /// Stops navigation and cancels the movement loop.
    func stop() {
        navigationTask?.cancel()
        navigationTask = nil
        state = .idle
    }

    // MARK: - Mesh Raycasting

    /// Finds a random target point on the scene mesh near the creature's current position.
    private func findTargetOnMesh() -> SIMD3<Float>? {
        guard let arView else { return nil }

        // Get the anchor's world position as the creature's base
        let anchorWorldPos = anchor.position(relativeTo: nil)

        // Pick a random direction and distance
        let angle = Float.random(in: 0...(2 * .pi))
        let distance = Float.random(in: wanderRadius)
        let offset = SIMD3<Float>(cos(angle) * distance, 0, sin(angle) * distance)
        // Probe from slightly above to optimize raycast performance
        let probeOrigin = SIMD3<Float>(
            anchorWorldPos.x + offset.x,
            anchorWorldPos.y + 0.3,
            anchorWorldPos.z + offset.z
        )

        // Raycast straight down to find the mesh surface
        let results = arView.scene.raycast(
            origin: probeOrigin,
            direction: SIMD3(0, -1, 0),
            length: 1.0,
            query: .nearest,
            mask: .all
        )

        guard let hit = results.first else {
            Logger.ar.debug("Navigator raycast missed — no mesh surface found")
            return nil
        }

        // Ledge detection: reject targets with >5cm altitude difference (prevents falling off table)
        let altitudeDelta = anchorWorldPos.y - hit.position.y
        if abs(altitudeDelta) > 0.05 {
            Logger.ar.debug("Ledge detected (altitude delta > 5cm). Target rejected.")
            return nil
        }

        return hit.position
    }

    // MARK: - Movement

    /// Moves the anchor to the target world position over time, keeping the creature grounded.
    private func walkTo(_ targetWorldPos: SIMD3<Float>) async {
        let currentWorldPos = anchor.position(relativeTo: nil)

        let delta = targetWorldPos - currentWorldPos
        let horizontalDistance = simd_length(SIMD2(delta.x, delta.z))

        guard horizontalDistance > 0.005 else { return }

        let duration = TimeInterval(horizontalDistance / walkSpeed)

        // Rotate the anchor so the creature faces the movement direction
        let forward = SIMD3<Float>(0, 0, 1)
        let targetDir = normalize(SIMD3<Float>(delta.x, 0, delta.z))
        let rotation = simd_quatf(from: forward, to: targetDir)

        // Build the target transform in world space
        let targetTransform = Transform(
            scale: anchor.scale,
            rotation: rotation,
            translation: targetWorldPos
        )

        anchor.move(
            to: targetTransform,
            relativeTo: nil,
            duration: duration,
            timingFunction: .easeInOut
        )

        try? await Task.sleep(for: .seconds(duration))
    }
}
