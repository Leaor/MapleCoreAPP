import SwiftUI

/// MCButton styles from the Components board: .primary · .ink · .secondary · .destructiveOutline.
/// Buttons fill the available width. Height is 50pt, or 60pt for `.glove` and in Glove Mode.
struct MCButtonStyle: ButtonStyle {
    enum Kind { case primary, ink, secondary, destructiveOutline, tinted }

    var kind: Kind
    var glove: Bool = false
    var compact: Bool = false

    @Environment(\.gloveMode) private var gloveMode
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = compact ? Hit.min : ((glove || gloveMode) ? Hit.glove : 50)
        configuration.label
            .font((glove || gloveMode) && !compact ? .title3.weight(.semibold) : .headline)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, Space.l)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? Radius.control + 2 : Radius.card, style: .continuous))
            .overlay {
                if kind == .destructiveOutline {
                    RoundedRectangle(cornerRadius: compact ? Radius.control + 2 : Radius.card, style: .continuous)
                        .strokeBorder(Palette.redText.opacity(0.6), lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .ink: Palette.background
        case .secondary: Palette.ink
        case .destructiveOutline: Palette.redText
        case .tinted: Palette.redText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.red
        case .ink: Palette.ink
        case .secondary: Palette.surface2
        case .destructiveOutline: .clear
        case .tinted: Palette.redSoft
        }
    }
}

extension ButtonStyle where Self == MCButtonStyle {
    static func mc(_ kind: MCButtonStyle.Kind, glove: Bool = false, compact: Bool = false) -> MCButtonStyle {
        MCButtonStyle(kind: kind, glove: glove, compact: compact)
    }
}

/// Round 44pt icon button on surface.secondary, used in headers over maps and cameras.
struct IconCircleButtonStyle: ButtonStyle {
    var size: CGFloat = Hit.min
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(width: size, height: size)
            .foregroundStyle(onDark ? Color.white : Palette.ink)
            .background(onDark ? AnyShapeStyle(.black.opacity(0.45)) : AnyShapeStyle(Palette.surface2), in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == IconCircleButtonStyle {
    static var iconCircle: IconCircleButtonStyle { IconCircleButtonStyle() }
    static var iconCircleOnDark: IconCircleButtonStyle { IconCircleButtonStyle(onDark: true) }
}

/// The bottom action bar used by field screens: primary actions sit in thumb reach above the home indicator.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Space.s) { content }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}
