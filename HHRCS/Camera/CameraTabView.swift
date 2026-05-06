import SwiftUI

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
                    poller:      hdmiPoller,
                    bins:        histogramPoller.bins,
                    clippedLow:  histogramPoller.clippedLow,
                    clippedHigh: histogramPoller.clippedHigh
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
        .onDisappear { camPoller.stop(); hdmiPoller.stop(); histogramPoller.stop() }
        .onChange(of: currentPage) { _, _ in rebalancePollers() }
        .onChange(of: isActive) { _, active in
            if active { startActivePoller() }
            else { camPoller.stop(); hdmiPoller.stop(); histogramPoller.stop() }
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
        } else {
            hdmiPoller.stop()
            histogramPoller.stop()
            camPoller.start()
        }
    }

    private func rebalancePollers() {
        switch currentPage {
        case .still:
            camPoller.stop()
            hdmiPoller.start()
            histogramPoller.start()
        case .live, .detection:
            hdmiPoller.stop()
            histogramPoller.stop()
            camPoller.start()
        }
    }

    private func updatePollerURLs() {
        hdmiPoller.triggerURL    = makeURL("/hdmi/still")
        hdmiPoller.fetchURL      = makeURL("/hdmi/stills/latest")
        camPoller.triggerURL     = makeURL("/still/trigger")
        camPoller.fetchURL       = makeURL("/stills/latest")
        histogramPoller.fetchURL = makeURL("/hdmi/histogram")
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

// MARK: – Still image page (used by BMPCC and CAM sub-pages)

private struct StillImagePage: View {
    @ObservedObject var poller: StillPoller
    var bins:        [Int]   = []
    var clippedLow:  Double  = 0
    var clippedHigh: Double  = 0

    @State private var showFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.background

                if let image = poller.latestImage {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .onTapGesture { showFullscreen = true }
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
                HStack(spacing: 10) {
                    if let updated = poller.lastUpdated {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let elapsed = Int(max(0, ctx.date.timeIntervalSince(updated)))
                            Text("\(elapsed)s")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(elapsed > 15
                                    ? Theme.tertiary.opacity(0.35)
                                    : Theme.tertiary)
                        }
                    }
                    Button { poller.refreshNow() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
            }

            if !bins.isEmpty {
                HistogramView(bins: bins, clippedLow: clippedLow, clippedHigh: clippedHigh)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(
                    image:       image,
                    isPresented: $showFullscreen,
                    bins:        bins,
                    clippedLow:  clippedLow,
                    clippedHigh: clippedHigh
                )
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(
                    image:       image,
                    isPresented: $showFullscreen,
                    bins:        bins,
                    clippedLow:  clippedLow,
                    clippedHigh: clippedHigh
                )
            }
        }
        #endif
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
