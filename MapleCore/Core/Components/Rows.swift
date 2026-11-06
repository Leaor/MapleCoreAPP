import SwiftUI
import MapleCoreKit

/// Section caption with an optional trailing action ("See all", "Edit").
struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .captionStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            trailing
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.redText)
        }
        .padding(.horizontal, Space.xs)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Label/value row for grouped cards ("Service frequency  Weekly ›").
struct KeyValueRow: View {
    var label: String
    var value: String
    var valueTone: Tone? = nil
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: Space.s)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(valueTone?.foreground ?? Palette.ink)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .font(.body)
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
    }
}

/// A stack of rows inside one card, separated by inset hairlines.
struct CardList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var data: Data
    var inset: CGFloat = 0
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                row(element)
                if index < data.count - 1 {
                    Divider().padding(.leading, inset)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Ordered stop row: number badge, name, detail, status pill. Used by route lists and planners.
struct StopRow: View {
    var number: Int
    var title: String
    var detail: String
    var status: StopStatus
    var isNext: Bool = false
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: Space.m) {
            StopNumberBadge(number: number, status: status, isNext: isNext)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isNext ? .headline : .body.weight(.semibold))
                    .foregroundStyle(status == .skipped ? Palette.ink3 : Palette.ink)
                    .strikethrough(status == .skipped, color: Palette.ink3)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(status == .delayed ? Palette.amber : Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if let trailing {
                Pill(text: trailing, tone: trailing == "High" ? .red : .neutral)
            }
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(number), \(title), \(isNext ? "next, " : "")\(detail)")
    }
}

/// Large number tile ("38 Scheduled").
struct StatTile: View {
    var value: String
    var label: String
    var tone: Tone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .numeric()
                .foregroundStyle(tone?.foreground ?? Palette.ink)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal chips filter ("All 64 · Commercial · Residential").
struct FilterChips<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String
    var count: (Option) -> Int? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selection
                    Button {
                        selection = option
                    } label: {
                        HStack(spacing: 5) {
                            Text(label(option))
                            if let c = count(option) {
                                Text("\(c)").numeric().opacity(0.75)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(isOn ? Palette.background : Palette.ink)
                        .background(isOn ? Palette.ink : Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: isOn ? 0 : 1))
                        .frame(minHeight: Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.l)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Segmented progress bar for a route: done (green), in progress (blue), delayed (amber), remaining.
struct RouteProgressBar: View {
    var stops: [RouteStop]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(stops) { stop in
                Capsule()
                    .fill(color(for: stop.status))
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(stops.filter { $0.status == .done }.count) of \(stops.count) stops completed")
    }

    private func color(for status: StopStatus) -> Color {
        switch status {
        case .done: Palette.green
        case .inProgress, .enRoute: Palette.blue
        case .delayed: Palette.amber
        case .skipped: Palette.ink3.opacity(0.4)
        default: Palette.surface2
        }
    }
}

/// Inline banner card: icon + text on a soft tone background.
struct NoticeCard: View {
    var symbol: String
    var text: String
    var tone: Tone = .amber

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m + 2)
        .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
