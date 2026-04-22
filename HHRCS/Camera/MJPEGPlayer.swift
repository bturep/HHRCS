import Foundation
import Combine

// Streams an MJPEG URL, publishing decoded frames as PlatformImage.
// Uses JPEG start/end markers (FF D8 ... FF D9) for reliable frame extraction.
// If no frame is received within 5 seconds of connecting, switches to fallbackURL.
final class MJPEGPlayer: NSObject, ObservableObject, URLSessionDataDelegate {

    @Published var currentFrame: PlatformImage?
    @Published var isConnected  = false
    @Published var statusText   = "CONNECTING"

    private(set) var streamURL: URL
    var fallbackURL: URL?

    private var session:    URLSession?
    private var dataTask:   URLSessionDataTask?
    private var buffer      = Data()
    private var retryCount  = 0
    private let maxRetries  = 5

    private var frameWatchdog: DispatchWorkItem?
    private var hasReceivedFrame = false
    private var usingFallback    = false

    private static let soi = Data([0xFF, 0xD8])
    private static let eoi = Data([0xFF, 0xD9])

    init(url: URL, fallbackURL: URL? = nil) {
        self.streamURL   = url
        self.fallbackURL = fallbackURL
        super.init()
    }

    func start() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = .infinity
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        connect()
    }

    func stop() {
        frameWatchdog?.cancel()
        frameWatchdog = nil
        dataTask?.cancel()
        session?.invalidateAndCancel()
        session  = nil
        dataTask = nil
    }

    private func connect() {
        buffer.removeAll()
        hasReceivedFrame = false
        statusText = retryCount == 0 ? "CONNECTING" : "RECONNECTING (\(retryCount))"
        let url = usingFallback ? (fallbackURL ?? streamURL) : streamURL
        var request = URLRequest(url: url)
        request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
        armWatchdog()
    }

    private func armWatchdog() {
        frameWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.hasReceivedFrame, !self.usingFallback,
                  self.fallbackURL != nil else { return }
            self.switchToFallback()
        }
        frameWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    private func switchToFallback() {
        usingFallback = true
        dataTask?.cancel()
        buffer.removeAll()
        DispatchQueue.main.async { self.statusText = "SWITCHING TO FALLBACK" }
        connect()
    }

    private func scheduleRetry() {
        guard retryCount < maxRetries else {
            DispatchQueue.main.async { self.statusText = "STREAM UNAVAILABLE" }
            return
        }
        retryCount += 1
        let delay = min(30.0, pow(2.0, Double(retryCount)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // MARK: – URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.statusText  = "LIVE"
            self.retryCount  = 0
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffer.append(data)
        extractFrames()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if let err = error, (err as NSError).code != NSURLErrorCancelled {
                self.scheduleRetry()
            }
        }
    }

    // MARK: – Frame extraction
    private func extractFrames() {
        while true {
            guard let soiRange = buffer.range(of: MJPEGPlayer.soi) else {
                buffer.removeAll()
                return
            }
            if soiRange.lowerBound > 0 {
                buffer.removeSubrange(0..<soiRange.lowerBound)
            }
            guard buffer.count > 2,
                  let eoiRange = buffer.range(of: MJPEGPlayer.eoi, in: 2..<buffer.count) else {
                if buffer.count > 10_000_000 { buffer.removeAll() }
                return
            }

            let frameEnd = eoiRange.upperBound
            let jpegData = Data(buffer[0..<frameEnd])

            if let img = PlatformImage(data: jpegData) {
                let captured = img
                if !hasReceivedFrame {
                    hasReceivedFrame = true
                    frameWatchdog?.cancel()
                }
                DispatchQueue.main.async { [weak self] in
                    self?.currentFrame = captured
                }
            }

            buffer.removeSubrange(0..<frameEnd)
        }
    }
}
