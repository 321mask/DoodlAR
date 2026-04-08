import SwiftUI
import SwiftData
import os

/// DoodlAR — "Draw a creature. Watch it come alive."
///
/// An AR game where the player draws a creature on paper, points their iPhone camera
/// at it, and a 3D version comes alive in augmented reality.
@main
struct DoodlARApp: App {
    @State private var appState = AppState()
    @State private var arViewModel = ARViewModel()
    @State private var cameraViewModel = CameraViewModel()
    @State private var collectionViewModel = CollectionViewModel()

    var body: some Scene {
        WindowGroup {
            CameraView(
                arViewModel: arViewModel,
                cameraViewModel: cameraViewModel,
                collectionViewModel: collectionViewModel,
                appState: appState
            )
            .environment(appState)
            .onChange(of: appState.spawnState.shouldSpawn) { _, shouldSpawn in
                if shouldSpawn {
                    Task { await handleSpawn() }
                }
            }
        }
        .modelContainer(for: PersistedCreature.self)
    }

    /// Handles the creature spawn sequence when a detection is confirmed.
    @MainActor
    private func handleSpawn() async {
        guard let result = cameraViewModel.lastDetectionResult else { return }

        cameraViewModel.stopScanning()
        appState.hapticClassification.toggle()
        appState.spawnState = .classifying

        // Brief "thinking" pause
        try? await Task.sleep(for: .milliseconds(800))

        // Raycast to find world position
        guard let worldTransform = arViewModel.raycastFromCenter() else {
            appState.spawnState = .failed(.paperNotFound)
            appState.hapticError.toggle()
            return
        }

        appState.spawnState = .morphing

        do {
            _ = try await arViewModel.spawnCreature(
                type: result.classificationResult.creatureType,
                at: worldTransform,
                sketchImage: result.normalizedSketchImage,
                features: result.sketchFeatures
            )

            appState.hapticSpawn.toggle()
            appState.aliveCreatureType = result.classificationResult.creatureType
            appState.isDogWalking = false
            appState.spawnState = .alive(creatureID: UUID())
            Logger.ar.info("Spawn complete, creature alive")
            
            // [MODIFICA] Auto-reset to scan again after 2.5 seconds!
            try? await Task.sleep(for: .seconds(2.5))
            appState.spawnState = .idle
            await cameraViewModel.resetDetection()
            
        } catch {
            appState.hapticError.toggle()
            appState.spawnState = .failed(
                .entityLoadFailed(
                    modelName: result.classificationResult.creatureType.modelName,
                    underlying: error.localizedDescription
                )
            )
        }
    }
}

// MARK: - SpawnState Helpers

extension SpawnState {
    /// Whether the state indicates a spawn should begin.
    var shouldSpawn: Bool {
        if case .triggerSpawn = self { return true }
        return false
    }
}
