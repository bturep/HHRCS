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
                VStack(spacing: 8) {
                    if currentPage == .live {
                        operationalControls
                    }
                    pageIndicator
                }
                .padding(.bottom, 10)
            }
        }
        // HUD strip — top of CAM page only
        .overlay(alignment: .top) {
            if currentPage == .live {
                hudStrip
            }
        }
        // Config sheet button — top left, owner mode + live page only
        .overlay(alignment: .topLeading) {
            if currentPage == .live && settings.ownerModeEnabled {
                Button { showControlSheet = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(16)
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

    // MARK: – HUD strip

    private var hudStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                if vm.isRecording {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
                Text(vm.isRecording ? "REC" : "IDLE")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(
                        vm.isRecording ? Theme.accent.opacity(0.9) : Color.white.opacity(0.8)
                    )
            }
            Text(vm.recordingDurationString)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            Spacer()
            Text(hudLuxLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            Text(String(format: "EV%.1f", vm.ev))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            Text(hudNDLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            Text("ISO\(vm.iso)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .frame(maxWidth: .infinity)
    }

    private var hudLuxLabel: String {
        vm.lux >= 1000
            ? String(format: "%.1fklx", vm.lux / 1000)
            : String(format: "%.0flx", vm.lux)
    }

    private var hudNDLabel: String {
        vm.ndPosition == 0 ? "CLEAR" : "ND\(vm.ndPosition)"
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

    // MARK: – Operational controls (CAM page — record toggle only)

    private var operationalControls: some View {
        Button {
            Task { await vm.toggleRecord() }
        } label: {
            Image(systemName: vm.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 28))
                .foregroundStyle(vm.isRecording ? Theme.accent : Color.white.opacity(0.35))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 24)
        .background(Theme.background.opacity(0.75))
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
        .padding(.vertical, 6)
        .background(Theme.background.opacity(0.85))
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
