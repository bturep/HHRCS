import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Periodically triggers a Pi still capture then fetches the resulting JPEG.
// Only one network round-trip per tick; no persistent socket.
final class StillPoller: ObservableObject {
    @Published var latestImage: PlatformImage?
    @Published var lastUpdated: Date?

    var triggerURL: URL
    var fetchURL:   URL

    private var timer:   Timer?
    private var running = false

    init(triggerURL: URL, fetchURL: URL) {
        self.triggerURL = triggerURL
        self.fetchURL   = fetchURL
    }

    func start() {
        guard !running else { return }
        running = true
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.async { self.latestImage = nil }
    }

    func refreshNow() {
        poll()
    }

    private func poll() {
        var req = URLRequest(url: triggerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            guard let self else { return }
            var fetch = URLRequest(url: self.fetchURL)
            fetch.timeoutInterval = 8
            URLSession.shared.dataTask(with: fetch) { data, _, _ in
                guard let data, let img = PlatformImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.latestImage = img
                    self.lastUpdated = Date()
                }
            }.resume()
        }.resume()
    }
}
