import SwiftUI
import MapleCoreKit

/// Five-segment progress for the visit: Arrive · Before · Work · After · Submit.
/// Finished steps are green, the current step red, upcoming steps neutral.
struct VisitStepIndicator: View {
    static let steps = ["Arrive", "Before", "Work", "After", "Submit"]

    /// Zero-based index of the current step.
    var current: Int

    private var clamped: Int { min(max(current, 0), Self.steps.count - 1) }

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, title in
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(barColor(index))
                        .frame(height: 4)
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(textColor(index))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .motionAnimation(value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(clamped + 1) of \(Self.steps.count), \(Self.steps[clamped])")
    }

    private func barColor(_ index: Int) -> Color {
        if index < clamped { return Palette.green }
        if index == clamped { return Palette.red }
        return Palette.surface2
    }

    private func textColor(_ index: Int) -> Color {
        if index < clamped { return Palette.green }
        if index == clamped { return Palette.redText }
        return Palette.ink3
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(0..<5, id: \.self) { VisitStepIndicator(current: $0) }
    }
    .padding()
    .screenBackground()
}
