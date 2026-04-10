import RealityKit
import UIKit
import simd
import os

/// Handles the creature spawn sequence: flat sketch → morph transition → alive 3D creature.
///
/// The spawn sequence is the game's signature moment:
/// 1. Anchor a flat quad textured with the sketch photo at the paper's world position
/// 2. Morph from flat sketch to 3D model over ~1.5 seconds with particle burst
/// 3. Creature becomes alive — bobs, responds to tap gestures
/// Tracks a spawned entity along with its type and anchor.
struct SpawnedEntity {
    let entity: Entity
    let anchor: AnchorEntity
    let type: CreatureType
}

@MainActor
final class CreatureSpawner {
    private let arView: ARView

    /// Cache of loaded USDZ/placeholder entities by creature type.
    private var entityCache: [CreatureType: Entity] = [:]

    /// All spawned entities in the scene with their type and anchor.
    private(set) var spawnedEntities: [SpawnedEntity] = []

    /// Backward-compatible accessor for existing code that iterates entities.
    var aliveCreatures: [Entity] { spawnedEntities.map(\.entity) }

    /// All creature/object types currently alive in the scene.
    var aliveTypes: Set<CreatureType> { Set(spawnedEntities.map(\.type)) }

    /// Active navigators for creatures walking on the mesh.
    private var navigators: [ObjectIdentifier: CreatureNavigator] = [:]

    /// Animation controller for dog creatures with multi-animation USDA files.
    private(set) var dogAnimationController: DogAnimationController?

    /// Handles dog-to-object interactions (walk to tent, chase ball).
    private(set) var dogInteractionController: DogInteractionController?

    /// Handles baseball throwing and placement.
    private(set) var baseballInteractionController: BaseballInteractionController?

    /// Spatial audio service for creature sounds.
    let audioService = SpatialAudioService()

    /// Whether scene reconstruction is available (determines if navigation is enabled).
    var isSceneReconstructionAvailable = false

    /// Reference to AppState for mute status (set by the view model).
    weak var appState: AppState?

    /// Tracks which entity the long-press or pan gesture started on (for baseball interactions).
    private var activePanTarget: SpawnedEntity?

    /// Stores the original scale for each entity so tap reactions never accumulate scale drift.
    private var originalScales: [ObjectIdentifier: SIMD3<Float>] = [:]

    /// The spawned entity currently being dragged via long-press.
    private var dragTarget: SpawnedEntity?

    /// Timer that continuously updates the drag target's position while held.
    private var dragTimer: Timer?

    init(arView: ARView) {
        self.arView = arView
    }

    // MARK: - Spawn Sequence

