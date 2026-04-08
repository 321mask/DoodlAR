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

    init(arView: ARView) {
        self.arView = arView
        setupGestureRecognizers()
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

        // Grow creature from flat to full size
        let targetScale = SIMD3<Float>(repeating: 0.1)
        creatureEntity.move(
            to: Transform(scale: targetScale, translation: SIMD3(0, 0.05, 0)),
            relativeTo: anchor,
            duration: morphDuration,
            timingFunction: .easeOut
        )

        try await Task.sleep(for: .milliseconds(Int(morphDuration * 1000)))

        // Cleanup: remove sketch and particles
        sketchEntity.removeFromParent()

        // Remove particles after they fade
        Task {
            try? await Task.sleep(for: .seconds(2))
            particleEntity.removeFromParent()
        }

        // Phase 3: Creature alive
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

        // Start mesh navigation on LiDAR devices (skip for static objects and dogs with baked anims)
        if isSceneReconstructionAvailable && !creatureType.isStaticObject && !isDog {
            let navigator = CreatureNavigator(anchor: anchor, entity: creatureEntity, arView: arView)
            navigator.start()
            navigators[ObjectIdentifier(creatureEntity)] = navigator
            Logger.ar.info("Navigator started for \(creatureType.displayName)")
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

    // MARK: - Gesture Recognizers

    /// Sets up tap, long-press, and pan gesture recognizers on the AR view.
    private func setupGestureRecognizers() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

        // Tap should fail if long press is recognized (prevents conflicts)
        tap.require(toFail: longPress)

        arView.addGestureRecognizer(tap)
        arView.addGestureRecognizer(longPress)
        arView.addGestureRecognizer(pan)
    }

    /// Handles a tap on the AR view — if it hits a creature, play a reaction.
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: arView)

        // Dismiss radial menu on any tap
        if appState?.isRadialMenuVisible == true {
            appState?.isRadialMenuVisible = false
            return
        }

        guard let hitEntity = arView.entity(at: location) else { return }

        if let spawned = findSpawnedEntity(from: hitEntity) {
            // Don't play tap reaction on static objects
            guard !spawned.type.isStaticObject else { return }
            playTapReaction(on: spawned.entity)
        }
    }

    /// Handles long-press: dog → show radial menu, baseball → enter hold-to-place mode.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: arView)

        switch recognizer.state {
        case .began:
            guard let hitEntity = arView.entity(at: location),
                  let spawned = findSpawnedEntity(from: hitEntity) else { return }

            if spawned.type == .dog {
                showRadialMenu(for: spawned.entity)
            } else if spawned.type == .baseball {
                baseballInteractionController?.beginHold(at: location)
            }

        case .changed:
            baseballInteractionController?.updateHold(at: location)

        case .ended, .cancelled:
            baseballInteractionController?.endHold()

        default:
            break
        }
    }

    /// Handles pan gesture on the baseball for swipe-to-throw.
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: arView)

        switch recognizer.state {
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
            let velocity = recognizer.velocity(in: arView)
            baseballInteractionController?.endPan(at: location, velocity: velocity)
            activePanTarget = nil

        case .cancelled:
            baseballInteractionController?.cancelPan()
            activePanTarget = nil

        default:
            break
        }
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

        let currentTransform = entity.transform
        let jumpHeight: Float = 0.04

        // Jump up
        let jumpUp = Transform(
            scale: SIMD3(repeating: currentTransform.scale.x * 1.15),
            rotation: currentTransform.rotation,
            translation: SIMD3(
                currentTransform.translation.x,
                currentTransform.translation.y + jumpHeight,
                currentTransform.translation.z
            )
        )

        entity.move(to: jumpUp, relativeTo: parent, duration: 0.2, timingFunction: .easeOut)

        // Come back down
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            entity.move(
                to: currentTransform,
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

    /// Attempts to load a USDZ model for the given creature type.
    private func loadUSDZModel(for type: CreatureType, tintColors: [CGColor]) async -> Entity? {
        do {
            let entity = try await Entity(named: type.modelName)

            // Normalize scale so all creatures are roughly 0.1m
            normalizeScale(of: entity, targetSize: 0.1)

            // Apply tint from sketch's dominant colors
            applyTint(to: entity, colors: tintColors, type: type)

            // Generate collision shapes for tap hit-testing
            entity.generateCollisionShapes(recursive: true)

            Logger.ar.info("Loaded USDZ model: \(type.modelName)")
            return entity
        } catch {
            Logger.ar.warning("USDZ '\(type.modelName)' not found, using placeholder: \(error.localizedDescription)")
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
        case .unknown:   return .systemIndigo
        }
    }
}
