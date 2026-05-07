import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum CameraPage: Int, CaseIterable {
    case still     = 0
    case live      = 1
    case detection = 2

    var label: String {
        switch self {
        case .still:     return "BMPCC"
        case .live:      return "CAM"
        case .detection: return "DETECT"
        }
    }
}

struct CameraTabView: View {
    var isActive: Bool = true

    @EnvironmentObject var vm: DataViewModel
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver
    @ObservedObject private var settings = AppSettings.shared

    @State private var currentPage        = CameraPage.still
    @State private var showISOPopover     = false
    @State private var showWBPopover      = false
    @State private var showShutterPopover = false
    @State private var showYoloPopover    = false

    // HDMI still: POST /hdmi/still → GET /hdmi/stills/latest
    @StateObject private var hdmiPoller = StillPoller(
        triggerURL: URL(string: "http://raspberrypi.local:5001/hdmi/still")!,
        fetchURL:   URL(string: "http://raspberrypi.local:5001/hdmi/stills/latest")!
    )
    // Pi cam still: POST /still/trigger → GET /stills/latest
    @StateObject private var camPoller = StillPoller(
        triggerURL: URL(string: "http://raspberrypi.local:5001/still/trigger")!,
        fetchURL:   URL(string: "http://raspberrypi.local:5001/stills/latest")!
    )
    // HDMI histogram: GET /hdmi/histogram every 5s (BMPCC page only)
    @StateObject private var histogramPoller = HistogramPoller(
        fetchURL: URL(string: "http://raspberrypi.local:5001/hdmi/histogram")!
    )
    // BMPCC false color: GET /hdmi/falsecolor every 5s (BMPCC page only)
    @StateObject private var falseColorPoller = FalseColorPoller(
        fetchURL: URL(string: "http://raspberrypi.local:5001/hdmi/falsecolor")!
    )

    private var isLandscape: Bool { orientationObserver.orientation.isLandscape }