    /// Spawns a creature at the given world position with the full morph animation.
    func spawn(
        creatureType: CreatureType,
        at worldTransform: simd_float4x4,
        sketchImage: CGImage,
        features: SketchFeatures
    ) async throws -> Entity {
        Logger.ar.info("Spawning \(creatureType.displayName)")

        let anchor = AnchorEntity(world: worldTransform)

        // Phase 1: Flat sketch on the surface
        let sketchEntity = createSketchQuad(from: sketchImage)
        anchor.addChild(sketchEntity)
        arView.scene.addAnchor(anchor)

        // Show the sketch briefly to connect AR to the real drawing
        try await Task.sleep(for: .milliseconds(600))

        // Phase 2: Morph transition
        let isDog = creatureType == .dog
        let creatureEntity: Entity

        if isDog {
            // Load the dog model via the animation controller (extracts all 4 animations)
            let controller = DogAnimationController(arView: arView)
            creatureEntity = try await controller.loadModel()
            normalizeScale(of: creatureEntity, targetSize: 0.1)
            creatureEntity.generateCollisionShapes(recursive: true)
            applyTint(to: creatureEntity, colors: features.dominantColors, type: creatureType)
            dogAnimationController = controller
        } else {
            creatureEntity = await createCreatureEntity(for: creatureType, tintColors: features.dominantColors)
        }

        // Capture the target scale BEFORE shrinking to invisible
        let customTargetScale = creatureEntity.scale
        creatureEntity.scale = SIMD3(repeating: 0.001) // Start invisible
        creatureEntity.position.y = 0.0
        anchor.addChild(creatureEntity)

        // Spawn particle burst at the midpoint
        let particleEntity = createSpawnParticles(color: defaultColor(for: creatureType))
        particleEntity.position.y = 0.04
        anchor.addChild(particleEntity)

        // Play spawn sound during morph
        let isMuted = appState?.isMuted ?? false
        audioService.playSpawnSound(on: creatureEntity, isMuted: isMuted)

        // Animate: fade sketch out while growing creature
        let morphDuration: TimeInterval = 1.5

        // Fade sketch to transparent
        sketchEntity.move(
            to: Transform(
                scale: SIMD3(repeating: 0.3),
                rotation: sketchEntity.transform.rotation,
                translation: SIMD3(0, 0.03, 0)
            ),
            relativeTo: anchor,
            duration: morphDuration * 0.6,
            timingFunction: .easeIn
        )

        // Grow creature from flat to full size (rise slightly during morph)
        creatureEntity.move(
            to: Transform(scale: customTargetScale, translation: SIMD3(0, 0.06, 0)),
            relativeTo: anchor,
            duration: morphDuration,
            timingFunction: .easeOut
        )

        try await Task.sleep(for: .milliseconds(Int(morphDuration * 1000)))

        // Land on the surface after morph
        creatureEntity.move(
            to: Transform(scale: customTargetScale, translation: SIMD3(0, 0, 0)),
            relativeTo: anchor,
            duration: 0.4,
            timingFunction: .easeIn
        )
        try await Task.sleep(for: .milliseconds(400))

        // Cleanup: remove sketch and particles
        sketchEntity.removeFromParent()

        // Remove particles after they fade
        Task {
            try? await Task.sleep(for: .seconds(2))
            particleEntity.removeFromParent()
        }

        // Record the original scale so tap reactions never accumulate drift
        originalScales[ObjectIdentifier(creatureEntity)] = customTargetScale

        // Phase 3: Creature alive
        // Re-generate collision shapes now that the entity is at its final scale
        // (the morph animation changed scale from 0.001 → target, invalidating earlier shapes)
        ensureCollisionShapes(on: creatureEntity)

        if isDog, let controller = dogAnimationController {
            // Play the baked spawn animation, which auto-transitions to idle loop
            controller.playSpawn()

            // Configure the dog interaction controller for tent/ball commands
            let interactionController = DogInteractionController(arView: arView)
            interactionController.configure(
                dogAnchor: anchor,
                dogEntity: creatureEntity,
                animationController: controller
            )
            dogInteractionController = interactionController
        } else if creatureType.isStaticObject {
            // Static objects: no idle animation, no navigator, no ambient audio
            if creatureType == .baseball {
                let controller = BaseballInteractionController(arView: arView)
                controller.configure(entity: creatureEntity, anchor: anchor)
                baseballInteractionController = controller
            }
        } else {
            startIdleAnimationLoop(for: creatureEntity, anchor: anchor)
        }

        spawnedEntities.append(SpawnedEntity(entity: creatureEntity, anchor: anchor, type: creatureType))
        appState?.sceneObjectTypes.insert(creatureType)

        // Start ambient audio loop (skip for static objects)
        if !creatureType.isStaticObject {
            audioService.startAmbientLoop(
                on: creatureEntity,
                creatureType: creatureType,
                isMuted: isMuted
            )
        }

        // Prepare mesh navigator on LiDAR devices (paused — creature stays on its surface)
        if isSceneReconstructionAvailable && !creatureType.isStaticObject && !isDog {
            let navigator = CreatureNavigator(anchor: anchor, entity: creatureEntity, arView: arView)
            navigators[ObjectIdentifier(creatureEntity)] = navigator
            Logger.ar.info("Navigator initialized (paused) for \(creatureType.displayName)")
        }

        Logger.ar.info("Creature \(creatureType.displayName) spawned and alive")
        return creatureEntity
    }

