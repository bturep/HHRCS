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

    @State private var currentPage       = CameraPage.still
    @State private var showISOPopover    = false
    @State private var showWBPopover     = false
    @State private var showShutterPopover = false
    @State private var showYoloPopover   = false

    @StateObject private var mjpegPlayer = MJPEGPlayer(
        url: URL(string: "http://raspberrypi.local:5001/stream")!
    )

    private var isLandscape: Bool { orientationObserver.orientation.isLandscape }

    private var streamURL: URL {
        if !settings.piServerURL.isEmpty,
           var c = URLComponents(string: settings.piServerURL),
           c.host != nil {
            c.path  = "/stream"
            c.query = nil
            if let url = c.url { return url }
        }
        return URL(string: "http://raspberrypi.local:5001/stream")!
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            TabView(selection: $currentPage) {
                StillFrameView()
                    .padding(.top, 32)
                    .padding(.bottom, 54)
                    .tag(CameraPage.still)

                MJPEGStreamView(player: mjpegPlayer)
                    .onAppear {
                        print("[MJPEG] CAM page appeared url=\(streamURL)")
                        mjpegPlayer.streamURL = streamURL
                        mjpegPlayer.start()
                    }
                    .onDisappear {
                        print("[MJPEG] CAM page disappeared — stopping")
                        mjpegPlayer.stop()
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 54)
                    .tag(CameraPage.live)

                DetectionOverlayView(player: mjpegPlayer)
                    .onAppear {
                        print("[MJPEG] DETECT page appeared url=\(streamURL)")
                        mjpegPlayer.streamURL = streamURL
                        mjpegPlayer.start()
                    }
                    .onDisappear {
                        print("[MJPEG] DETECT page disappeared — stopping")
                        mjpegPlayer.stop()
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 54)
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
                        captureIsPlaceholder: true,
                        onRecord: { Task { await vm.toggleBmpccRecord() } },
                        onCapture: { Task { await vm.captureBmpccStill() } }
                    ) { pageIndicator }
                case .live:
                    OperatorControlRow(
                        isOwner: settings.ownerModeEnabled,
                        isRecording: vm.isPiCamRecording,
                        captureIsPlaceholder: false,
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
        .onChange(of: streamURL) { _, url in
            mjpegPlayer.streamURL = url
            if currentPage == .live {
                mjpegPlayer.stop()
                mjpegPlayer.start()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                if currentPage == .live || currentPage == .detection {
                    mjpegPlayer.streamURL = streamURL
                    mjpegPlayer.start()
                }
            } else {
                mjpegPlayer.stop()
            }
        }
    }

    // MARK: – Data bar (BMPCC page only)

    private var stillDataBar: some View {
        HStack(spacing: 0) {
            // AUTO badge — visible only when YOLO has triggered a recording
            if vm.yoloLocked && vm.isRecording {
                Text("AUTO")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 10)
            }

            // ISO
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

            // WB
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

            // Shutter
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

    // MARK: – Detection bottom bar (just the page indicator)

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

// MARK: – Shared operator control row (STILL + CAM)

private struct OperatorControlRow<Indicator: View>: View {
    let isOwner: Bool
    let isRecording: Bool
    let captureIsPlaceholder: Bool
    let onRecord: () -> Void
    let onCapture: () -> Void
    @ViewBuilder let indicator: () -> Indicator

    @State private var captureFlash = false

    var body: some View {
        ZStack {
            // 4-column grid matching the tab bar's equal layout
            HStack(spacing: 0) {
                Group {
                    if isOwner {
                        Button {
                            onRecord()
                        } label: {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 26))
                                .foregroundStyle(isRecording ? Theme.recordingRed : Theme.tertiary)
                        }
                        .buttonStyle(.plain)
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