    private func makeURL(_ path: String) -> URL {
        if !settings.piServerURL.isEmpty,
           var c = URLComponents(string: settings.piServerURL),
           c.host != nil {
            c.path = path; c.query = nil
            if let url = c.url { return url }
        }
        return URL(string: "http://raspberrypi.local:5001\(path)")!
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            TabView(selection: $currentPage) {
                StillImagePage(
                    poller:          hdmiPoller,
                    luma:            histogramPoller.luma,
                    r:               histogramPoller.r,
                    g:               histogramPoller.g,
                    b:               histogramPoller.b,
                    falseColorImage: falseColorPoller.latestImage
                )
                .padding(.top, 32)
                .padding(.bottom, isLandscape ? 0 : 54)
                .tag(CameraPage.still)

                StillImagePage(poller: camPoller)
                    .padding(.top, 32)
                    .padding(.bottom, isLandscape ? 0 : 54)
                    .tag(CameraPage.live)

                DetectionOverlayView(poller: camPoller)
                    .padding(.top, 32)
                    .padding(.bottom, isLandscape ? 0 : 54)
                    .tag(CameraPage.detection)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: isLandscape ? .all : .top)

            if !isLandscape {
                switch currentPage {
                case .still:
                    OperatorControlRow(
                        isOwner: settings.ownerModeEnabled,
                        isRecording: vm.isRecording,
                        captureIsPlaceholder: false,
                        onRecord: { Task { await vm.toggleBmpccRecord() } },
                        onCapture: { Task { await vm.captureHdmiStill() } }
                    ) { pageIndicator }
                case .live:
                    OperatorControlRow(
                        isOwner: settings.ownerModeEnabled,
                        isRecording: vm.isPiCamRecording,
                        captureIsPlaceholder: false,
                        recordDisabled: true,
                        onRecord: { vm.togglePiCamRecord() },
                        onCapture: { Task { await vm.captureStill() } }
                    ) { pageIndicator }
                case .detection:
                    detectionControlBar
                }
            }
        }
        .overlay(alignment: .top) {
            switch currentPage {
            case .still:     stillDataBar
            case .live:      EmptyView()
            case .detection: detectionHudStrip
            }
        }
        .background(Theme.background)
        .onAppear { startActivePoller() }
        .onDisappear { camPoller.stop(); hdmiPoller.stop(); histogramPoller.stop(); falseColorPoller.stop() }
        .onChange(of: currentPage) { _, _ in rebalancePollers() }
        .onChange(of: isActive) { _, active in
            if active { startActivePoller() }
            else { camPoller.stop(); hdmiPoller.stop(); histogramPoller.stop(); falseColorPoller.stop() }
        }
        .onChange(of: settings.piServerURL) { _, _ in updatePollerURLs() }
    }

    // MARK: – Poller lifecycle

    private func startActivePoller() {
        updatePollerURLs()
        if currentPage == .still {
            camPoller.stop()
            hdmiPoller.start()
            histogramPoller.start()
            falseColorPoller.start()
        } else {
            hdmiPoller.stop()
            histogramPoller.stop()
            falseColorPoller.stop()
            camPoller.start()
        }
    }

    private func rebalancePollers() {
        switch currentPage {
        case .still:
            camPoller.stop()
            hdmiPoller.start()
            histogramPoller.start()
            falseColorPoller.start()
        case .live, .detection:
            hdmiPoller.stop()
            histogramPoller.stop()
            falseColorPoller.stop()
            camPoller.start()
        }
    }

    private func updatePollerURLs() {
        hdmiPoller.triggerURL     = makeURL("/hdmi/still")
        hdmiPoller.fetchURL       = makeURL("/hdmi/stills/latest")
        camPoller.triggerURL      = makeURL("/still/trigger")
        camPoller.fetchURL        = makeURL("/stills/latest")
        histogramPoller.fetchURL  = makeURL("/hdmi/histogram")
        falseColorPoller.fetchURL = makeURL("/hdmi/falsecolor")
    }

    // MARK: – Data bar (BMPCC page only)

    private var stillDataBar: some View {
        HStack(spacing: 0) {
            if vm.yoloLocked && vm.isRecording {
                Text("AUTO")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 10)
            }

            Group {
                if settings.ownerModeEnabled {
                    Button { showISOPopover = true } label: {
                        Text("ISO \(vm.iso)")
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showISOPopover,
                             attachmentAnchor: .point(.bottom),
                             arrowEdge: .top) {
                        ISOPopover()
                            .environmentObject(vm)
                            .frame(width: 280)
                            .presentationCompactAdaptation(.popover)
                    }
                } else {
                    Text("ISO \(vm.iso)")
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))

            Spacer()

            Group {
                if settings.ownerModeEnabled {
                    Button { showWBPopover = true } label: {
                        Text("\(vm.wbKelvin)K")
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showWBPopover,
                             attachmentAnchor: .point(.bottom),
                             arrowEdge: .top) {
                        WBPopover()
                            .environmentObject(vm)
                            .frame(width: 280)
                            .presentationCompactAdaptation(.popover)
                    }
                } else {
                    Text("\(vm.wbKelvin)K")
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))

            Spacer()

            Group {
                if settings.ownerModeEnabled {
                    Button { showShutterPopover = true } label: {
                        Text(shutterLabel)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showShutterPopover,
                             attachmentAnchor: .point(.bottom),
                             arrowEdge: .top) {
                        ShutterPopover()
                            .environmentObject(vm)
                            .frame(width: 280)
                            .presentationCompactAdaptation(.popover)
                    }
                } else {
                    Text(shutterLabel)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.background)
        .frame(maxWidth: .infinity)
    }

    private var shutterLabel: String {
        let a = vm.shutterAngle
        return a.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(a))°"
            : String(format: "%.1f°", a)
    }

    // MARK: – Detection HUD strip

    private var detectionHudStrip: some View {
        ZStack {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if vm.triggerState == .active {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 5, height: 5)
                    }
                    Text(vm.triggerStateLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(vm.triggerStateColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(vm.triggerStateColor.opacity(0.5), lineWidth: Theme.ruleWidth)
                )

                if !vm.lastDetectionClass.isEmpty {
                    Text(vm.lastDetectionClass.uppercased())
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)

            Button { showYoloPopover = true } label: {
                Text(vm.healthYoloSimMode ? "YOLOv8  SIM" : "YOLOv8  LIVE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.background.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.accent.opacity(0.4), lineWidth: Theme.ruleWidth)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showYoloPopover) {
                YoloInfoPopover(simulationMode: settings.simulationMode)
                    .presentationCompactAdaptation(.popover)
            }

            HStack {
                Spacer()
                Text(vm.lastDetectionTimeString)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .background(Theme.background)
        .frame(maxWidth: .infinity)
    }

    // MARK: – Detection bottom bar

    private var detectionControlBar: some View {
        HStack {
            Spacer()
            pageIndicator
            Spacer()
        }
        .frame(height: 44)
        .padding(.bottom, 10)
        .background(Theme.background)
    }

    // MARK: – Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(CameraPage.allCases, id: \.rawValue) { page in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { currentPage = page }
                } label: {
                    if page == currentPage {
                        Text(page.label)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(Theme.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.accentColor, lineWidth: 0.5)
                            )
                    } else {
                        Circle()
                            .fill(Theme.rule)
                            .frame(width: 5, height: 5)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: – False color display mode

private enum DisplayMode: String {
    case still      = "still"
    case falseColor = "falseColor"
}

// MARK: – False color poller

// Polls GET /hdmi/falsecolor every 5s; publishes the JPEG as a PlatformImage.
final class FalseColorPoller: ObservableObject {
    @Published var latestImage: PlatformImage? = nil

    var fetchURL: URL
    private var timer:   Timer?
    private var running = false

    init(fetchURL: URL) { self.fetchURL = fetchURL }

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

    private func poll() {
        var req = URLRequest(url: fetchURL)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let image = PlatformImage(data: data)
            else { return }
            DispatchQueue.main.async { self.latestImage = image }
        }.resume()
    }
}

// MARK: – False color IRE scale bar

// Smooth gradient bar matching the BMPCC false color LUT anchors.
// ARRI/BMPCC band-based scalebar. Gradient stops use empirically-shifted IRE thresholds
// matching our 8-bit HDMI feed. Labels stay at BMPCC conceptual reference positions
// (0–100 scale) so the operator sees the exposure intent, not pixel values.
private struct FalseColorScalebar: View {
    // Hard-edge band transitions via paired stops. Gradient positions use the
    // empirically-shifted IRE values that match our 8-bit HDMI feed; labels
    // (in the Canvas below) stay at BMPCC's conceptual reference positions.
    private static let gradientStops: [Gradient.Stop] = [
        // Purple band 0–5.5% (BDL)
        .init(color: Color(red: 100/255, green:   0,       blue: 130/255), location: 0.000),
        .init(color: Color(red: 100/255, green:   0,       blue: 130/255), location: 0.055),
        // Blue band 5.5–10% (NBDL)
        .init(color: Color(red:   0,     green: 100/255,   blue:   1),     location: 0.055),
        .init(color: Color(red:   0,     green: 100/255,   blue:   1),     location: 0.100),
        // Grey zone 10–58%
        .init(color: Color(white: 0x1A/255),                                location: 0.100),
        .init(color: Color(white: 0x94/255),                                location: 0.580),
        // Green band 58–62% (18%MG)
        .init(color: Color(red:   0,     green: 220/255,   blue:   0),     location: 0.580),
        .init(color: Color(red:   0,     green: 220/255,   blue:   0),     location: 0.620),
        // Grey zone 62–73%
        .init(color: Color(white: 0x9E/255),                                location: 0.620),
        .init(color: Color(white: 0xBA/255),                                location: 0.730),
        // Pink band 73–77% (MG+1)
        .init(color: Color(red: 240/255, green: 100/255,   blue: 200/255), location: 0.730),
        .init(color: Color(red: 240/255, green: 100/255,   blue: 200/255), location: 0.770),
        // Grey zone 77–88%
        .init(color: Color(white: 0xC4/255),                                location: 0.770),
        .init(color: Color(white: 0xE0/255),                                location: 0.880),
        // Yellow band 88–93% (80%WC)
        .init(color: Color(red: 240/255, green: 220/255,   blue:   0),     location: 0.880),
        .init(color: Color(red: 240/255, green: 220/255,   blue:   0),     location: 0.930),
        // Grey gap 93–95%
        .init(color: Color(white: 0xED/255),                                location: 0.930),
        .init(color: Color(white: 0xF2/255),                                location: 0.950),
        // Red band 95–100% (95%WC / clip)
        .init(color: .red,                                                   location: 0.950),
        .init(color: .red,                                                   location: 1.000),
    ]

    var body: some View {
        VStack(spacing: 3) {
            // Gradient bar
            Rectangle()
                .fill(LinearGradient(stops: Self.gradientStops,
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)
            // IRE position labels
            HStack {
                Text("0")
                Spacer()
                Text("25")
                Spacer()
                Text("50")
                Spacer()
                Text("75")
                Spacer()
                Text("100")
            }
            .font(.system(size: 7, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.tertiary)
            // Reference band legend — positioned at approximate IRE fractions
            Canvas { ctx, size in
                // Labels at BMPCC conceptual reference positions (not shifted pixel values).
                let items: [(String, CGFloat, UnitPoint)] = [
                    ("BDL",   0.000, UnitPoint(x: 0,   y: 0.5)),
                    ("NBDL",  0.040, UnitPoint(x: 0,   y: 0.5)),
                    ("18%MG", 0.400, UnitPoint(x: 0.5, y: 0.5)),
                    ("MG+1",  0.550, UnitPoint(x: 0.5, y: 0.5)),
                    ("80%WC", 0.800, UnitPoint(x: 0.5, y: 0.5)),
                    ("95%WC", 0.990, UnitPoint(x: 1,   y: 0.5)),
                ]
                for (label, frac, anchor) in items {
                    let resolved = ctx.resolve(
                        Text(label)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundColor(Color(white: 0.30))
                    )
                    ctx.draw(resolved,
                             at: CGPoint(x: size.width * frac, y: size.height / 2),
                             anchor: anchor)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}

// MARK: – Still image page (used by BMPCC and CAM sub-pages)

private struct StillImagePage: View {
    @ObservedObject var poller: StillPoller
    var luma:            ChannelHistogram = .empty
    var r:               ChannelHistogram = .empty
    var g:               ChannelHistogram = .empty
    var b:               ChannelHistogram = .empty
    var falseColorImage: PlatformImage?   = nil

    // Long-press cycles still ↔ false color (BMPCC page only; no-op when no data).
    @AppStorage("bmpccDisplayMode") private var displayModeRaw: String = DisplayMode.still.rawValue
    @State private var showFullscreen = false

    private var displayMode:   DisplayMode { DisplayMode(rawValue: displayModeRaw) ?? .still }
    private var hasHistogram:  Bool { !luma.bins.isEmpty }
    private var canToggle:     Bool { hasHistogram || falseColorImage != nil }

    var body: some View {
        VStack(spacing: 0) {
            imageArea
            bottomStrip
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(
                    image:       image,
                    isPresented: $showFullscreen,
                    luma:        luma,
                    r:           r,
                    g:           g,
                    b:           b
                )
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(
                    image:       image,
                    isPresented: $showFullscreen,
                    luma:        luma,
                    r:           r,
                    g:           g,
                    b:           b
                )
            }
        }
        #endif
    }

    @ViewBuilder
    private var imageArea: some View {
        let shownImage: PlatformImage? = (displayMode == .falseColor && falseColorImage != nil)
            ? falseColorImage
            : poller.latestImage

        ZStack {
            Theme.background

            if let image = shownImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .contentShape(Rectangle())
                    .contextMenu { }          // suppress iOS image-preview on long-press
                    .onTapGesture {
                        if displayMode == .still { showFullscreen = true }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                guard canToggle else { return }
                                let next: DisplayMode = displayMode == .still ? .falseColor : .still
                                displayModeRaw = next.rawValue
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }
                    )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundStyle(Theme.tertiary)
                    Text("POLLING")
                        .font(Theme.dataLabel())
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if displayMode == .still {
                HStack(spacing: 10) {
                    if let updated = poller.lastUpdated {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let elapsed = Int(max(0, ctx.date.timeIntervalSince(updated)))
                            Text("\(elapsed)s")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(Theme.tertiary.opacity(0.4))
                        }
                    }
                    Button { poller.refreshNow() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var bottomStrip: some View {
        if displayMode == .falseColor {
            FalseColorScalebar()
        } else if hasHistogram {
            HistogramView(luma: luma, r: r, g: g, b: b)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
        }
    }
}

// MARK: – Shared operator control row (BMPCC + CAM)

private struct OperatorControlRow<Indicator: View>: View {
    let isOwner: Bool
    let isRecording: Bool
    let captureIsPlaceholder: Bool
    var recordDisabled: Bool = false
    let onRecord: () -> Void
    let onCapture: () -> Void
    @ViewBuilder let indicator: () -> Indicator

    @State private var captureFlash = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Group {
                    if isOwner {
                        if recordDisabled {
                            VStack(spacing: 2) {
                                Image(systemName: "record.circle")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.tertiary.opacity(0.4))
                                Text("PROXY RECORDING — PLANNED")
                                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Theme.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .allowsHitTesting(false)
                        } else {
                            Button {
                                onRecord()
                            } label: {
                                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 26))
                                    .foregroundStyle(isRecording ? Theme.recordingRed : Theme.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)

                Group {
                    if isOwner {
                        if captureIsPlaceholder {
                            Text("HDMI PREVIEW")
                                .font(Theme.dataLabel(size: 8))
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Color.white.opacity(0.4))
                        } else {
                            Button {
                                withAnimation(.easeOut(duration: 0.08)) { captureFlash = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeIn(duration: 0.08)) { captureFlash = false }
                                }
                                onCapture()
                            } label: {
                                Image(systemName: "camera.aperture")
                                    .font(.system(size: 24))
                                    .foregroundStyle(captureFlash ? Theme.accent : Color.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }

            indicator()
        }
        .frame(height: 44)
        .padding(.bottom, 10)
        .background(Theme.background)
    }
}

// MARK: – ISO popover

private struct ISOPopover: View {
    @EnvironmentObject var vm: DataViewModel
    private let isoStops = [100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ISO")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Text("\(vm.iso)")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Slider(
                value: Binding(
                    get: { Double(isoStops.firstIndex(of: vm.iso) ?? 2) },
                    set: { vm.iso = isoStops[Int($0.rounded())] }
                ),
                in: 0...Double(isoStops.count - 1),
                step: 1
            ) { editing in
                if !editing { Task { await vm.setISO(vm.iso) } }
            }
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
    }
}

// MARK: – WB popover

private struct WBPopover: View {
    @EnvironmentObject var vm: DataViewModel
    private let presets: [(String, Int)] = [
        ("TUNG", 3200), ("FLUO", 4000), ("SUN", 5600), ("CLOUD", 6500), ("SHADE", 7500)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHITE BALANCE")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Text("\(vm.wbKelvin) K")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Slider(
                value: Binding(
                    get: { Double(vm.wbKelvin) },
                    set: { vm.wbKelvin = Int($0.rounded()) }
                ),
                in: 2500...10000,
                step: 100
            ) { editing in
                if !editing { Task { await vm.setWB(vm.wbKelvin) } }
            }
            .tint(Theme.accent)

            HStack(spacing: 0) {
                ForEach(presets, id: \.0) { name, kelvin in
                    Button(name) {
                        vm.wbKelvin = kelvin
                        Task { await vm.setWB(kelvin) }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(vm.wbKelvin == kelvin ? Theme.accent : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                vm.wbKelvin == kelvin ? Theme.accent.opacity(0.5) : Theme.rule,
                                lineWidth: Theme.ruleWidth
                            )
                    )
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
    }
}

// MARK: – Shutter popover

private struct ShutterPopover: View {
    @EnvironmentObject var vm: DataViewModel
    private let options: [Double] = [90, 120, 172.8, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHUTTER ANGLE")
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { angle in
                    Button(angleLabel(angle)) {
                        vm.shutterAngle = angle
                        Task { await vm.setShutterAngle(angle) }
                    }
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(vm.shutterAngle == angle ? Theme.accent : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                vm.shutterAngle == angle ? Theme.accent.opacity(0.5) : Theme.rule,
                                lineWidth: Theme.ruleWidth
                            )
                    )
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
    }

    private func angleLabel(_ a: Double) -> String {
        a.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(a))°" : String(format: "%.1f°", a)
    }
}

// MARK: – YOLO info popover

struct YoloInfoPopover: View {
    let simulationMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow(label: "MODEL", value: "YOLOv8 Nano")
            HRule()
            infoRow(label: "MODE", value: simulationMode ? "SIM" : "LIVE")
            HRule()
            infoRow(label: "DET FPS", value: "4.0")
            HRule()
            infoRow(label: "THRESHOLD", value: "0.72")
        }
        .padding(14)
        .background(Theme.cardBackground)
        .frame(width: 200)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
