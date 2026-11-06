import SwiftUI
import MapleCoreKit

/// Next week's availability. The store has no availability mutation yet, so the request is sent to the
/// manager as a direct message — honest and functional until a real approval flow exists.
struct AvailabilityView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var days: [Bool] = Array(repeating: true, count: 7)
    @State private var lastSent: [Bool]?
    @State private var didLoad = false

    private var isPreview: Bool { isRolePreview || store.isReadOnly }
    private var managerName: String { store.fieldManager?.firstName ?? "your manager" }

    /// Monday of next week.
    private var weekStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        var offset = (9 - weekday) % 7
        if offset == 0 { offset = 7 }
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func date(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
    }

    var body: some View {
        Form {
            Section {
                ForEach(Weekday.allCases, id: \.self) { day in
                    let index = day.rawValue - 1
                    Toggle(isOn: $days[index]) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.label)
                            Text(Fmt.shortDate(date(for: index)))
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                        }
                    }
                    .tint(Palette.green)
                    .frame(minHeight: Hit.min)
                    .disabled(isPreview)
                }
            } header: {
                Text("Week of \(Fmt.shortDate(weekStart))")
            } footer: {
                Text(isPreview
                     ? "Preview only — availability belongs to the crew member."
                     : "Turn off the days you can't work. Your request goes to \(managerName) as a message; routes are planned once it's approved.")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Availability")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: days)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Send to \(store.fieldManager?.firstName ?? "Manager")") { send() }
                    .buttonStyle(.mc(.primary, glove: true))
                    .disabled(lastSent == days)
            }
        }
        .onAppear(perform: load)
    }

    private var offDays: [String] {
        days.enumerated().compactMap { index, isOn in
            isOn ? nil : Weekday(rawValue: index + 1).map { String($0.label.prefix(3)) }
        }
    }

    private var summary: String {
        if offDays.isEmpty { return "Available all week" }
        if offDays.count == 7 { return "Off all week" }
        return "Off " + offDays.joined(separator: ", ")
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let availability = store.fieldMember?.availability, availability.count == 7 {
            days = availability
        }
    }

    private func send() {
        if isPreview {
            toasts.show("Preview only — nothing is sent", symbol: "eye", tone: .blue)
            return
        }
        guard let threadID = store.fieldManagerThreadID() else {
            toasts.show("Couldn't reach \(managerName) — try again", symbol: "exclamationmark.circle", tone: .amber)
            return
        }
        let request = offDays.isEmpty ? "available all week" : "off " + offDays.joined(separator: ", ")
        store.send("Availability request for the week of \(Fmt.shortDate(weekStart)): \(request)", to: threadID, visibility: .internal)
        lastSent = days
        Haptics.success()
        toasts.show(store.isOnline ? "Sent to \(managerName)" : "Saved on this iPhone · sends automatically")
    }
}

#Preview("Availability") {
    NavigationStack {
        AvailabilityView()
    }
    .previewEnvironment(role: .field)
}