    /// Removes all spawned creatures from the scene.
    func clearScene() {
        // Stop all navigators
        for (_, navigator) in navigators {
            navigator.stop()
        }
        navigators.removeAll()

        // Clean up controllers
        dogAnimationController?.cleanup()
        dogAnimationController = nil
        dogInteractionController?.cleanup()
        dogInteractionController = nil
        baseballInteractionController?.cleanup()
        baseballInteractionController = nil

        // Stop all audio
        audioService.stopAllAudio()

        arView.scene.anchors.removeAll()
        spawnedEntities.removeAll()
        originalScales.removeAll()
        appState?.sceneObjectTypes.removeAll()
        Logger.ar.info("Scene cleared")
    }

    // MARK: - Dog Walk Control

    /// Starts the dog walk animation loop.
    func startDogWalk() {
        dogAnimationController?.playWalk()
    }

    /// Stops the dog walk animation and returns to idle.
    func stopDogWalk() {
        dogAnimationController?.stopWalk()
    }

    // MARK: - Dog Actions

    /// Executes a dog action from the radial menu (go to tent, chase ball).
    func executeDogAction(_ action: DogAction) {
        guard let interactionController = dogInteractionController else { return }

        // Stop random wandering navigator for the dog
        if let dogSpawn = spawnedEntity(ofType: .dog) {
            navigators[ObjectIdentifier(dogSpawn.entity)]?.stop()
        }

        switch action {
        case .goToTent:
            guard let tentSpawn = spawnedEntity(ofType: .tent) else { return }
            let tentPos = tentSpawn.anchor.position(relativeTo: nil)
            interactionController.goToTent(tentWorldPosition: tentPos)

        case .chaseBall:
            guard let ballSpawn = spawnedEntity(ofType: .baseball) else { return }
            let ballPos = ballSpawn.anchor.position(relativeTo: nil)
            interactionController.chaseBall(ballWorldPosition: ballPos)
        }
    }

    // MARK: - Entity Lookup

    /// Returns the first spawned entity matching the given type.
    func spawnedEntity(ofType type: CreatureType) -> SpawnedEntity? {
        spawnedEntities.first(where: { $0.type == type })
    }

    /// Walks the parent chain from a hit entity to find which spawned entity was hit.
    private func findSpawnedEntity(from hitEntity: Entity) -> SpawnedEntity? {
        var target: Entity? = hitEntity
        while let entity = target {
            if let spawned = spawnedEntities.first(where: { $0.entity === entity }) {
                return spawned
            }
            target = entity.parent
        }
        return nil
    }

    // MARK: - Collision Shape Guarantee

