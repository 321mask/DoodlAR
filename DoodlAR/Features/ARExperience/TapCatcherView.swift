import SwiftUI
import UIKit

/// A transparent UIKit overlay that captures tap gestures and reports their screen coordinates.
///
/// This exists because RealityKit's ARView internally hijacks UITapGestureRecognizers
/// after `generateCollisionShapes()` is called, preventing subsequent taps from reaching
/// custom gesture recognizers attached to the ARView. By catching taps on a separate UIView
/// layer managed by SwiftUI (positioned above the ARView in the ZStack), we fully bypass
/// RealityKit's internal gesture system.
struct TapCatcherView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughTapView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let location = recognizer.location(in: recognizer.view)
            onTap(location)
        }
    }
}

/// A UIView subclass that only responds to taps and passes all other touches through.
/// This lets SwiftUI buttons (top bar, bottom bar) receive their touches normally.
private class PassthroughTapView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Always return true — we want to catch all taps in our area
        return true
    }
}
