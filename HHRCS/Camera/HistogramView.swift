import SwiftUI

// MARK: – Per-channel data

struct ChannelHistogram {
    var bins:        [Int]
    var clippedLow:  Double
    var clippedHigh: Double

    static let empty = ChannelHistogram(bins: [], clippedLow: 0, clippedHigh: 0)
}

// MARK: – Channel mode

enum HistogramChannel: String {
    case luma       = "luma"
    case rgbOverlap = "rgbOverlap"
    case rgbStacked = "rgbStacked"
}

// MARK: – Histogram poller

// Polls GET /hdmi/histogram every 5s; decodes the multi-channel 64-bin JSON response.
final class HistogramPoller: ObservableObject {
    @Published var luma = ChannelHistogram.empty
    @Published var r    = ChannelHistogram.empty
    @Published var g    = ChannelHistogram.empty
    @Published var b    = ChannelHistogram.empty

    var isEmpty: Bool { luma.bins.isEmpty }

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
            self.luma = .empty
            self.r    = .empty
            self.g    = .empty
            self.b    = .empty
        }
    }

    private func poll() {
        var req = URLRequest(url: fetchURL)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, err in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                print("[HistogramPoller] parse failed err=\(String(describing: err))")
                return
            }
            func parseCh(_ key: String) -> ChannelHistogram? {
                guard let ch   = json[key] as? [String: Any],
                      let bins = ch["bins"] as? [Int],
                      let low  = (ch["clipped_low_pct"]  as? NSNumber)?.doubleValue,
                      let high = (ch["clipped_high_pct"] as? NSNumber)?.doubleValue
                else { return nil }
                return ChannelHistogram(bins: bins, clippedLow: low, clippedHigh: high)
            }
            guard let luma = parseCh("luma"),
                  let r    = parseCh("r"),
                  let g    = parseCh("g"),
                  let b    = parseCh("b")
            else {
                print("[HistogramPoller] parse failed — channels missing in response")
                return
            }
            print("[HistogramPoller] got \(luma.bins.count) bins (luma+RGB)")
            DispatchQueue.main.async {
                self.luma = luma
                self.r    = r
                self.g    = g
                self.b    = b
            }
        }.resume()
    }
}

// MARK: – Histogram view

// Single tap cycles channel mode: luma → RGB overlap → RGB stacked → luma.
// Long-press on the parent still image toggles display mode (still ↔ false color).
// Red ticks at edges when any channel clipping exceeds 2%.
struct HistogramView: View {
    let luma: ChannelHistogram
    let r:    ChannelHistogram
    let g:    ChannelHistogram
    let b:    ChannelHistogram

    @AppStorage("histogramChannel") private var channelRaw: String = HistogramChannel.luma.rawValue

    private var channel: HistogramChannel { HistogramChannel(rawValue: channelRaw) ?? .luma }

    private var anyClippedLow:  Double { max(luma.clippedLow,  r.clippedLow,  g.clippedLow,  b.clippedLow) }
    private var anyClippedHigh: Double { max(luma.clippedHigh, r.clippedHigh, g.clippedHigh, b.clippedHigh) }

