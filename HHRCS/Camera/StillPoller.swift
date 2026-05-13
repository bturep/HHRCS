import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Notification.Name {
    static let stillRefreshIntervalChanged = Notification.Name("stillRefreshIntervalChanged")
}

// Periodically triggers a Pi still capture then fetches the resulting JPEG.
// Interval is read from UserDefaults key "stillRefreshInterval" (seconds; -1 = manual only).
final class StillPoller: ObservableObject {
    @Published var latestImage: PlatformImage?
    @Published var lastUpdated: Date?
    @Published var isManual:    Bool = false

    var triggerURL: URL
    var fetchURL:   URL

    private var timer:   Timer?
    private var running = false

    static let intervalKey     = "stillRefreshInterval"
    static let defaultInterval = 5

    private var currentInterval: Int {
        let v = UserDefaults.standard.integer(forKey: Self.intervalKey)
        return v == 0 ? Self.defaultInterval : v  // 0 = key unset → default 5s
    }

    init(triggerURL: URL, fetchURL: URL) {
        self.triggerURL = triggerURL
        self.fetchURL   = fetchURL
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIntervalChange),
            name: .stillRefreshIntervalChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    func start() {
        guard !running else { return }
        running = true
        scheduleTimer()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.async {
            self.latestImage = nil
            self.isManual    = false
        }
    }

    func refreshNow() {
        poll()
    }

    @objc private func handleIntervalChange() {
        guard running else { return }
        timer?.invalidate()
        timer = nil
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = currentInterval
        DispatchQueue.main.async { self.isManual = interval == -1 }
        poll()
        guard interval != -1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            self?.poll()
        }
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
