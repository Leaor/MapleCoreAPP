import SwiftUI
import UIKit
import MapleCoreKit

/// Empty state from the "Empty States" board: symbol, title, one sentence and up to two actions.
struct EmptyStateView<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Space.l) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Palette.ink3)
                .frame(width: 72, height: 72)
                .background(Palette.surface2, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Space.s) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Space.s) { actions }
                .padding(.top, Space.xs)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xxxl)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Error state: says what happened, that nothing was lost, and offers one recovery action.
struct ErrorStateView: View {
    var title: String
    var message: String
    var reference: String? = nil
    var retryTitle = "Try Again"
    var retry: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 32))
                .foregroundStyle(Palette.amber)
                .frame(width: 72, height: 72)
                .background(Palette.amberSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Space.s) {
                Text(title).font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
            Button(retryTitle, action: retry)
                .buttonStyle(.mc(.ink))
                .frame(maxWidth: 260)
            if let reference {
                Text("Reference \(reference) · copy to share with support")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .textSelection(.enabled)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// Skeleton block for first loads. Pairs with `.redacted(reason: .placeholder)` on real rows.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(height: CGFloat = 16, width: CGFloat? = nil) {
        self.height = height
        self.width = width
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Palette.surface2)
            .frame(width: width, height: height)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// Global offline banner: "Offline — work is saved on this iPhone".
struct OfflineBanner: View {
    var pendingCount: Int

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "wifi.slash").font(.footnote.weight(.bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("Offline — work is saved on this iPhone")
                    .font(.footnote.weight(.semibold))
                if pendingCount > 0 {
                    Text("\(Fmt.plural(pendingCount, "item")) waiting to send · sends automatically")
                        .font(.caption)
                        .opacity(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.amber)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(Palette.amberSoft, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Timestamp provenance. Server time is authoritative; device time is labelled "iPhone clock".
struct TimeStampLabel: View {
    enum Source { case server, device, imported }

    var source: Source
    var date: Date?
    var withSeconds = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(caption).font(.caption).foregroundStyle(Palette.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch source {
        case .server: "checkmark.shield"
        case .device: "iphone"
        case .imported: "photo.on.rectangle"
        }
    }

    private var tone: Tone {
        switch source {
        case .server: date == nil ? .amber : .green
        case .device: .neutral
        case .imported: .amber
        }
    }

    private var title: String {
        guard let date else { return source == .server ? "Pending upload" : "—" }
        let time = withSeconds ? Fmt.timeWithSeconds(date) : Fmt.time(date)
        switch source {
        case .server: return "Received \(time)"
        case .device: return "Captured \(time)"
        case .imported: return "Imported · \(time)"
        }
    }

    private var caption: String {
        switch source {
        case .server: date == nil ? "Server time is added when the upload lands" : "Server-recorded when the upload arrived"
        case .device: "iPhone clock — reported by this device"
        case .imported: "From the photo library · can't be confirmed"
        }
    }
}

/// Lightweight confirmation toast shown at the top of the screen.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var symbol: String
        var tone: Tone
    }

    var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, symbol: String = "checkmark.circle.fill", tone: Tone = .green) {
        current = Toast(text: text, symbol: symbol, tone: tone)
        UIAccessibility.post(notification: .announcement, argument: text)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toasts.current {
                HStack(spacing: Space.s) {
                    Image(systemName: toast.symbol).foregroundStyle(toast.tone.foreground)
                    Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .background(.regularMaterial, in: Capsule())
                .floatingShadow()
                .padding(.top, Space.s)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityHidden(true)
            }
        }
        .motionAnimation(value: toasts.current)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
