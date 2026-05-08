import Foundation
import MapKit

final class LocationSearchViewModel: NSObject, ObservableObject {

    @Published var query: String = "" {
        didSet { guard query != oldValue else { return }; scheduleSearch() }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    // Set true before programmatic clearQuery() to suppress the empty-field confirmation sheet.
    var suppressNextClearConfirmation = false

    private let completer = MKLocalSearchCompleter()
    private var debounceTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// App-initiated clear — suppresses the "Clear location?" confirmation.
    func clearQuery() {
        suppressNextClearConfirmation = true
        query     = ""
        results   = []
        isSearching = false
        debounceTask?.cancel()
        DispatchQueue.main.async { [weak self] in self?.suppressNextClearConfirmation = false }
    }

    /// Resolve a completion to coordinates + formatted address string.
    func select(_ completion: MKLocalSearchCompletion) async -> (lat: Double, lon: Double, address: String)? {
        let req = MKLocalSearch.Request(completion: completion)
        guard let resp  = try? await MKLocalSearch(request: req).start(),
              let item  = resp.mapItems.first else { return nil }
        let coord = item.placemark.coordinate
        let parts: [String] = [
            item.placemark.subThoroughfare,
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.administrativeArea,
            item.placemark.postalCode,
            item.placemark.country,
        ].compactMap { $0 }
        return (coord.latitude, coord.longitude, parts.joined(separator: ", "))
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results     = []
            isSearching = false
            return
        }
        isSearching = true
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.completer.queryFragment = q
        }
    }
}

extension LocationSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        DispatchQueue.main.async { [weak self] in
            self?.results     = Array(r.prefix(5))
            self?.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.results     = []
            self?.isSearching = false
        }
    }
}
