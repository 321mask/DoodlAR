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
@MainActor
final class CreatureSpawner {
    private let arView: ARView

    /// Currently alive creature entities for gesture handling.
    private(set) var aliveCreatures: [Entity] = []

    /// Active navigators for creatures walking on the mesh.
    private var navigators: [ObjectIdentifier: CreatureNavigator] = [:]

    /// Spatial audio service for creature sounds.
    let audioService = SpatialAudioService()

    /// Whether scene reconstruction is available (determines if navigation is enabled).
    var isSceneReconstructionAvailable = false

    /// Reference to AppState for mute status (set by the view model).
    weak var appState: AppState?

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
        Logger.ar.info("[V10] ===== SPAWN START: type=\(creatureType.rawValue), displayName=\(creatureType.displayName), modelName=\(creatureType.modelName) =====")

        let anchor = AnchorEntity(world: worldTransform)

        // Phase 1: Flat sketch on the surface
        let sketchEntity = createSketchQuad(from: sketchImage)
        anchor.addChild(sketchEntity)
        arView.scene.addAnchor(anchor)

        // Show the sketch briefly to connect AR to the real drawing
        try await Task.sleep(for: .milliseconds(600))

        // Phase 2: Morph transition
        // [V10] Always load fresh — never clone from cache.
        // Entity.clone(recursive:) does NOT reliably clone CollisionComponent,
        // which causes arView.entity(at:) to miss the entity entirely on subsequent spawns.
        let creatureEntity = await loadFreshCreatureEntity(for: creatureType, tintColors: features.dominantColors)
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

        // Grow creature from flat to full size
        creatureEntity.move(
            to: Transform(scale: customTargetScale, translation: SIMD3(0, 0.05, 0)),
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
        // [V10 CRITICAL] After the morph animation, the entity's scale has reached its final value.
        // We MUST re-generate collision shapes NOW, on the live entity in the scene,
        // because .move() animation changes scale from 0.001→target and the collision
        // shape set at load time was computed at the original scale.
        ensureCollisionShapes(on: creatureEntity)

        aliveCreatures.append(creatureEntity)
        Logger.ar.info("[V10] Creature registered. Total alive: \(self.aliveCreatures.count)")

        // Start ambient audio loop
        audioService.startAmbientLoop(
            on: creatureEntity,
            creatureType: creatureType,
            isMuted: isMuted
        )

        // Start mesh navigation on LiDAR devices
        if isSceneReconstructionAvailable {
            let navigator = CreatureNavigator(anchor: anchor, entity: creatureEntity, arView: arView)
            navigators[ObjectIdentifier(creatureEntity)] = navigator
            Logger.ar.info("Navigator initialized (but paused) for \(creatureType.displayName)")
        }

        Logger.ar.info("Creature \(creatureType.displayName) spawned and alive")
        return creatureEntity
    }

    /// Removes all spawned creatures from the scene.
    func clearScene() {
        for (_, navigator) in navigators {
            navigator.stop()
        }
        navigators.removeAll()

        audioService.stopAllAudio()

        arView.scene.anchors.removeAll()
        aliveCreatures.removeAll()
        Logger.ar.info("Scene cleared")
    }

    // MARK: - Collision Shape Guarantee

