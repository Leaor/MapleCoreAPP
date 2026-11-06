import SwiftUI
import MapleCoreKit

/// Small capsule label. Status is always colour + icon + text, never colour alone.
struct Pill: View {
    var text: String
    var tone: Tone = .neutral
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: Capsule())
        .fixedSize()
    }
}

/// StatusPill(status:) from the Components board.
struct StatusPill: View {
    var status: StopStatus
    var text: String? = nil

    var body: some View {
        Pill(text: text ?? status.label, tone: status.tone, symbol: status.symbol)
            .accessibilityLabel("Status: \(text ?? status.label)")
    }
}

/// Upload/sync state badge: Uploaded · Uploading 3 of 7 · Queued · Failed.
struct SyncBadge: View {
    var state: OutboxState
    var completed: Int = 0
    var total: Int = 1

    var body: some View {
        switch state {
        case .queued:
            Pill(text: "Queued", tone: .amber, symbol: "clock.arrow.circlepath")
        case .sending:
            Pill(text: total > 1 ? "\(completed) / \(total)" : "Sending", tone: .blue, symbol: "arrow.up.circle")
        case .sent:
            Pill(text: "Sent", tone: .green, symbol: "checkmark")
        case .failed:
            Pill(text: "Failed", tone: .red, symbol: "exclamationmark.circle")
        case .needsAttention:
            Pill(text: "Needs you", tone: .red, symbol: "exclamationmark.circle")
        }
    }
}

/// Crew letter badge used in rows: a rounded square with the crew letter.
struct CrewBadge: View {
    var letter: String
    var size: CGFloat = 36

    var body: some View {
        Text(letter)
            .font(.headline)
            .frame(width: size, height: size)
            .foregroundStyle(Palette.background)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Initials avatar.
struct Avatar: View {
    var initials: String
    var size: CGFloat = 40
    var tone: Tone = .neutral

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .foregroundStyle(tone == .neutral ? Palette.ink : tone.foreground)
            .background(tone.background, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Overlapping initials for crew members.
struct AvatarStack: View {
    var initials: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(initials.enumerated()), id: \.offset) { _, value in
                Avatar(initials: value, size: size)
                    .overlay(Circle().stroke(Palette.surface, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Numbered stop badge used in lists and map pins. The next stop is red and larger.
struct StopNumberBadge: View {
    var number: Int
    var status: StopStatus
    var isNext: Bool = false

    var body: some View {
        let size: CGFloat = isNext ? 40 : 32
        ZStack {
            Circle().fill(fill)
            if status == .done {
                Image(systemName: "checkmark").font(.footnote.weight(.bold))
            } else if status == .skipped {
                Text("–").font(.subheadline.weight(.bold))
            } else {
                Text("\(number)").font(.subheadline.weight(.bold)).numeric()
            }
        }
        .foregroundStyle(foreground)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        if isNext { return Palette.red }
        switch status {
        case .done: return Palette.green
        case .inProgress, .enRoute: return Palette.blue
        case .delayed: return Palette.amber
        default: return Palette.surface2
        }
    }

    private var foreground: Color {
        if isNext { return .white }
        switch status {
        case .pending, .skipped: return Palette.ink
        default: return .white
        }
    }
}
