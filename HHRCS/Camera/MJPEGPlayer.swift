import Foundation
import Combine

// Streams an MJPEG URL, publishing decoded frames as PlatformImage.
// Decoded frames are placed in a capped queue; a display timer dequeues
// and publishes them at frameInterval for smooth, consistent playback.
final class MJPEGPlayer: NSObject, ObservableObject, URLSessionDataDelegate {

    @Published var currentFrame: PlatformImage?
    @Published var isConnected  = false
    @Published var statusText   = "CONNECTING"

    var streamURL: URL
    var fallbackURL: URL?

    // Playback tuning — change without recompilation.
    var frameInterval:   TimeInterval = 0.2   // display cadence (~5 fps)
    var bufferCapacity:  Int          = 8     // max queued frames before dropping oldest

    private var session:    URLSession?
    private var dataTask:   URLSessionDataTask?
    private var buffer      = Data()
    private var retryCount  = 0
    private let maxRetries  = 5

    // Serial queue — serializes all buffer + frameQueue access, preventing
    // EXC_BAD_INSTRUCTION crashes from concurrent didReceive/extractFrames calls.
    private let bufferQueue = DispatchQueue(label: "com.hhrcs.mjpeg.buffer")

    // Decoded frame queue — all access on bufferQueue.
    private var frameQueue: [PlatformImage] = []

    // Display timer fires on bufferQueue so dequeue is serialized with enqueue.
    private var displayTimer: DispatchSourceTimer?

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
        startDisplayTimer()
        connect()
    }

    func stop() {
        displayTimer?.cancel()
        displayTimer = nil
        frameWatchdog?.cancel()
        frameWatchdog = nil
        dataTask?.cancel()
        session?.invalidateAndCancel()
        session  = nil
        dataTask = nil
        bufferQueue.async { self.frameQueue.removeAll() }
    }

    private func startDisplayTimer() {
        let timer = DispatchSource.makeTimerSource(queue: bufferQueue)
        timer.schedule(deadline: .now() + frameInterval,
                       repeating: frameInterval,
                       leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self, !self.frameQueue.isEmpty else { return }
            let frame = self.frameQueue.removeFirst()
            DispatchQueue.main.async { self.currentFrame = frame }
        }
        timer.resume()
        displayTimer = timer
    }

    private func connect() {
        bufferQueue.sync { buffer.removeAll() }
        hasReceivedFrame = false
        statusText = retryCount == 0 ? "CONNECTING" : "RECONNECTING (\(retryCount))"
        let url = usingFallback ? (fallbackURL ?? streamURL) : streamURL
        print("[MJPEG] connect url=\(url) retry=\(retryCount)")
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
        bufferQueue.sync { buffer.removeAll() }
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
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[MJPEG] response HTTP \(code) from \(response.url?.absoluteString ?? "?")")
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
        bufferQueue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(data)
            self.extractFrames()
        }
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

    // MARK: – Frame extraction (always called from bufferQueue)

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
                if buffer.count > 50_000_000 { buffer.removeAll() }
                return
            }

            let frameEnd = eoiRange.upperBound
            let jpegData = Data(buffer[0..<frameEnd])
            buffer.removeSubrange(0..<frameEnd)

            guard let img = PlatformImage(data: jpegData) else { continue }

            if !hasReceivedFrame {
                hasReceivedFrame = true
                frameWatchdog?.cancel()
            }

            // Enqueue for display; drop the oldest frame if at capacity.
            if frameQueue.count >= bufferCapacity {
                frameQueue.removeFirst()
            }
            frameQueue.append(img)
        }
    }
}
