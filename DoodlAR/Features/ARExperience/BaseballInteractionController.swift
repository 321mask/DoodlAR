import RealityKit
import UIKit
import simd
import os

/// Handles baseball throwing (swipe) and placement (tap-and-hold) interactions.
///
/// The ball is a static model with no baked animations. Rolling is simulated
/// programmatically by rotating the entity proportionally to distance traveled.
@MainActor
final class BaseballInteractionController {

    enum BallState {
        case idle
        case holding    // Long-press: ball follows finger on ground plane
        case dragging   // Pan: tracking swipe for throw
        case thrown     // Ball is rolling after throw
    }

    private(set) var state: BallState = .idle

    private weak var arView: ARView?
    private var ballEntity: Entity?
    private var ballAnchor: AnchorEntity?

    /// Approximate ball radius for rolling rotation calculation.
    private let ballRadius: Float = 0.015

    /// Maximum throw distance in meters.
    private let maxThrowDistance: Float = 2.0

    /// Task running the throw animation.
    private var throwAnimationTask: Task<Void, Never>?

    init(arView: ARView) {
        self.arView = arView
    }

    func configure(entity: Entity, anchor: AnchorEntity) {
        self.ballEntity = entity
        self.ballAnchor = anchor
    }

    // MARK: - Pan Gesture (Swipe to Throw)

    func beginPan(at screenPoint: CGPoint) {
        guard state == .idle else { return }
        state = .dragging
    }

    func updatePan(at screenPoint: CGPoint) {
        // Could show trajectory preview during drag — left for future polish
    }

    func endPan(at screenPoint: CGPoint, velocity: CGPoint) {
        guard state == .dragging, let arView else {
            state = .idle
            return
        }

        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard speed > 100 else {
            // Too slow — not a throw, just cancel
            state = .idle
            return
        }

        // Normalize screen velocity to a direction
        let screenDir = CGPoint(x: velocity.x / speed, y: velocity.y / speed)

        // Map screen direction to world direction using camera orientation
        let cameraTransform = arView.cameraTransform
        let cameraRight = simd_normalize(SIMD3<Float>(
            cameraTransform.matrix.columns.0.x,
            0,
            cameraTransform.matrix.columns.0.z
        ))
        let cameraForward = simd_normalize(SIMD3<Float>(
            -cameraTransform.matrix.columns.2.x,
            0,
            -cameraTransform.matrix.columns.2.z
        ))

        // Screen X → world right, screen Y (negative = forward) → world forward
        let worldDirection = simd_normalize(
            cameraRight * Float(screenDir.x) + cameraForward * Float(-screenDir.y)
        )

        // Map speed to distance (clamp to max)
        let throwForce = min(Float(speed) / 500.0, 1.0)
        let throwDistance = throwForce * maxThrowDistance

        throwBall(direction: worldDirection, distance: throwDistance)
    }

    func cancelPan() {
        if state == .dragging {
            state = .idle
        }
    }

    // MARK: - Long-Press (Hold to Place)

    func beginHold(at screenPoint: CGPoint) {
        guard state == .idle else { return }
        state = .holding
    }

    func updateHold(at screenPoint: CGPoint) {
        guard state == .holding, let arView, let anchor = ballAnchor else { return }

        // Project screen point to ground plane via raycast
        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal)
        if let hit = results.first {
            let worldPos = hit.worldTransform.translation
            anchor.setPosition(worldPos, relativeTo: nil)
        }
    }

    func endHold() {
        if state == .holding {
            state = .idle
            Logger.ar.debug("Baseball placed via hold gesture")
        }
    }

    // MARK: - Throw Animation

    /// Animates the ball along a ground trajectory with rolling rotation and easeOut deceleration.
    private func throwBall(direction: SIMD3<Float>, distance: Float) {
        guard let anchor = ballAnchor, let entity = ballEntity else { return }
        state = .thrown

        throwAnimationTask?.cancel()
        throwAnimationTask = Task { [weak self] in
            guard let self else { return }

            let startPos = anchor.position(relativeTo: nil)
            let endPos = startPos + direction * distance

            // Rolling rotation axis: perpendicular to movement direction on the ground
            let upVector = SIMD3<Float>(0, 1, 0)
            let rollAxis = simd_normalize(simd_cross(upVector, direction))

            // Total rotation = distance / ball radius (full rolling without slipping)
            let totalRotation = distance / self.ballRadius

            // Animation duration scales with distance (~0.3 m/s effective)
            let duration: TimeInterval = TimeInterval(distance / 0.3)
            let steps = 60
            let stepDuration = duration / Double(steps)

            let originalOrientation = entity.orientation

            for i in 1...steps {
                guard !Task.isCancelled else { break }

                let t = Float(i) / Float(steps)
                // Quadratic easeOut: 1 - (1 - t)^2
                let easedT = 1.0 - (1.0 - t) * (1.0 - t)

                let currentPos = simd_mix(startPos, endPos, SIMD3(repeating: easedT))
                let rollRotation = simd_quatf(angle: totalRotation * easedT, axis: rollAxis)

                anchor.setPosition(currentPos, relativeTo: nil)
                entity.orientation = rollRotation * originalOrientation

                try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
            }

            self.state = .idle
            Logger.ar.debug("Baseball throw complete, distance: \(distance)m")
        }
    }

    // MARK: - Accessors

    /// The ball's current world position (for the dog to chase).
    var worldPosition: SIMD3<Float>? {
        ballAnchor?.position(relativeTo: nil)
    }

    // MARK: - Lifecycle

    func cleanup() {
        throwAnimationTask?.cancel()
        throwAnimationTask = nil
        state = .idle
        ballEntity = nil
        ballAnchor = nil
    }
}
