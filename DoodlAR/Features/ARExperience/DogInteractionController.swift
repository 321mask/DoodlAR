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

    /// Tracks the ball anchor while the dog carries it during fetch.
    private var carryTask: Task<Void, Never>?

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

    /// Dog walks to the tent, steps inside (translates + scales down), waits, then steps back out.
    func goToTent(tentWorldPosition: SIMD3<Float>) {
        guard state == .idle else { return }
        state = .walkingToTent

        interactionTask?.cancel()
        interactionTask = Task { [weak self] in
            guard let self else { return }

            self.animationController?.playWalk()

            guard let anchor = self.dogAnchor, let entity = self.dogEntity else { return }
            let currentPos = anchor.position(relativeTo: nil)

            // Horizontal direction from dog to tent — used to position approach + exit points.
            let delta = tentWorldPosition - currentPos
            let horizontalDelta = SIMD3<Float>(delta.x, 0, delta.z)
            let direction: SIMD3<Float>
            if simd_length(horizontalDelta) > 0.0001 {
                direction = simd_normalize(horizontalDelta)
            } else {
                direction = SIMD3<Float>(0, 0, 1)
            }

            // Phase 1: walk up to the tent entrance.
            let approachPos = tentWorldPosition - direction * 0.06
            await self.walkTo(approachPos)

            guard !Task.isCancelled else { return }

            // Phase 2: step INTO the tent while shrinking — looks like entering, not vanishing.
            self.state = .insideTent
            let originalScale = entity.scale

            anchor.move(
                to: Transform(
                    scale: anchor.scale,
                    rotation: anchor.transform.rotation,
                    translation: tentWorldPosition
                ),
                relativeTo: nil,
                duration: 0.5,
                timingFunction: .easeIn
            )
            entity.move(
                to: Transform(scale: SIMD3(repeating: 0.001), translation: entity.position),
                relativeTo: entity.parent,
                duration: 0.5,
                timingFunction: .easeIn
            )
            try? await Task.sleep(for: .milliseconds(500))
            self.animationController?.playIdle()

            // Phase 3: rest inside the tent.
            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }

            // Phase 4: scale up and step back out of the tent.
            self.animationController?.playWalk()
            let exitPos = tentWorldPosition - direction * 0.08
            entity.move(
                to: Transform(scale: originalScale, translation: entity.position),
                relativeTo: entity.parent,
                duration: 0.5,
                timingFunction: .easeOut
            )
            anchor.move(
                to: Transform(
                    scale: anchor.scale,
                    rotation: anchor.transform.rotation,
                    translation: exitPos
                ),
                relativeTo: nil,
                duration: 0.5,
                timingFunction: .easeOut
            )

            try? await Task.sleep(for: .milliseconds(500))
            self.animationController?.playIdle()
            self.state = .idle
        }
    }

    // MARK: - Chase Baseball

    /// Dog walks to the baseball, picks it up, carries it back to where the dog started, drops it.
    func chaseBall(ballAnchor: AnchorEntity) {
        guard state == .idle else { return }
        state = .chasingBall

        interactionTask?.cancel()
        carryTask?.cancel()

        interactionTask = Task { [weak self, weak ballAnchor] in
            guard let self, let ballAnchor else { return }
            guard let dogAnchor = self.dogAnchor else { return }

            // Remember the dog's starting position — that's where the ball gets dropped.
            let homePosition = dogAnchor.position(relativeTo: nil)

            // Phase 1: walk to the ball.
            self.animationController?.playWalk()
            let ballPos = ballAnchor.position(relativeTo: nil)
            await self.walkTo(ballPos)

            guard !Task.isCancelled else { return }

            // Phase 2: brief pickup reaction.
            self.state = .reactingToBall
            self.animationController?.playTapReact()
            try? await Task.sleep(for: .milliseconds(600))

            guard !Task.isCancelled else { return }

            // Phase 3: walk home carrying the ball.
            self.animationController?.playWalk()
            self.startCarrying(ballAnchor: ballAnchor)

            await self.walkTo(homePosition)

            self.carryTask?.cancel()
            self.carryTask = nil

            guard !Task.isCancelled else { return }

            // Drop the ball just in front of the dog's snout.
            let dogPos = dogAnchor.position(relativeTo: nil)
            let dogForward = dogAnchor.transform.rotation.act(SIMD3<Float>(0, 0, 1))
            let dropPos = SIMD3<Float>(
                dogPos.x + dogForward.x * 0.04,
                dogPos.y,
                dogPos.z + dogForward.z * 0.04
            )
            ballAnchor.setPosition(dropPos, relativeTo: nil)

            self.animationController?.playIdle()
            self.state = .idle
        }
    }

    /// Drives the ball's anchor to follow the dog's mouth each tick until cancelled.
    private func startCarrying(ballAnchor: AnchorEntity) {
        carryTask?.cancel()
        carryTask = Task { [weak self, weak ballAnchor] in
            while !Task.isCancelled {
                guard let self,
                      let ballAnchor,
                      let dogAnchor = self.dogAnchor else { return }

                let dogPos = dogAnchor.position(relativeTo: nil)
                let dogRot = dogAnchor.transform.rotation
                // Place the ball at the dog's snout: slightly forward (+z local) and raised (+y).
                let mouthOffset = dogRot.act(SIMD3<Float>(0, 0.025, 0.06))
                ballAnchor.setPosition(dogPos + mouthOffset, relativeTo: nil)

                try? await Task.sleep(for: .milliseconds(33))
            }
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
        carryTask?.cancel()
        carryTask = nil
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
