import SwiftUI
import RealityKit

/// Wraps the RealityKit `ARView` for use in SwiftUI.
///
/// This is the primary camera feed view — RealityKit renders the camera passthrough
/// and AR content in a single view. The `ARViewModel` manages the session and delivers
/// frames to the Vision pipeline.
struct ARContainerView: UIViewRepresentable {
    let viewModel: ARViewModel

    func makeUIView(context: Context) -> ARView {
        viewModel.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // ARView configuration is managed by ARViewModel
    }
}

#Preview {
    ARContainerView(viewModel: ARViewModel())
        .ignoresSafeArea()
}
