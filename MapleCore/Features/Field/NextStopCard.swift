import SwiftUI
import MapleCoreKit

/// "Next stop · 6 of 9" hero card on Field Today. Red 2pt ring; the header opens the stop,
/// the buttons hand off to Apple Maps or start the visit.
struct NextStopCard: View {
    var route: Route
    var stop: RouteStop
    var property: Property?
    var now: Date
    var onNavigate: () -> Void
    var onArrive: () -> Void

    private var number: Int { (route.index(of: stop.id) ?? 0) + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m + 2) {
            NavigationLink(value: AppDestination.fieldStop(route.id, stop.id)) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens stop details")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s + 2) { buttons }
                VStack(spacing: Space.s + 2) { buttons }
            }
        }
        .padding(Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.red, lineWidth: 2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.s) {
                Text("Next stop · \(number) of \(route.stops.count)")
                    .fieldCaption(Palette.redText)
                Spacer(minLength: Space.s)
                if stop.status == .enRoute {
                    Pill(text: "En route", tone: .blue, symbol: StopStatus.enRoute.symbol)
                } else if let eta = FieldText.eta(stop, now: now) {
                    Pill(text: eta, tone: .neutral, symbol: "clock")
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(property?.name ?? "Stop \(number)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text([property?.address, stop.serviceName].compactMap { $0 }.joined(separator: " · "))
                        .font(.body)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onNavigate) {
            Label("Navigate", systemImage: "location.north.line.fill")
        }
        .buttonStyle(.mc(.secondary, glove: true))
        .disabled(property == nil)
        .accessibilityHint("Opens driving directions in Apple Maps")

        Button("I've Arrived", action: onArrive)
            .buttonStyle(.mc(.primary, glove: true))
            .layoutPriority(1)
    }
}

/// Shown on Today instead of the next stop while a visit is running.
struct ActiveVisitCard: View {
    var session: VisitSession
    var onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text("Visit in progress").fieldCaption(Palette.blue)
                Spacer(minLength: Space.s)
                Pill(text: session.state.label, tone: tone, symbol: symbol)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.propertyName)
                    .font(.title2.weight(.bold))
                Text("Stop \(session.stopNumber) of \(session.stopCount) · \(session.serviceName)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            VisitElapsedText(session: session)
                .foregroundStyle(session.state == .paused ? Palette.amber : Palette.ink)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
            Button("Return to Visit", action: onReturn)
                .buttonStyle(.mc(.primary, glove: true))
        }
        .padding(Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.blue, lineWidth: 2)
        }
    }

    private var tone: Tone {
        switch session.state {
        case .paused: .amber
        case .completed, .reviewed: .green
        default: .blue
        }
    }

    private var symbol: String {
        switch session.state {
        case .paused: "pause.fill"
        case .working: "timer"
        default: "mappin.circle.fill"
        }
    }

    private var caption: String {
        switch session.state {
        case .arrived: "Take \(VisitSession.requiredBeforePhotos) before photos to start the work timer."
        case .paused: "Work time is frozen while paused."
        case .working: "Estimate \(Fmt.duration(minutes: session.estimateMinutes)) · keeps running if the app closes."
        default: "Estimate \(Fmt.duration(minutes: session.estimateMinutes))."
        }
    }
}
