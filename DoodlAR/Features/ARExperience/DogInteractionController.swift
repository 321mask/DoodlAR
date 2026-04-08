import Foundation
import RealityKit
import simd
import os

/// Handles dog-to-object interactions: walking to the tent, chasing the baseball.
///
/// Coordinates with `DogAnimationController` for walk/idle animation transitions
/// and reuses the movement pattern from `CreatureNavigator` for world-space navigation.
@MainActor
final class DogInteractionController {

    enum InteractionState {
        case idle
        case walkingToTent
        case insideTent
        case chasingBall
        case reactingToBall
    }

    private(set) var state: InteractionState = .idle

    private weak var arView: ARView?
    private var interactionTask: Task<Void, Never>?

    // Dependencies (configured after dog spawns)
    private var dogAnchor: AnchorEntity?
    private var dogEntity: Entity?
    private var animationController: DogAnimationController?

    /// Walk speed for directed movement (faster than random wander).
    private let walkSpeed: Float = 0.05

    init(arView: ARView) {
        self.arView = arView
    }

    func configure(
        dogAnchor: AnchorEntity,
        dogEntity: Entity,
        animationController: DogAnimationController
    ) {
        self.dogAnchor = dogAnchor
        self.dogEntity = dogEntity
        self.animationController = animationController
    }

    // MARK: - Go to Tent

    /// Dog walks to the tent, enters it (scales down), waits, then comes back out.
    func goToTent(tentWorldPosition: SIMD3<Float>) {
        guard state == .idle else { return }
        state = .walkingToTent

        interactionTask?.cancel()
        interactionTask = Task { [weak self] in
            guard let self else { return }

            // Start walk animation
            self.animationController?.playWalk()

            // Walk to the tent (stop slightly in front)
            guard let anchor = self.dogAnchor else { return }
            let currentPos = anchor.position(relativeTo: nil)
            let direction = simd_normalize(tentWorldPosition - currentPos)
            let targetPos = tentWorldPosition - direction * 0.03

            await self.walkTo(targetPos)

            guard !Task.isCancelled else { return }

            // "Enter" tent: scale down to disappear
            self.state = .insideTent
            self.animationController?.playIdle()

            guard let entity = self.dogEntity else { return }
            let originalScale = entity.scale

            entity.move(
                to: Transform(scale: SIMD3(repeating: 0.001), translation: entity.position),
                relativeTo: entity.parent,
                duration: 0.5,
                timingFunction: .easeIn
            )

            // Stay inside tent for 3 seconds
            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }

            // Come back out: scale up
            entity.move(
                to: Transform(scale: originalScale, translation: entity.position),
                relativeTo: entity.parent,
                duration: 0.5,
                timingFunction: .easeOut
            )

            try? await Task.sleep(for: .milliseconds(500))
            self.state = .idle
        }
    }

    // MARK: - Chase Baseball

    /// Dog walks to the baseball, then plays a reaction on arrival.
    func chaseBall(ballWorldPosition: SIMD3<Float>) {
        guard state == .idle else { return }
        state = .chasingBall

        interactionTask?.cancel()
        interactionTask = Task { [weak self] in
            guard let self else { return }

            // Start walk animation
            self.animationController?.playWalk()

            // Walk to ball
            await self.walkTo(ballWorldPosition)

            guard !Task.isCancelled else { return }

            // React to ball
            self.state = .reactingToBall
            self.animationController?.playTapReact()

            // Wait for reaction to finish (tapReact auto-transitions to idle)
            try? await Task.sleep(for: .seconds(1.5))

            self.state = .idle
        }
    }

    // MARK: - Movement

    /// Moves the dog's anchor to a target world position (reuses CreatureNavigator pattern).
    private func walkTo(_ targetWorldPos: SIMD3<Float>) async {
        guard let anchor = dogAnchor else { return }

        let currentWorldPos = anchor.position(relativeTo: nil)
        let delta = targetWorldPos - currentWorldPos
        let horizontalDistance = simd_length(SIMD2(delta.x, delta.z))

        guard horizontalDistance > 0.005 else { return }

        let duration = TimeInterval(horizontalDistance / walkSpeed)

        // Rotate to face target
        let forward = SIMD3<Float>(0, 0, 1)
        let targetDir = simd_normalize(SIMD3<Float>(delta.x, 0, delta.z))
        let rotation = simd_quatf(from: forward, to: targetDir)

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

    // MARK: - Lifecycle

    /// Stops any ongoing interaction and returns to idle.
    func cancel() {
        interactionTask?.cancel()
        interactionTask = nil
        animationController?.playIdle()
        state = .idle
    }

    func cleanup() {
        cancel()
        dogAnchor = nil
        dogEntity = nil
        animationController = nil
    }
}