    /// Ensures the entity (and its children) have valid collision shapes for tap detection.
    /// Called AFTER the morph animation completes so the entity is at its final scale.
    private func ensureCollisionShapes(on entity: Entity) {
        // First try: generate collision shapes from the model mesh itself.
        // This works on ModelEntity and its children.
        if let modelEntity = entity as? ModelEntity {
            modelEntity.generateCollisionShapes(recursive: true)
            Logger.ar.info("[V10] Generated collision shapes from ModelEntity mesh (recursive)")
            return
        }

        // Fallback: walk children looking for ModelEntity
        var foundModel = false
        for child in entity.children {
            if let childModel = child as? ModelEntity {
                childModel.generateCollisionShapes(recursive: true)
                foundModel = true
            }
        }
        if foundModel {
            Logger.ar.info("[V10] Generated collision shapes on child ModelEntities")
            return
        }

        // Last resort: create a manual box from visual bounds
        let bounds = entity.visualBounds(relativeTo: entity)
        guard bounds.extents.x > 0, bounds.extents.y > 0, bounds.extents.z > 0 else {
            Logger.ar.warning("[V10] Visual bounds are zero — cannot create collision shape")
            return
        }
        let box = ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)
        entity.components.set(CollisionComponent(shapes: [box]))
        Logger.ar.info("[V10] Created manual box collision shape from visual bounds")
    }

    // MARK: - Particle Effects

    /// Creates a particle burst effect for the spawn moment.
    private func createSpawnParticles(color: UIColor) -> Entity {
        let entity = Entity()

        let particleCount = 12
        for i in 0..<particleCount {
            let angle = Float(i) / Float(particleCount) * .pi * 2
            let particleMesh = MeshResource.generateBox(size: 0.005, cornerRadius: 0.001)
            let material = UnlitMaterial(color: color.withAlphaComponent(0.8))
            let particle = ModelEntity(mesh: particleMesh, materials: [material])

            particle.position = .zero
            entity.addChild(particle)

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

    // MARK: - Tap Handling (called from TapCatcherView)

    /// Receives a tap coordinate from the SwiftUI TapCatcherView overlay.
    /// This bypasses ARView's internal gesture system which blocks taps after
    /// collision shapes are generated.
    func handleTapAtPoint(_ location: CGPoint) {
        print("[DOODLAR] handleTapAtPoint at (\(location.x), \(location.y)). Alive: \(aliveCreatures.count)")

        // Strategy 1: RealityKit collision-based hit test
        if let hitEntity = arView.entity(at: location) {
            print("[DOODLAR] entity(at:) hit: \(hitEntity.name), id: \(hitEntity.id)")
            var target: Entity? = hitEntity
            while let entity = target {
                if aliveCreatures.contains(where: { $0 === entity }) {
                    print("[DOODLAR] Matched via collision hit!")
                    playTapReaction(on: entity)
                    return
                }
                target = entity.parent
            }
        } else {
            print("[DOODLAR] entity(at:) returned nil")
        }

        // Strategy 2: Projection fallback — works even if collision shapes are broken
        var closestCreature: Entity?
        var closestDistance: CGFloat = .greatestFiniteMagnitude

        for creature in aliveCreatures {
            let worldPos = creature.position(relativeTo: nil)
            guard let screenPos = arView.project(worldPos) else { continue }
            let dist = hypot(location.x - screenPos.x, location.y - screenPos.y)
            if dist < closestDistance {
                closestDistance = dist
                closestCreature = creature
            }
        }

        if closestDistance < 150, let creature = closestCreature {
            print("[DOODLAR] Fallback hit! Distance: \(closestDistance) pts")
            playTapReaction(on: creature)
        } else {
            print("[DOODLAR] No creature near tap (closest: \(closestDistance) pts)")
        }
    }

    /// Plays a bounce reaction when a creature is tapped.
    private func playTapReaction(on entity: Entity) {
        guard let parent = entity.parent else { return }

        print("[DOODLAR] TAP DETECTED on entity \(entity.id)")

        // Cancel any running animation so we can always restart
        entity.stopAllAnimations()

        // Play tap sound
        let isMuted = appState?.isMuted ?? false
        audioService.playTapSound(on: entity, isMuted: isMuted)

        // Use a fixed base Y of 0.05 (the spawn landing height) to prevent drift
        let currentScale = entity.scale
        let currentPos = entity.transform.translation
        let baseTranslation = SIMD3<Float>(currentPos.x, 0.05, currentPos.z)
        let apexTranslation = SIMD3<Float>(currentPos.x, 0.05 + 0.15, currentPos.z)

        let jumpDuration: TimeInterval = 0.30
        let fallDuration: TimeInterval = 0.30

        // 360° spin split across up + down
        let halfSpin = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let apexRotation = (entity.transform.rotation * halfSpin).normalized
        let landRotation = (apexRotation * halfSpin).normalized

        let apexTransform = Transform(
            scale: currentScale,
            rotation: apexRotation,
            translation: apexTranslation
        )

        let landTransform = Transform(
            scale: currentScale,
            rotation: landRotation,
            translation: baseTranslation
        )

        // Jump up
        entity.move(to: apexTransform, relativeTo: parent, duration: jumpDuration, timingFunction: .easeOut)

        // Fall down, then regenerate collision shapes
        Task {
            try? await Task.sleep(for: .milliseconds(Int(jumpDuration * 1000)))
            guard entity.parent != nil else { return }

            entity.move(to: landTransform, relativeTo: parent, duration: fallDuration, timingFunction: .easeIn)

            try? await Task.sleep(for: .milliseconds(Int(fallDuration * 1000) + 150))
            guard entity.parent != nil else { return }

            // Regenerate collision shapes so the next tap works
            self.ensureCollisionShapes(on: entity)
            print("[DOODLAR] Animation complete, collision shapes regenerated")
        }
    }

    // MARK: - Entity Creation

    /// [V10] Always loads a fresh USDZ model — no caching.
    /// Entity.clone(recursive:) does NOT reliably copy CollisionComponent,
    /// which causes tap detection to fail on cloned entities.
    private func loadFreshCreatureEntity(
        for type: CreatureType,
        tintColors: [CGColor]
    ) async -> Entity {
        // Try loading a real USDZ model
        if let usdzEntity = await loadUSDZModel(for: type, tintColors: tintColors) {
            return usdzEntity
        }

        // Fall back to colored box placeholder
        return createPlaceholderEntity(for: type, tintColors: tintColors)
    }

    /// Attempts to load a USDZ model for the given creature type.
    private func loadUSDZModel(for type: CreatureType, tintColors: [CGColor]) async -> Entity? {
        do {
            let modelFileName = "\(type.modelName).usdz"
            Logger.ar.info("[V10] Loading USDZ file: \(modelFileName) for type: \(type.rawValue)")
            let entity = try await ModelEntity.loadModel(named: modelFileName)
            Logger.ar.info("[V10] USDZ loaded successfully. Mesh bounds: \(entity.visualBounds(relativeTo: nil).extents)")

            // Set manual scale per creature type
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

            // Note: Collision shapes will be generated AFTER morph animation
            // by ensureCollisionShapes(), when the entity is at final scale in the scene.

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

        let labelEntity = createLabel(type.displayName)
        labelEntity.position.y = size / 2 + 0.025
        entity.addChild(labelEntity)

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
        case .apple:     return .systemRed
        case .banana:    return .systemYellow
        case .unknown:   return .systemIndigo
        }
    }
}