    /// Ensures the entity (and its children) have valid collision shapes for tap detection.
    /// Called AFTER the morph animation completes so the entity is at its final scale.
    private func ensureCollisionShapes(on entity: Entity) {
        if let modelEntity = entity as? ModelEntity {
            modelEntity.generateCollisionShapes(recursive: true)
            Logger.ar.info("Generated collision shapes from ModelEntity mesh (recursive)")
            return
        }

        var foundModel = false
        for child in entity.children {
            if let childModel = child as? ModelEntity {
                childModel.generateCollisionShapes(recursive: true)
                foundModel = true
            }
        }
        if foundModel {
            Logger.ar.info("Generated collision shapes on child ModelEntities")
            return
        }

        let bounds = entity.visualBounds(relativeTo: entity)
        guard bounds.extents.x > 0, bounds.extents.y > 0, bounds.extents.z > 0 else {
            Logger.ar.warning("Visual bounds are zero — cannot create collision shape")
            return
        }
        let box = ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)
        entity.components.set(CollisionComponent(shapes: [box]))
        Logger.ar.info("Created manual box collision shape from visual bounds")
    }

    // MARK: - Tap Handling (called from TapCatcherView)

    /// Receives a tap coordinate from the SwiftUI TapCatcherView overlay.
    /// This bypasses ARView's internal gesture system which blocks taps after
    /// collision shapes are generated.
    func handleTapAtPoint(_ location: CGPoint) {
        // Dismiss radial menu on any tap
        if appState?.isRadialMenuVisible == true {
            appState?.isRadialMenuVisible = false
            return
        }

        // Strategy 1: RealityKit collision-based hit test
        if let hitEntity = arView.entity(at: location) {
            if let spawned = findSpawnedEntity(from: hitEntity) {
                guard !spawned.type.isStaticObject else { return }
                playTapReaction(on: spawned.entity)
                return
            }
        }

        // Strategy 2: Projection fallback — works even if collision shapes are broken
        var closestSpawned: SpawnedEntity?
        var closestDistance: CGFloat = .greatestFiniteMagnitude

        for spawned in spawnedEntities {
            guard !spawned.type.isStaticObject else { continue }
            let worldPos = spawned.entity.position(relativeTo: nil)
            guard let screenPos = arView.project(worldPos) else { continue }
            let dist = hypot(location.x - screenPos.x, location.y - screenPos.y)
            if dist < closestDistance {
                closestDistance = dist
                closestSpawned = spawned
            }
        }

        if closestDistance < 150, let spawned = closestSpawned {
            playTapReaction(on: spawned.entity)
        }
    }

    // MARK: - Particle Effects

    /// Creates a particle burst effect for the spawn moment.
    private func createSpawnParticles(color: UIColor) -> Entity {
        let entity = Entity()

        // Create small sparkle cubes that scatter outward
        let particleCount = 12
        for i in 0..<particleCount {
            let angle = Float(i) / Float(particleCount) * .pi * 2
            let particleMesh = MeshResource.generateBox(size: 0.005, cornerRadius: 0.001)
            let material = UnlitMaterial(color: color.withAlphaComponent(0.8))
            let particle = ModelEntity(mesh: particleMesh, materials: [material])

            // Start at center
            particle.position = .zero

            entity.addChild(particle)

            // Scatter outward
            let radius: Float = 0.06
            let targetPos = SIMD3<Float>(
                cos(angle) * radius,
                Float.random(in: 0.02...0.08),
                sin(angle) * radius
            )

            particle.move(
                to: Transform(
                    scale: SIMD3(repeating: 0.3),
                    translation: targetPos
                ),
                relativeTo: entity,
                duration: 0.8,
                timingFunction: .easeOut
            )
        }

        return entity
    }

    // MARK: - Idle Animation

    /// Starts a looping idle bob animation using a Timer-based approach.
    private func startIdleAnimationLoop(for entity: Entity, anchor: AnchorEntity) {
        let basePosition = entity.position
        let bobHeight: Float = 0.012
        let bobDuration: TimeInterval = 1.2

        // Use a recursive async loop for the bob animation
        Task { [weak entity, weak anchor] in
            var goingUp = true
            while let entity, let anchor, entity.parent != nil {
                let targetY = goingUp
                    ? basePosition.y + bobHeight
                    : basePosition.y

                let transform = Transform(
                    scale: entity.scale,
                    rotation: entity.transform.rotation,
                    translation: SIMD3(basePosition.x, targetY, basePosition.z)
                )

                entity.move(
                    to: transform,
                    relativeTo: anchor,
                    duration: bobDuration,
                    timingFunction: .easeInOut
                )

                try? await Task.sleep(for: .milliseconds(Int(bobDuration * 1000)))
                goingUp.toggle()
            }
        }
    }

    // MARK: - Gesture Handling (called from TapCatcherView)

    /// Handles a long-press gesture state from the TapCatcherView overlay.
    /// Long-press "picks up" the object — it then follows where the device points until released.
    func handleLongPress(state: UIGestureRecognizer.State, location: CGPoint) {
        switch state {
        case .began:
            // Find the entity near the long-press location
            var spawned = closestSpawnedEntity(toScreenPoint: location, maxDistance: 150)
            if spawned == nil, let hitEntity = arView.entity(at: location) {
                spawned = findSpawnedEntity(from: hitEntity)
            }
            guard let target = spawned else { return }

            if target.type == .dog {
                showRadialMenu(for: target.entity)
            }

            // Enter drag mode — freeze entity at current position
            dragTarget = target
            navigators[ObjectIdentifier(target.entity)]?.stop()
            let baseScale = originalScales[ObjectIdentifier(target.entity)] ?? target.entity.scale
            target.entity.stopAllAnimations()
            target.entity.scale = baseScale

            // Start a timer that continuously moves the entity to where the device center points.
            // This works both when the user moves their finger AND when they move the device.
            startDragTimer()

        case .ended, .cancelled:
            finishDrag()

        default:
            break
        }
    }

    /// Handles a pan gesture state from the TapCatcherView overlay.
    func handlePan(state: UIGestureRecognizer.State, location: CGPoint, velocity: CGPoint) {
        // If dragging, ignore pan
        if dragTarget != nil { return }

        switch state {
        case .began:
            guard let hitEntity = arView.entity(at: location),
                  let spawned = findSpawnedEntity(from: hitEntity),
                  spawned.type == .baseball else {
                activePanTarget = nil
                return
            }
            activePanTarget = spawned
            baseballInteractionController?.beginPan(at: location)

        case .changed:
            guard activePanTarget != nil else { return }
            baseballInteractionController?.updatePan(at: location)

        case .ended:
            guard activePanTarget != nil else { return }
            baseballInteractionController?.endPan(at: location, velocity: velocity)
            activePanTarget = nil

        case .cancelled:
            baseballInteractionController?.cancelPan()
            activePanTarget = nil

        default:
            break
        }
    }

    /// Starts a repeating timer that moves the drag target to where the center of the screen points.
    private func startDragTimer() {
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDragPosition()
            }
        }
    }

    /// Raycasts from the center of the screen and moves the drag target there.
    private func updateDragPosition() {
        guard let target = dragTarget else {
            dragTimer?.invalidate()
            dragTimer = nil
            return
        }

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = results.first else { return }

        let targetPos = SIMD3<Float>(
            hit.worldTransform.columns.3.x,
            hit.worldTransform.columns.3.y,
            hit.worldTransform.columns.3.z
        )

        // Limit movement to 0.5m per tick to prevent teleportation
        let currentPos = target.anchor.position(relativeTo: nil)
        let distance = simd_length(targetPos - currentPos)
        guard distance < 0.5 else { return }

        // Smooth movement
        target.anchor.move(
            to: Transform(
                scale: target.anchor.scale,
                rotation: target.anchor.transform.rotation,
                translation: targetPos
            ),
            relativeTo: nil,
            duration: 0.08,
            timingFunction: .linear
        )
    }

    /// Ends a drag interaction and restarts idle animations.
    private func finishDrag() {
        dragTimer?.invalidate()
        dragTimer = nil

        guard let target = dragTarget else { return }
        if !target.type.isStaticObject && target.type != .dog {
            startIdleAnimationLoop(for: target.entity, anchor: target.anchor)
        }
        ensureCollisionShapes(on: target.entity)
        dragTarget = nil
    }

    /// Finds the closest spawned entity to a screen point within a maximum distance.
    private func closestSpawnedEntity(toScreenPoint point: CGPoint, maxDistance: CGFloat) -> SpawnedEntity? {
        var closest: SpawnedEntity?
        var closestDist: CGFloat = .greatestFiniteMagnitude

        for spawned in spawnedEntities {
            let worldPos = spawned.entity.position(relativeTo: nil)
            guard let screenPos = arView.project(worldPos) else { continue }
            let dist = hypot(point.x - screenPos.x, point.y - screenPos.y)
            if dist < closestDist {
                closestDist = dist
                closest = spawned
            }
        }

        return closestDist <= maxDistance ? closest : nil
    }

    /// Shows the floating radial menu above the dog.
    private func showRadialMenu(for dogEntity: Entity) {
        let worldPos = dogEntity.position(relativeTo: nil)
        guard let screenPoint = arView.project(worldPos) else { return }

        // Only show interactions for objects in the scene (excluding the dog itself)
        let availableTypes = aliveTypes.subtracting([.dog, .unknown])
        guard !availableTypes.isEmpty else { return }

        appState?.radialMenuScreenPosition = screenPoint
        appState?.sceneObjectTypes = aliveTypes
        appState?.isRadialMenuVisible = true
    }

    /// Plays a reaction when a creature is tapped.
    private func playTapReaction(on entity: Entity) {
        Logger.ar.debug("Creature tapped — playing reaction")

        // Play tap sound
        let isMuted = appState?.isMuted ?? false
        audioService.playTapSound(on: entity, isMuted: isMuted)

        // Use baked tap_react animation for dogs
        if let controller = dogAnimationController, controller.entity === entity {
            controller.playTapReact()
            return
        }

        // Fallback bounce animation for other creature types
        guard let parent = entity.parent else { return }

        // Always use the stored original scale to prevent accumulation
        let baseScale = originalScales[ObjectIdentifier(entity)] ?? entity.scale
        let baseTranslation = entity.transform.translation
        let jumpHeight: Float = 0.04

        // Jump up with a slight scale bump
        let jumpUp = Transform(
            scale: baseScale * 1.15,
            rotation: entity.transform.rotation,
            translation: SIMD3(
                baseTranslation.x,
                baseTranslation.y + jumpHeight,
                baseTranslation.z
            )
        )

        entity.move(to: jumpUp, relativeTo: parent, duration: 0.2, timingFunction: .easeOut)

        // Come back down to exact original scale
        let restoreTransform = Transform(
            scale: baseScale,
            rotation: entity.transform.rotation,
            translation: baseTranslation
        )

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard entity.parent != nil else { return }
            entity.move(
                to: restoreTransform,
                relativeTo: parent,
                duration: 0.3,
                timingFunction: .easeIn
            )
        }
    }

    // MARK: - Entity Creation

    /// Creates the creature entity — loads USDZ if available, otherwise falls back to placeholder.
    private func createCreatureEntity(
        for type: CreatureType,
        tintColors: [CGColor]
    ) async -> Entity {
        if let cached = entityCache[type] {
            return cached.clone(recursive: true)
        }

        // Try loading a real USDZ model
        if let usdzEntity = await loadUSDZModel(for: type, tintColors: tintColors) {
            entityCache[type] = usdzEntity
            return usdzEntity.clone(recursive: true)
        }

        // Fall back to colored box placeholder
        let placeholder = createPlaceholderEntity(for: type, tintColors: tintColors)
        entityCache[type] = placeholder
        return placeholder.clone(recursive: true)
    }

    /// Attempts to load a 3D model for the given creature type.
    private func loadUSDZModel(for type: CreatureType, tintColors: [CGColor]) async -> Entity? {
        let modelName = type.modelName

        // Try loading by name first (works when file is at bundle root)
        // Then fall back to explicit URL search (works for files in subdirectories)
        do {
            let entity: ModelEntity
            if let url = Bundle.main.url(forResource: modelName, withExtension: "usdz") {
                Logger.ar.info("Found model URL: \(url.lastPathComponent)")
                entity = try await ModelEntity.loadModel(contentsOf: url)
            } else if let url = Bundle.main.url(forResource: modelName, withExtension: "usdc") {
                Logger.ar.info("Found model URL (usdc): \(url.lastPathComponent)")
                entity = try await ModelEntity.loadModel(contentsOf: url)
            } else if let url = Bundle.main.url(forResource: modelName, withExtension: "usda") {
                Logger.ar.info("Found model URL (usda): \(url.lastPathComponent)")
                entity = try await ModelEntity.loadModel(contentsOf: url)
            } else {
                // Last resort: try the named loading API
                Logger.ar.info("No bundle URL for '\(modelName)', trying loadModel(named:)")
                entity = try await ModelEntity.loadModel(named: "\(modelName).usdz")
            }

            // Per-type scale overrides for models that don't normalize well
            switch type {
            case .apple:
                entity.scale = SIMD3(repeating: 0.005)
            case .banana:
                entity.scale = SIMD3(repeating: 0.02)
            default:
                normalizeScale(of: entity, targetSize: 0.1)
            }

            // Apply tint from sketch's dominant colors
            applyTint(to: entity, colors: tintColors, type: type)

            // Generate collision shapes for tap hit-testing
            entity.generateCollisionShapes(recursive: true)

            Logger.ar.info("Loaded model: \(modelName)")
            return entity
        } catch {
            Logger.ar.warning("Model '\(modelName)' not found, using placeholder: \(error.localizedDescription)")
            return nil
        }
    }

    /// Normalizes the entity's scale so its bounding box fits within the target size.
    private func normalizeScale(of entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard maxExtent > 0 else { return }
        let scaleFactor = targetSize / maxExtent
        entity.scale = SIMD3(repeating: scaleFactor)
    }

    /// Applies a tint from the sketch's dominant colors to the model's materials.
    private func applyTint(to entity: Entity, colors: [CGColor], type: CreatureType) {
        let tintColor: UIColor
        if let firstColor = colors.first {
            tintColor = UIColor(cgColor: firstColor)
        } else {
            tintColor = defaultColor(for: type)
        }

        // Iterate over all model entities in the hierarchy
        applyTintRecursive(to: entity, tint: tintColor)
    }

    /// Recursively applies a tint to all PhysicallyBasedMaterial in an entity hierarchy.
    private func applyTintRecursive(to entity: Entity, tint: UIColor) {
        if var modelComponent = entity.components[ModelComponent.self] {
            var updatedMaterials: [any Material] = []
            for material in modelComponent.materials {
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.baseColor.tint = tint
                    updatedMaterials.append(pbr)
                } else {
                    updatedMaterials.append(material)
                }
            }
            modelComponent.materials = updatedMaterials
            entity.components.set(modelComponent)
        }
        for child in entity.children {
            applyTintRecursive(to: child, tint: tint)
        }
    }

    /// Creates a flat quad textured with the user's sketch.
    private func createSketchQuad(from sketchImage: CGImage) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 0.15, height: 0.15)

        var material = UnlitMaterial()
        if let texture = try? TextureResource(image: sketchImage, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        // Lay flat on the surface
        entity.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        return entity
    }

    /// Creates a colored box placeholder for a creature type.
    private func createPlaceholderEntity(for type: CreatureType, tintColors: [CGColor]) -> ModelEntity {
        let size: Float = 0.08
        let mesh = MeshResource.generateBox(size: size, cornerRadius: 0.008)

        let color: UIColor
        if let firstColor = tintColors.first {
            color = UIColor(cgColor: firstColor)
        } else {
            color = defaultColor(for: type)
        }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.6)
        material.metallic = .init(floatLiteral: 0.1)

        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Floating label
        let labelEntity = createLabel(type.displayName)
        labelEntity.position.y = size / 2 + 0.025
        entity.addChild(labelEntity)

        // Collision shape for tap detection and physics
        entity.generateCollisionShapes(recursive: false)

        return entity
    }

    /// Creates a text label entity.
    private func createLabel(_ text: String) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.02),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let material = UnlitMaterial(color: .white)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position.x = -bounds.extents.x / 2
        return entity
    }

    // MARK: - Color Mapping

    private func defaultColor(for type: CreatureType) -> UIColor {
        switch type {
        case .dragon:    return .systemRed
        case .bird:      return .systemCyan
        case .cat:       return .systemOrange
        case .dog:       return .systemBrown
        case .spider:    return .darkGray
        case .fish:      return .systemBlue
        case .snake:     return .systemGreen
        case .frog:      return .systemMint
        case .butterfly: return .systemPurple
        case .rabbit:    return .systemPink
        case .tent:      return .systemBrown
        case .baseball:  return .white
        case .apple:     return .systemRed
        case .banana:    return .systemYellow
        case .unknown:   return .systemIndigo
        }
    }
}
