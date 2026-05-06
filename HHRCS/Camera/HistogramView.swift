import SwiftUI

// MARK: – Histogram poller

// Polls GET /hdmi/histogram every 5s; decodes the 64-bin JSON response.
final class HistogramPoller: ObservableObject {
    @Published var bins:        [Int]  = []
    @Published var clippedLow:  Double = 0
    @Published var clippedHigh: Double = 0

    var fetchURL: URL
    private var timer:   Timer?
    private var running = false

    init(fetchURL: URL) {
        self.fetchURL = fetchURL
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
        DispatchQueue.main.async {
            self.bins = []
            self.clippedLow  = 0
            self.clippedHigh = 0
        }
    }

    private func poll() {
        var req = URLRequest(url: fetchURL)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, err in
            guard let data,
                  let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawBins = json["bins"] as? [Int],
                  let low     = (json["clipped_low_pct"]  as? NSNumber)?.doubleValue,
                  let high    = (json["clipped_high_pct"] as? NSNumber)?.doubleValue
            else {
                print("[HistogramPoller] parse failed — data=\(data?.count ?? -1) err=\(String(describing: err))")
                return
            }
            print("[HistogramPoller] got \(rawBins.count) bins low=\(low) high=\(high)")
            DispatchQueue.main.async {
                self.bins        = rawBins
                self.clippedLow  = low
                self.clippedHigh = high
            }
        }.resume()
    }
}

// MARK: – Histogram view

// Renders 64 vertical bars. Bins 0 and 63 turn red if clipping exceeds 2%.
// Clipping label appears below bars when either value exceeds 0.5%.
struct HistogramView: View {
    let bins:        [Int]
    let clippedLow:  Double
    let clippedHigh: Double

    private static let barMaxHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            barsCanvas
            if clippedLow >= 0.005 || clippedHigh >= 0.005 {
                Text(String(format: "CLIPPED  LOW %.1f%%  ·  HIGH %.1f%%",
                            clippedLow * 100, clippedHigh * 100))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var barsCanvas: some View {
        Canvas { ctx, size in
            guard !bins.isEmpty else { return }
            let maxVal = CGFloat(bins.max() ?? 1)
            let count  = CGFloat(bins.count)
            let barW   = size.width / count

            for (i, bin) in bins.enumerated() {
                let h = max(1, Self.barMaxHeight * CGFloat(bin) / maxVal)
                let x = CGFloat(i) * barW
                let rect = CGRect(x: x, y: size.height - h,
                                  width: max(1, barW - 0.5), height: h)
                let color: Color = {
                    if i == 0 && clippedLow > 0.02              { return Theme.recordingRed }
                    if i == bins.count - 1 && clippedHigh > 0.02 { return Theme.recordingRed }
                    return Theme.tertiary
                }()
                ctx.fill(Path(rect), with: .color(color))
            }
        }
        .frame(height: Self.barMaxHeight)
    }
}
