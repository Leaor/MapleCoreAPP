import Foundation
import MapKit
import Observation

/// A chosen address with a map coordinate.
struct PropertyResolvedAddress: Equatable {
    var street: String
    var city: String
    var latitude: Double
    var longitude: Double
    /// False when the address was typed manually and couldn't be placed; the pin is approximate.
    var isLocated: Bool

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Wraps `MKLocalSearchCompleter` for address suggestions while typing.
/// UI-facing methods are main-actor; the completer calls its delegate on the main thread.
@Observable
final class AddressSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String
    }

    /// Default region: the Greater Toronto Area, where MapleCore operates.
    static let serviceCenter = CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.4500)

    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false
    private(set) var lastError: String?

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(center: Self.serviceCenter, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    @MainActor
    func update(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
        guard q.count >= 3 else {
            completer.cancel()
            completions = []
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = q
    }

    @MainActor
    func clear() {
        completer.cancel()
        completions = []
        suggestions = []
        isSearching = false
    }

    /// Resolves a suggestion to a coordinate with `MKLocalSearch`.
    @MainActor
    func resolve(_ suggestion: Suggestion) async -> PropertyResolvedAddress? {
        guard completions.indices.contains(suggestion.id) else { return nil }
        let request = MKLocalSearch.Request(completion: completions[suggestion.id])
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            let placemark = item.placemark
            return PropertyResolvedAddress(street: suggestion.title,
                                           city: placemark.locality ?? suggestion.subtitle.components(separatedBy: ",").first ?? "",
                                           latitude: placemark.coordinate.latitude,
                                           longitude: placemark.coordinate.longitude,
                                           isLocated: true)
        } catch {
            lastError = "Couldn't look up that address. You can still use it as typed."
            return nil
        }
    }

    /// Places a typed address with a natural-language search. Falls back to an approximate pin.
    @MainActor
    func locate(manual text: String) async -> PropertyResolvedAddress {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = completer.region
        if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
            return PropertyResolvedAddress(street: trimmed, city: item.placemark.locality ?? "",
                                           latitude: item.placemark.coordinate.latitude,
                                           longitude: item.placemark.coordinate.longitude, isLocated: true)
        }
        return PropertyResolvedAddress(street: trimmed, city: "", latitude: Self.serviceCenter.latitude,
                                       longitude: Self.serviceCenter.longitude, isLocated: false)
    }

    // MARK: MKLocalSearchCompleterDelegate (MapKit calls these on the main thread)

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            let results = completer.results
            completions = results
            suggestions = results.enumerated().map { Suggestion(id: $0.offset, title: $0.element.title, subtitle: $0.element.subtitle) }
            isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            completions = []
            suggestions = []
            isSearching = false
            lastError = "No suggestions right now. You can use the address as typed."
        }
    }
}
