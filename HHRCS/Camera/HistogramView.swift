import SwiftUI

// MARK: – Histogram style

enum HistogramStyle: String {
    case bars    = "bars"
    case curve   = "curve"
    case outline = "outline"
}

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

// Single tap cycles style: bars → curve → outline → bars.
// Long-press on the parent still image (BMPCC page only) toggles visibility.
// Bins 0 and 63 highlighted red when clipping exceeds 2%.
// Clipping label shown below when either value ≥ 0.5%.
struct HistogramView: View {
    let bins:        [Int]
    let clippedLow:  Double
    let clippedHigh: Double

    @AppStorage("histogramStyle") private var styleRaw: String = HistogramStyle.bars.rawValue

    private var style: HistogramStyle { HistogramStyle(rawValue: styleRaw) ?? .bars }

    private static let canvasHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            mainCanvas
                .onTapGesture { cycleStyle() }
            if clippedLow >= 0.005 || clippedHigh >= 0.005 {
                Text(String(format: "CLIPPED  LOW %.1f%%  ·  HIGH %.1f%%",
                            clippedLow * 100, clippedHigh * 100))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func cycleStyle() {
        let next: HistogramStyle
        switch style {
        case .bars:    next = .curve
        case .curve:   next = .outline
        case .outline: next = .bars
        }
        styleRaw = next.rawValue
    }

    private var mainCanvas: some View {
        Canvas { ctx, size in
            guard !self.bins.isEmpty else { return }
            let maxVal = CGFloat(self.bins.max() ?? 1)
            let barW   = size.width / CGFloat(self.bins.count)

            switch self.style {
            case .bars:
                for (i, bin) in self.bins.enumerated() {
                    let h = max(1, Self.canvasHeight * CGFloat(bin) / maxVal)
                    let x = CGFloat(i) * barW
                    let rect = CGRect(x: x, y: size.height - h,
                                      width: max(1, barW - 0.5), height: h)
                    let color: Color = {
                        if i == 0 && self.clippedLow > 0.02 { return Theme.recordingRed }
                        if i == self.bins.count - 1 && self.clippedHigh > 0.02 { return Theme.recordingRed }
                        return Theme.tertiary
                    }()
                    ctx.fill(Path(rect), with: .color(color))
                }

            case .curve:
                let path = self.smoothPath(size: size, maxVal: maxVal, barW: barW, closed: true)
                ctx.fill(path, with: .color(Theme.tertiary.opacity(0.6)))
                if self.clippedLow > 0.02 {
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: barW, height: size.height)),
                             with: .color(Theme.recordingRed.opacity(0.5)))
                }
                if self.clippedHigh > 0.02 {
                    ctx.fill(Path(CGRect(x: size.width - barW, y: 0, width: barW, height: size.height)),
                             with: .color(Theme.recordingRed.opacity(0.5)))
                }

            case .outline:
                let path = self.smoothPath(size: size, maxVal: maxVal, barW: barW, closed: false)
                ctx.stroke(path, with: .color(Theme.secondary), lineWidth: 1)
                if self.clippedLow > 0.02 {
                    var tick = Path()
                    tick.move(to:    CGPoint(x: 0.5, y: 0))
                    tick.addLine(to: CGPoint(x: 0.5, y: size.height))
                    ctx.stroke(tick, with: .color(Theme.recordingRed), lineWidth: 1)
                }
                if self.clippedHigh > 0.02 {
                    var tick = Path()
                    tick.move(to:    CGPoint(x: size.width - 0.5, y: 0))
                    tick.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
                    ctx.stroke(tick, with: .color(Theme.recordingRed), lineWidth: 1)
                }
            }
        }
        .frame(height: Self.canvasHeight)
    }

    // Mid-point quadratic bezier through bin-top points.
    // closed=true adds baseline edges to form a filled area shape.
    private func smoothPath(size: CGSize, maxVal: CGFloat, barW: CGFloat, closed: Bool) -> Path {
        let pts: [CGPoint] = bins.enumerated().map { i, bin in
            let h = max(1, Self.canvasHeight * CGFloat(bin) / maxVal)
            return CGPoint(x: barW * (CGFloat(i) + 0.5), y: size.height - h)
        }
        guard pts.count >= 2 else { return Path() }

        var p = Path()

        if closed {
            p.move(to:    CGPoint(x: 0, y: size.height))
            p.addLine(to: pts[0])
        } else {
            p.move(to: pts[0])
        }

        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i-1].x + pts[i].x) / 2,
                              y: (pts[i-1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i-1])
        }
        p.addLine(to: pts.last!)

        if closed {
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
        }

        return p
    }
}
