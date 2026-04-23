import SwiftUI

private enum CameraPage: Int, CaseIterable {
    case live       = 0
    case detection  = 1
    case still      = 2

    var label: String {
        switch self {
        case .live:      return "CAM"
        case .detection: return "DETECT"
        case .still:     return "STILL"
        }
    }
}

struct CameraTabView: View {
    @EnvironmentObject var vm: DataViewModel
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver
    @ObservedObject private var settings = AppSettings.shared

    @State private var currentPage      = CameraPage.live
    @State private var showControlSheet = false
    @State private var isStreamLive     = false
    @State private var showLivePopover  = false
    @State private var showYoloPopover  = false

    private var isLandscape: Bool { orientationObserver.orientation.isLandscape }

    private var streamURL: URL {
        let base = settings.streamBaseURL
        if !base.isEmpty, let url = URL(string: base + "/stream") { return url }
        return URL(string: "http://raspberrypi.local:8080/stream")!
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            TabView(selection: $currentPage) {
                MJPEGStreamView(streamURL: streamURL, onConnectionChange: { isStreamLive = $0 })
                    .id(settings.piServerURL)
                    .tag(CameraPage.live)

                DetectionOverlayView()
                    .tag(CameraPage.detection)

                StillFrameView()
                    .tag(CameraPage.still)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: isLandscape ? .all : .top)

            if !isLandscape {
                controlBar
            }
        }
        // Top HUD — adapts to current page
        .overlay(alignment: .top) {
            switch currentPage {
            case .live:      hudStrip
            case .detection: detectionHudStrip
            case .still:     EmptyView()
            }
        }
        // LIVE badge — top right, live page + connected
        .overlay(alignment: .topTrailing) {
            if currentPage == .live && isStreamLive {
                Button { showLivePopover = true } label: {
                    liveTag
                }
                .buttonStyle(.plain)
                .padding(12)
                .popover(isPresented: $showLivePopover) {
                    LiveInfoPopover(
                        isConnected: isStreamLive,
                        lastPollAt:  vm.lastPollAt,
                        streamURL:   streamURL.absoluteString
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showControlSheet) {
            ControlTabView()
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: – HUD strip (CAM page)
    // ZStack: left cluster | center gear | right cluster — gear is always at true center

    private var hudStrip: some View {
        ZStack {
            HStack(spacing: 6) {
                if vm.isRecording {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
                Text(vm.isRecording ? "REC" : "IDLE")
                    .foregroundStyle(vm.isRecording ? Theme.accent.opacity(0.9) : Color.white.opacity(0.8))
                Text(vm.recordingDurationString)
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer()
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)

            if settings.ownerModeEnabled {
                Button { showControlSheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                Spacer()
                Text(hudLuxLabel)
                Text(String(format: "EV%.1f", vm.ev))
                Text(hudNDLabel)
                Text("ISO \(String(vm.iso))")
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .frame(maxWidth: .infinity)
    }

    private var hudLuxLabel: String {
        vm.lux >= 1000
            ? String(format: "%.1fk lx", vm.lux / 1000)
            : String(format: "%.0f lx", vm.lux)
    }

    private var hudNDLabel: String {
        vm.ndPosition == 0 ? "CLEAR" : "ND\(vm.ndPosition)"
    }

    // MARK: – Detection HUD strip
    // ZStack: state+class left | YOLO badge center | timestamp right

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
                Text("YOLOv8  SIM")
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
        .background(Color.black.opacity(0.6))
        .frame(maxWidth: .infinity)
    }

    // MARK: – LIVE badge

    private var liveTag: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.background.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.accent.opacity(0.5), lineWidth: Theme.ruleWidth)
        )
    }

    // MARK: – Control bar
    // Left action button | [spacer] page indicator [spacer] | right action button
    // Both action slots are fixed 56pt wide so page indicator stays screen-centred.

    private var controlBar: some View {
        HStack(spacing: 0) {
            leftActionButton
                .frame(width: 56, height: 44)

            Spacer()
            pageIndicator
            Spacer()

            rightActionButton
                .frame(width: 56, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .background(Theme.background.opacity(0.85))
    }

    @ViewBuilder
    private var leftActionButton: some View {
        switch currentPage {
        case .live:
            Button {
                Task { await vm.toggleRecord() }
            } label: {
                Image(systemName: vm.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(vm.isRecording ? Theme.accent : Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        case .detection:
            // Phase 4: Pi cam record trigger — wired in Phase 4
            Button { } label: {
                Image(systemName: "video.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(true)
        case .still:
            Color.clear
        }
    }

    @ViewBuilder
    private var rightActionButton: some View {
        switch currentPage {
        case .live:
            Button {
                Task { await vm.triggerStill() }
            } label: {
                bmpccStillIcon
            }
            .buttonStyle(.plain)
        case .detection:
            // Phase 4: Pi cam still — wired in Phase 4
            Button { } label: {
                Image(systemName: "camera")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(true)
        case .still:
            Color.clear
        }
    }

    // Camera + bolt badge: distinguishes BMPCC still from Pi cam still
    private var bmpccStillIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "camera")
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.5))
            Image(systemName: "bolt.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.accent.opacity(0.85))
                .offset(x: 3, y: 2)
        }
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
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.accent, lineWidth: 0.5)
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

// MARK: – LIVE info popover

private struct LiveInfoPopover: View {
    let isConnected: Bool
    let lastPollAt:  Date
    let streamURL:   String

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow(label: "STATUS",     value: isConnected ? "CONNECTED" : "DISCONNECTED",
                    valueColor: isConnected ? Theme.accent : Theme.tertiary)
            HRule()
            infoRow(label: "LAST POLL",  value: Self.timeFmt.string(from: lastPollAt))
            HRule()
            infoRow(label: "UPTIME",     value: "—")
            HRule()
            infoRow(label: "STREAM URL", value: streamURL)
        }
        .padding(14)
        .background(Theme.cardBackground)
        .frame(width: 260)
    }

    private func infoRow(label: String, value: String,
                         valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: – YOLO info popover (used by detectionHudStrip)

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
