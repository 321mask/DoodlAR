import RealityKit
import Combine
import os

/// Manages loading and playing multi-animation sequences for the dog creature model.
///
/// Loads 4 USDA files (idle, walk, spawn, tap_react) that share the same skeleton,
/// extracts their animation resources, and provides methods to play them with smooth transitions.
/// Animation completion is detected via `AnimationEvents.PlaybackCompleted` to chain
/// one-shot animations (spawn, tap_react) back into the idle loop.
@MainActor
final class DogAnimationController {

    enum AnimationState {
        case none
        case spawning
        case idle
        case walking
        case tapReacting
    }

    /// The primary dog entity displayed in the scene.
    private(set) var entity: Entity?

    /// Current animation state.
    private(set) var state: AnimationState = .none

    // MARK: - Animation Resources

    private var idleAnimation: AnimationResource?
    private var walkAnimation: AnimationResource?
    private var spawnAnimation: AnimationResource?
    private var tapReactAnimation: AnimationResource?

    /// Active playback controller for the current animation.
    private var currentController: AnimationPlaybackController?

    /// Subscription for animation completion events (one-shot animations).
    private var completionSubscription: (any Cancellable)?

    /// The AR view's scene for subscribing to animation events.
    private weak var arView: ARView?

    init(arView: ARView) {
        self.arView = arView
    }

    // MARK: - Loading

    /// Loads the dog model from `idle2.usda` and extracts animations from all 4 USDA files.
    ///
    /// The primary entity comes from `idle2.usda`. The other 3 files are loaded only to
    /// extract their `availableAnimations` — they share the same skeleton so animations
    /// are interchangeable.
    func loadModel() async throws -> Entity {
        // Load the primary entity (the one displayed in the scene)
        let idleEntity = try await Entity(named: "idle2")
        self.entity = idleEntity

        // Extract idle animation
        if let anim = idleEntity.availableAnimations.first {
            self.idleAnimation = anim
            Logger.ar.debug("DogAnimationController: idle animation loaded")
        }

        // Load secondary entities concurrently — only for their animations
        async let walkLoad = Entity(named: "walk_dog2")
        async let spawnLoad = Entity(named: "spawn_dog2")
        async let tapReactLoad = Entity(named: "tap_react2")

        do {
            let walkEntity = try await walkLoad
            if let anim = walkEntity.availableAnimations.first {
                self.walkAnimation = anim
                Logger.ar.debug("DogAnimationController: walk animation loaded")
            }
        } catch {
            Logger.ar.warning("DogAnimationController: failed to load walk animation: \(error.localizedDescription)")
        }

        do {
            let spawnEntity = try await spawnLoad
            if let anim = spawnEntity.availableAnimations.first {
                self.spawnAnimation = anim
                Logger.ar.debug("DogAnimationController: spawn animation loaded")
            }
        } catch {
            Logger.ar.warning("DogAnimationController: failed to load spawn animation: \(error.localizedDescription)")
        }

        do {
            let tapReactEntity = try await tapReactLoad
            if let anim = tapReactEntity.availableAnimations.first {
                self.tapReactAnimation = anim
                Logger.ar.debug("DogAnimationController: tap_react animation loaded")
            }
        } catch {
            Logger.ar.warning("DogAnimationController: failed to load tap_react animation: \(error.localizedDescription)")
        }

        let count = [idleAnimation, walkAnimation, spawnAnimation, tapReactAnimation]
            .compactMap { $0 }.count
        Logger.ar.info("DogAnimationController: loaded dog model with \(count)/4 animations")

        return idleEntity
    }

    // MARK: - Animation Playback

    /// Plays the spawn animation once, then automatically transitions to idle.
    func playSpawn() {
        guard let entity, let spawnAnimation else {
            Logger.ar.warning("DogAnimationController: spawn animation unavailable, falling back to idle")
            playIdle()
            return
        }

        state = .spawning
        completionSubscription?.cancel()
        currentController = entity.playAnimation(spawnAnimation, transitionDuration: 0.0)

        subscribeToCompletion { [weak self] in
            self?.playIdle()
        }
    }

    /// Plays the idle animation in an infinite loop.
    func playIdle() {
        guard let entity, let idleAnimation else { return }

        state = .idle
        completionSubscription?.cancel()
        completionSubscription = nil
        let looping = idleAnimation.repeat()
        currentController = entity.playAnimation(looping, transitionDuration: 0.3)
    }

    /// Plays the walk animation in an infinite loop.
    func playWalk() {
        guard let entity, let walkAnimation else { return }

        state = .walking
        completionSubscription?.cancel()
        completionSubscription = nil
        let looping = walkAnimation.repeat()
        currentController = entity.playAnimation(looping, transitionDuration: 0.3)
    }

    /// Stops walking and transitions back to idle.
    func stopWalk() {
        guard state == .walking else { return }
        playIdle()
    }

    /// Plays the tap reaction animation once, then returns to idle.
    func playTapReact() {
        guard let entity, let tapReactAnimation else { return }
        // Don't interrupt spawn
        guard state != .spawning else { return }

        state = .tapReacting
        completionSubscription?.cancel()
        currentController = entity.playAnimation(tapReactAnimation, transitionDuration: 0.15)

        subscribeToCompletion { [weak self] in
            self?.playIdle()
        }
    }

    /// Cleans up subscriptions and state.
    func cleanup() {
        completionSubscription?.cancel()
        completionSubscription = nil
        currentController = nil
        state = .none
    }

    // MARK: - Private

    /// Subscribes to `AnimationEvents.PlaybackCompleted` on the entity and invokes the handler once.
    private func subscribeToCompletion(handler: @escaping @MainActor @Sendable () -> Void) {
        guard let entity, let scene = arView?.scene else { return }

        completionSubscription = scene.subscribe(
            to: AnimationEvents.PlaybackCompleted.self,
            on: entity
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}
