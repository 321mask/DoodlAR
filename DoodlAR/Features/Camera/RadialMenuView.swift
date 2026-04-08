import SwiftUI

/// A floating radial menu that appears above the dog in screen space.
///
/// Shows available actions (tent, ball) based on which objects are currently
/// alive in the AR scene. Items fan out in an arc with a spring animation.
struct RadialMenuView: View {
    let position: CGPoint
    let availableActions: [DogAction]
    let onSelect: (DogAction) -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        ZStack {
            // Full-screen tap-to-dismiss background
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // Menu items arranged in an arc above the position
            ZStack {
                ForEach(Array(availableActions.enumerated()), id: \.offset) { index, action in
                    let angle = angleForItem(index: index, total: availableActions.count)
                    let offset = offsetForAngle(angle, radius: 70)

                    Button {
                        onSelect(action)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: iconName(for: action))
                                .font(.title2)
                            Text(label(for: action))
                                .font(.caption2)
                        }
                        .frame(width: 60, height: 60)
                        .background(.thickMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                    }
                    .offset(
                        x: isExpanded ? offset.x : 0,
                        y: isExpanded ? offset.y : 0
                    )
                    .scaleEffect(isExpanded ? 1.0 : 0.3)
                    .opacity(isExpanded ? 1.0 : 0.0)
                }
            }
            .position(x: position.x, y: position.y - 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = true
            }
        }
    }

    // MARK: - Layout

    /// Distributes items evenly in an upward-facing arc.
    private func angleForItem(index: Int, total: Int) -> Double {
        let startAngle: Double = -150
        let endAngle: Double = -30
        if total == 1 { return -90 } // Straight up for single item
        let step = (endAngle - startAngle) / Double(total - 1)
        return startAngle + step * Double(index)
    }

    private func offsetForAngle(_ angleDegrees: Double, radius: CGFloat) -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(x: cos(rad) * radius, y: sin(rad) * radius)
    }

    // MARK: - Content

    private func iconName(for action: DogAction) -> String {
        switch action {
        case .goToTent:  return "tent.fill"
        case .chaseBall: return "baseball.fill"
        }
    }

    private func label(for action: DogAction) -> String {
        switch action {
        case .goToTent:  return "Tent"
        case .chaseBall: return "Fetch"
        }
    }
}
