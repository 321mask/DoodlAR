import RealityKit
import os

/// Manages spatial audio playback for creatures in the AR scene.
///
/// Handles loading audio resources, attaching spatial audio components to entities,
/// and controlling playback of spawn sounds, ambient loops, and tap reactions.
/// All audio is spatial by default — attached to creature entities so it sounds
/// like it comes from the creature's position in 3D space.
@MainActor
final class SpatialAudioService {

    /// Active ambient loop controllers keyed by entity ID.
    private var ambientControllers: [ObjectIdentifier: AudioPlaybackController] = [:]

    /// Cached audio resources to avoid reloading.
    private var resourceCache: [String: AudioFileResource] = [:]

    // MARK: - Playback

    /// Plays the spawn sound on the creature entity during the morph phase.
    func playSpawnSound(on entity: Entity, isMuted: Bool) {
        guard !isMuted else { return }
        guard let resource = loadResource(named: "spawn.wav") else { return }
        entity.playAudio(resource)
    }

    /// Starts the ambient loop on a creature entity after it becomes alive.
    func startAmbientLoop(on entity: Entity, creatureType: CreatureType, isMuted: Bool) {
        guard !isMuted else { return }
        let fileName = "ambient_\(creatureType.rawValue).wav"
        let config = AudioFileResource.Configuration(
            loadingStrategy: .preload,
            shouldLoop: true
        )
        guard let resource = loadResource(named: fileName, configuration: config) else { return }

        configureSpatialAudio(on: entity)
        let controller = entity.playAudio(resource)
        ambientControllers[ObjectIdentifier(entity)] = controller
    }

    /// Plays the tap reaction sound on a creature entity.
    func playTapSound(on entity: Entity, isMuted: Bool) {
        guard !isMuted else { return }
        guard let resource = loadResource(named: "tap.wav") else { return }
        entity.playAudio(resource)
    }

    // MARK: - Lifecycle

    /// Stops all audio for a specific creature entity.
    func stopAudio(for entity: Entity) {
        let key = ObjectIdentifier(entity)
        ambientControllers[key]?.stop()
        ambientControllers.removeValue(forKey: key)
    }

    /// Stops all active audio playback (used on scene clear).
    func stopAllAudio() {
        for (_, controller) in ambientControllers {
            controller.stop()
        }
        ambientControllers.removeAll()
        Logger.audio.info("All spatial audio stopped")
    }

    // MARK: - Private

    /// Configures spatial audio component on an entity for 3D sound emission.
    private func configureSpatialAudio(on entity: Entity) {
        guard entity.components[SpatialAudioComponent.self] == nil else { return }
        let spatialAudio = SpatialAudioComponent()
        entity.components.set(spatialAudio)
    }

    /// Loads an audio file resource from the bundle, returning nil if not found.
    private func loadResource(
        named name: String,
        configuration: AudioFileResource.Configuration = .init()
    ) -> AudioFileResource? {
        if let cached = resourceCache[name] {
            return cached
        }

        do {
            let resource = try AudioFileResource.load(
                named: name,
                in: nil,
                configuration: configuration
            )
            resourceCache[name] = resource
            Logger.audio.debug("Loaded audio resource: \(name)")
            return resource
        } catch {
            Logger.audio.warning("Audio file '\(name)' not found, skipping: \(error.localizedDescription)")
            return nil
        }
    }
}