    private static let canvasHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            mainCanvas
                .onTapGesture { cycleChannel() }
            if anyClippedLow >= 0.005 || anyClippedHigh >= 0.005 {
                Text(String(format: "CLIP  ↓%.1f%%  ↑%.1f%%",
                            anyClippedLow * 100, anyClippedHigh * 100))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func cycleChannel() {
        switch channel {
        case .luma:       channelRaw = HistogramChannel.rgbOverlap.rawValue
        case .rgbOverlap: channelRaw = HistogramChannel.rgbStacked.rawValue
        case .rgbStacked: channelRaw = HistogramChannel.luma.rawValue
        }
    }

    private var mainCanvas: some View {
        Canvas { ctx, size in
            guard !self.luma.bins.isEmpty else { return }
            let barW = size.width / CGFloat(self.luma.bins.count)

            switch self.channel {

            case .luma:
                let maxVal = CGFloat(self.luma.bins.max() ?? 1)
                let path = self.curveFor(self.luma.bins,
                                          in: CGRect(origin: .zero, size: size),
                                          maxVal: maxVal, barW: barW, closed: true)
                ctx.fill(path, with: .color(Theme.tertiary.opacity(0.6)))
                self.drawClipTicks(&ctx, size: size,
                                   low: self.anyClippedLow, high: self.anyClippedHigh)

            case .rgbOverlap:
                let maxVal = CGFloat(max(
                    self.r.bins.max() ?? 1, self.g.bins.max() ?? 1, self.b.bins.max() ?? 1, 1
                ))
                let fullRect = CGRect(origin: .zero, size: size)
                // Draw B then G then R so warmer colors are on top
                let layers: [(bins: [Int], color: Color)] = [
                    (self.b.bins, Color(red: 0.25, green: 0.5,  blue: 1.0)),
                    (self.g.bins, Color(red: 0.25, green: 1.0,  blue: 0.25)),
                    (self.r.bins, Color(red: 1.0,  green: 0.25, blue: 0.25)),
                ]
                for layer in layers {
                    let path = self.curveFor(layer.bins, in: fullRect,
                                              maxVal: maxVal, barW: barW, closed: true)
                    ctx.fill(path, with: .color(layer.color.opacity(0.5)))
                }
                self.drawClipTicks(&ctx, size: size,
                                   low: self.anyClippedLow, high: self.anyClippedHigh)

            case .rgbStacked:
                let maxVal = CGFloat(max(
                    self.r.bins.max() ?? 1, self.g.bins.max() ?? 1, self.b.bins.max() ?? 1, 1
                ))
                let bandH = size.height / 3
                let bands: [(bins: [Int], color: Color)] = [
                    (self.r.bins, Color(red: 1.0,  green: 0.25, blue: 0.25)),
                    (self.g.bins, Color(red: 0.25, green: 1.0,  blue: 0.25)),
                    (self.b.bins, Color(red: 0.25, green: 0.5,  blue: 1.0)),
                ]
                for (i, band) in bands.enumerated() {
                    let rect = CGRect(x: 0, y: CGFloat(i) * bandH,
                                      width: size.width, height: bandH)
                    let path = self.curveFor(band.bins, in: rect,
                                              maxVal: maxVal, barW: barW, closed: true)
                    ctx.fill(path, with: .color(band.color.opacity(0.6)))
                    if i < 2 {
                        var sep = Path()
                        sep.move(to:    CGPoint(x: 0,          y: rect.maxY))
                        sep.addLine(to: CGPoint(x: size.width, y: rect.maxY))
                        ctx.stroke(sep, with: .color(Theme.tertiary.opacity(0.15)), lineWidth: 0.5)
                    }
                }
                self.drawClipTicks(&ctx, size: size,
                                   low: self.anyClippedLow, high: self.anyClippedHigh)
            }
        }
        .frame(height: Self.canvasHeight)
    }

    // Mid-point quadratic bezier through bin-top points within `rect`.
    // closed=true adds baseline edges to form a filled area shape.
    private func curveFor(_ bins: [Int], in rect: CGRect, maxVal: CGFloat,
                          barW: CGFloat, closed: Bool) -> Path {
        let pts: [CGPoint] = bins.enumerated().map { i, bin in
            let h = max(1, rect.height * CGFloat(bin) / maxVal)
            return CGPoint(x: rect.minX + barW * (CGFloat(i) + 0.5),
                           y: rect.maxY - h)
        }
        guard pts.count >= 2 else { return Path() }

        var p = Path()
        if closed {
            p.move(to:    CGPoint(x: rect.minX, y: rect.maxY))
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
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }

    private func drawClipTicks(_ ctx: inout GraphicsContext, size: CGSize,
                                low: Double, high: Double) {
        if low > 0.02 {
            var t = Path()
            t.move(to:    CGPoint(x: 0.5, y: 0))
            t.addLine(to: CGPoint(x: 0.5, y: size.height))
            ctx.stroke(t, with: .color(Theme.recordingRed), lineWidth: 1)
        }
        if high > 0.02 {
            var t = Path()
            t.move(to:    CGPoint(x: size.width - 0.5, y: 0))
            t.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
            ctx.stroke(t, with: .color(Theme.recordingRed), lineWidth: 1)
        }
    }
}
