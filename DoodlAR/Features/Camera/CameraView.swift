import SwiftUI
import SwiftData
import simd
import os

/// The main camera scanning view with AR passthrough and paper detection overlay.
///
/// Shows the RealityKit AR camera feed with a translucent Liquid Glass bottom bar
/// for guidance. Manages the full flow: scanning → classifying → spawning → alive.
struct CameraView: View {
    let arViewModel: ARViewModel
    @Bindable var cameraViewModel: CameraViewModel
    @Bindable var collectionViewModel: CollectionViewModel
    @Bindable var appState: AppState

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            // AR camera feed — always full screen
            ARContainerView(viewModel: arViewModel)
                .ignoresSafeArea()

            // Detection overlay
            if cameraViewModel.isPaperDetected, let corners = cameraViewModel.detectedCorners {
                PaperOverlayView(corners: corners)
            }

            // UI chrome
            VStack {
                topBar
                Spacer()
                debugPreview
                bottomBar
            }
        }
        .task {
            collectionViewModel.configure(with: modelContext)
            collectionViewModel.loadCollection()
            arViewModel.startSession()
            cameraViewModel.bind(to: arViewModel)
            await cameraViewModel.loadModel()
        }
        .sheet(isPresented: $appState.isCollectionPresented) {
            CollectionView(viewModel: collectionViewModel, arViewModel: arViewModel)
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraViewModel.isPaperDetected)
        .sensoryFeedback(.success, trigger: appState.hapticClassification)
        .sensoryFeedback(.impact(weight: .heavy), trigger: appState.hapticSpawn)
        .sensoryFeedback(.error, trigger: appState.hapticError)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            if let trackingMessage = arViewModel.trackingMessage {
                Text(trackingMessage)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
            }

            Spacer()

            // Creature count badge
            if !collectionViewModel.creatures.isEmpty {
                Button {
                    appState.isCollectionPresented = true
                } label: {
                    Label("\(collectionViewModel.creatures.count)", systemImage: "square.grid.2x2.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thickMaterial)
                        .clipShape(Capsule())
                }
            }

            // Debug toggle
            Button {
                appState.isDebugMode.toggle()
            } label: {
                Image(systemName: appState.isDebugMode ? "ladybug.fill" : "ladybug")
                    .font(.title3)
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    // MARK: - Debug Preview

    @ViewBuilder
    private var debugPreview: some View {
        if appState.isDebugMode, let sketch = cameraViewModel.extractedSketchImage {
            VStack(spacing: 4) {
                Image(decorative: sketch, scale: 1.0)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .border(Color.white.opacity(0.6), width: 1)
                    .shadow(radius: 4)

                if let result = cameraViewModel.lastDetectionResult {
                    Text("\(result.classificationResult.creatureType.displayName) — \(Int(result.classificationResult.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        switch appState.spawnState {
        case .idle, .scanning:
            scanningBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .detected:
            detectedBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .classifying, .triggerSpawn:
            classifyingBar
                .transition(.opacity)

        case .morphing:
            EmptyView()

        case .alive:
            aliveBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .failed(let error):
            errorBar(error)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var scanningBar: some View {
        HStack(spacing: 12) {
            Image(systemName: cameraViewModel.isPaperDetected ? "checkmark.circle.fill" : "viewfinder")
                .foregroundStyle(cameraViewModel.isPaperDetected ? .green : .primary)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))

            Text(cameraViewModel.guidanceMessage)
                .font(.subheadline)

            Spacer()

            Button {
                appState.isCollectionPresented = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.title3)
            }
        }
        .liquidGlassBar()
        .onChange(of: cameraViewModel.lastDetectionResult != nil) { _, hasResult in
            if hasResult {
                withAnimation(.spring(duration: 0.3)) {
                    appState.spawnState = .detected(
                        paperPosition: simd_float4x4(translation: .zero)
                    )
                }
            }
        }
    }

    private var classifyingBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.primary)

            Text("Bringing your creature to life...")
                .font(.subheadline)
        }
        .liquidGlassBar()
    }

    private var detectedBar: some View {
        HStack(spacing: 12) {
            if let result = cameraViewModel.lastDetectionResult {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.classificationResult.creatureType.displayName) Found!")
                        .font(.headline)
                    Text("\(Int(result.classificationResult.confidence * 100))% match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Collect & Spawn") {
                withAnimation(.spring(duration: 0.3)) {
                    addToCollection()
                    appState.spawnState = .triggerSpawn
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("Discard") {
                Task {
                    withAnimation(.spring(duration: 0.3)) {
                        appState.spawnState = .idle
                    }
                    await cameraViewModel.resetDetection()
                }
            }
            .buttonStyle(.bordered)
        }
        .liquidGlassBar()
    }

    private var aliveBar: some View {
        HStack(spacing: 12) {
            if let result = cameraViewModel.lastDetectionResult {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.classificationResult.creatureType.displayName) is Alive!")
                        .font(.headline)
                    Text("Auto-resetting scanner...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .liquidGlassBar()
    }

    private func errorBar(_ error: DoodlARError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(error.localizedDescription)
                .font(.subheadline)
                .lineLimit(2)

            Spacer()

            Button("Retry") {
                Task {
                    withAnimation(.spring(duration: 0.3)) {
                        appState.spawnState = .idle
                    }
                    await cameraViewModel.resetDetection()
                }
            }
            .buttonStyle(.bordered)
        }
        .liquidGlassBar()
    }

    // MARK: - Actions

    private func addToCollection() {
        guard let result = cameraViewModel.lastDetectionResult else { return }
        let creature = Creature(
            type: result.classificationResult.creatureType,
            sketchImage: result.normalizedSketchImage,
            features: result.sketchFeatures,
            confidence: result.classificationResult.confidence
        )
        collectionViewModel.addCreature(creature)
        appState.discoveredCreatures.append(creature)
        Logger.ui.info("Added \(creature.type.displayName) to collection")
    }
}

// MARK: - Liquid Glass Bar Modifier

extension View {
    /// Applies the standard Liquid Glass bar styling used throughout the app.
    func liquidGlassBar() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }
}

// MARK: - Paper Overlay

/// Draws a pulsing highlight over the detected paper rectangle.
struct PaperOverlayView: View {
    let corners: DetectedRectangle
    @State private var isPulsing = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Path { path in
                let tl = CGPoint(x: corners.topLeft.x * size.width, y: (1 - corners.topLeft.y) * size.height)
                let tr = CGPoint(x: corners.topRight.x * size.width, y: (1 - corners.topRight.y) * size.height)
                let br = CGPoint(x: corners.bottomRight.x * size.width, y: (1 - corners.bottomRight.y) * size.height)
                let bl = CGPoint(x: corners.bottomLeft.x * size.width, y: (1 - corners.bottomLeft.y) * size.height)

                path.move(to: tl)
                path.addLine(to: tr)
                path.addLine(to: br)
                path.addLine(to: bl)
                path.closeSubpath()
            }
            .stroke(
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .opacity(isPulsing ? 0.4 : 1.0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    CameraView(
        arViewModel: ARViewModel(),
        cameraViewModel: CameraViewModel(),
        collectionViewModel: CollectionViewModel(),
        appState: AppState()
    )
}
