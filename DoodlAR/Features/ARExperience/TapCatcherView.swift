import SwiftUI
import UIKit

/// A transparent UIKit overlay that captures all gesture recognizers and reports
/// their coordinates back via closures.
///
/// This exists because RealityKit's ARView internally hijacks gesture recognizers
/// after `generateCollisionShapes()` is called. By handling all gestures on a
/// separate UIView layer above the ARView, we fully bypass RealityKit's internal
/// gesture system while supporting tap, long-press, and pan interactions.
struct TapCatcherView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onLongPress: (UIGestureRecognizer.State, CGPoint) -> Void
    let onPan: (UIGestureRecognizer.State, CGPoint, CGPoint) -> Void  // state, location, velocity

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )

        // Tap should fail if long press is recognized
        tap.require(toFail: longPress)

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onPan = onPan
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress, onPan: onPan)
    }

    class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void
        var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Void
        var onPan: (UIGestureRecognizer.State, CGPoint, CGPoint) -> Void

        init(
            onTap: @escaping (CGPoint) -> Void,
            onLongPress: @escaping (UIGestureRecognizer.State, CGPoint) -> Void,
            onPan: @escaping (UIGestureRecognizer.State, CGPoint, CGPoint) -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onPan = onPan
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let location = recognizer.location(in: recognizer.view)
            onTap(location)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            onLongPress(recognizer.state, location)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            onPan(recognizer.state, location, CGPoint(x: velocity.x, y: velocity.y))
        }
    }
}
