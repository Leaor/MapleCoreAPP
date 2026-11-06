import SwiftUI

// Type uses SF Pro through Dynamic Type text styles only, so every screen scales to AX5.

extension View {
    /// Uppercase section caption: 13pt semibold, tracked, tertiary ink.
    func captionStyle() -> some View {
        font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.3)
            .foregroundStyle(Palette.ink3)
    }

    /// Tabular numbers for figures that update or align in columns.
    func numeric() -> some View {
        monospacedDigit()
    }

    /// The standard grouped screen background.
    func screenBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }

    /// Flat card on the grouped background. Cards never get a shadow.
    func cardStyle(padding: CGFloat = Space.l) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Shadow reserved for things floating over a map or camera (elevation e2).
    func floatingShadow() -> some View {
        shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }
}

/// Large timer face: 72pt semibold monospaced, scaled with Dynamic Type.
struct TimerText: View {
    let text: String
    var baseSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        Text(text)
            .font(.system(size: baseSize * min(scale, 1.6), weight: .semibold))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}
