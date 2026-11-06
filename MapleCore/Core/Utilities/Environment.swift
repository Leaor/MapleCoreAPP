import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Glove Mode raises field controls to 60pt and favours tap over swipe.
    @Entry var gloveMode: Bool = false
    /// True inside Admin "Preview Field Mode". Writes are no-ops in the store; show the preview banner.
    @Entry var isRolePreview: Bool = false
}

/// Imperative haptics for moments that aren't tied to a view value change.
/// Prefer `.sensoryFeedback(_:trigger:)` in views; use this from async actions.
@MainActor
enum Haptics {
    static var isEnabled = true

    static func success() { notify(.success) }
    static func error() { notify(.error) }
    static func warning() { notify(.warning) }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// Spring used for state changes. Collapses to no animation with Reduce Motion.
extension Animation {
    static let mcSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

struct MotionAwareAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation` that respects Reduce Motion.
    func motionAnimation<V: Hashable>(_ animation: Animation = .mcSpring, value: V) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: AnyHashable(value)))
    }
}

/// Runs `withAnimation` unless Reduce Motion is on.
@MainActor
func withMotion<Result>(_ animation: Animation = .mcSpring, _ body: () throws -> Result) rethrows -> Result {
    if UIAccessibility.isReduceMotionEnabled {
        return try body()
    }
    return try withAnimation(animation, body)
}
