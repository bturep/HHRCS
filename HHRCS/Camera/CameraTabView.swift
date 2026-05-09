import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum CameraPage: Int, CaseIterable {
    case still = 0
    case live  = 1

    var label: String {
        switch self {
        case .still: return "BMPCC"
        case .live:  return "CAM"
        }
    }
}

private enum ActiveStrip {
    case iso, wb, shutter
}

struct CameraTabView: View {
    var isActive: Bool = true

    @EnvironmentObject var vm: DataViewModel
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver
    @ObservedObject private var settings = AppSettings.shared

    @State private var currentPage  = CameraPage.still
    @State private var activeStrip: ActiveStrip? = nil
    @State private var breatheOpacity: Double = 1.0

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
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLandscape {
                TabView(selection: $currentPage) {
                    StillImagePage(poller: hdmiPoller, recordingState: vm.recordingState)
                        .tag(CameraPage.still)
                    StillImagePage(poller: camPoller)
                        .tag(CameraPage.live)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    // Row 1 — tab strip: BMPCC / CAM left, refresh right
                    tabStripRow
                        .padding(.horizontal, Theme.pagePadding)
                        .frame(height: 32)

                    HRule()
                        .padding(.horizontal, Theme.pagePadding)

                    // Row 2 — control strip: record / ISO / WB / SHUTTER / still
                    controlStrip

                    HRule()

                    // Feed — fills remaining space; chip strips overlay bottom
                    ZStack(alignment: .bottom) {
                        TabView(selection: $currentPage) {
                            StillImagePage(poller: hdmiPoller, recordingState: vm.recordingState)
                                .tag(CameraPage.still)
                            StillImagePage(poller: camPoller)
                                .tag(CameraPage.live)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if activeStrip != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) { activeStrip = nil }
                                }
                            chipStripView
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal:   .move(edge: .bottom).combined(with: .opacity)
                                ))
                        }
                    }
                    .frame(maxHeight: .infinity)

                    HRule()
                }
            }
        }
        .background(Theme.background)
        .onAppear { startActivePoller() }
        .onDisappear { camPoller.stop(); hdmiPoller.stop() }
        .onChange(of: currentPage) { _, _ in
            activeStrip = nil
            rebalancePollers()
        }
        .onChange(of: isActive) { _, active in
            if active { startActivePoller() }
            else { camPoller.stop(); hdmiPoller.stop() }
        }
        .onChange(of: settings.piServerURL) { _, _ in updatePollerURLs() }
        .onChange(of: vm.recordingState) { _, state in
            if state == .finalizing {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breatheOpacity = 0.4
                }
            } else {
                breatheOpacity = 1.0
            }
        }
    }

    // MARK: – Poller lifecycle

    private func startActivePoller() {
        updatePollerURLs()
        if currentPage == .still {
            camPoller.stop()
            hdmiPoller.start()
        } else {
            hdmiPoller.stop()
            camPoller.start()
        }
    }

    private func rebalancePollers() {
        switch currentPage {
        case .still:
            camPoller.stop()
            hdmiPoller.start()
        case .live:
            hdmiPoller.stop()
            camPoller.start()
        }
    }

    private func updatePollerURLs() {
        hdmiPoller.triggerURL = makeURL("/hdmi/still")
        hdmiPoller.fetchURL   = makeURL("/hdmi/stills/latest")
        camPoller.triggerURL  = makeURL("/still/trigger")
        camPoller.fetchURL    = makeURL("/stills/latest")
    }

    // MARK: – Row 1: Tab strip + refresh

    private var tabStripRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                ForEach(CameraPage.allCases, id: \.rawValue) { page in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage = page }
                    } label: {
                        Text(page.label)
                            .font(Theme.label(size: 11))
                            .fontWeight(page == currentPage ? .semibold : .regular)
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(page == currentPage ? settings.activeColor : Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            Spacer()
            if currentPage == .still {
                refreshControl
            }
        }
    }

    // MARK: – Row 2: Control strip

    private var controlStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            switch currentPage {
            case .still:
                recordButtonView
                    .frame(maxWidth: .infinity)

                if settings.ownerModeEnabled {
                    isoButton.frame(maxWidth: .infinity)
                    wbButton.frame(maxWidth: .infinity)
                    shutterButton.frame(maxWidth: .infinity)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                }

                stillCaptureButton(for: .still)
                    .frame(maxWidth: .infinity)

            case .live:
                Spacer()
                stillCaptureButton(for: .live)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .background(Theme.background)
    }

    // Record button — fixed frame; FIN overlaid above, nothing shifts
    @ViewBuilder
    private var recordButtonView: some View {
        ZStack {
            Button(action: { Task { await vm.toggleBmpccRecord() } }) {
                Image(systemName: vm.recordingState == .recording ? "stop.circle.fill" : "record.circle")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 26))
                    .foregroundStyle(
                        vm.recordingState == .recording  ? Theme.recordingRed :
                        vm.recordingState == .finalizing ? Theme.text3 :
                        Theme.tertiary
                    )
                    .opacity(vm.recordingState == .finalizing ? breatheOpacity : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(vm.recordingState == .finalizing)
        }
        .frame(width: 36, height: 36)
        .overlay(alignment: .top) {
            if vm.recordingState == .finalizing {
                Text("FIN")
                    .font(Theme.label(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.text2)
                    .opacity(breatheOpacity)
                    .offset(y: -13)
            }
        }
    }

    // ISO tappable label — label above, value below
    private var isoButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeStrip = activeStrip == .iso ? nil : .iso
            }
        } label: {
            VStack(spacing: 1) {
                Text("ISO")
                    .font(Theme.label(size: 8))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.text2)
                Text("\(vm.iso)")
                    .font(Theme.label(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(activeStrip == .iso ? settings.activeColor : Theme.text1)
            }
        }
        .buttonStyle(.plain)
    }

    // WB tappable label — label / kelvin / preset name
    private var wbButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeStrip = activeStrip == .wb ? nil : .wb
            }
        } label: {
            VStack(spacing: 1) {
                Text("WB")
                    .font(Theme.label(size: 8))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.text2)
                Text("\(vm.wbKelvin)K")
                    .font(Theme.label(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(activeStrip == .wb ? settings.activeColor : Theme.text1)
                if !wbPresetName.isEmpty {
                    Text(wbPresetName)
                        .font(Theme.label(size: 8))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.text3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var wbPresetName: String {
        switch vm.wbKelvin {
        case 3200: return "TUNGSTEN"
        case 4000: return "FLUORO"
        case 5500: return "FLASH"
        case 5600: return "DAYLIGHT"
        case 6500: return "CLOUDY"
        case 7500: return "SHADE"
        default: return ""
        }
    }

    // SHUTTER tappable label — label above, value below
    private var shutterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeStrip = activeStrip == .shutter ? nil : .shutter
            }
        } label: {
            VStack(spacing: 1) {
                Text("SHUTTER")
                    .font(Theme.label(size: 8))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.text2)
                Text(shutterLabelText)
                    .font(Theme.label(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(activeStrip == .shutter ? settings.activeColor : Theme.text1)
            }
        }
        .buttonStyle(.plain)
    }

    private var shutterLabelText: String {
        let a = vm.shutterAngle
        return a.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(a))°"
            : String(format: "%.1f°", a)
    }

    // Refresh countdown + ↻ button (shown in tab strip row on BMPCC page)
    private var refreshControl: some View {
        HStack(spacing: 4) {
            if let updated = hdmiPoller.lastUpdated {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let elapsed = Int(max(0, ctx.date.timeIntervalSince(updated)))
                    Text("\(elapsed)s")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.text3)
                }
            }
            Button { hdmiPoller.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
        }
    }

    // Still capture button
    @ViewBuilder
    private func stillCaptureButton(for page: CameraPage) -> some View {
        if settings.ownerModeEnabled {
            StillCaptureButton {
                Task {
                    if page == .still {
                        await vm.captureHdmiStill()
                    } else {
                        await vm.captureStill()
                    }
                }
            }
        } else {
            Color.clear.frame(width: 28, height: 28)
        }
    }

    // MARK: – Chip strips (overlay bottom of feed)

    @ViewBuilder
    private var chipStripView: some View {
        switch activeStrip {
        case .iso:     isoChipStrip
        case .wb:      wbChipStrip
        case .shutter: shutterChipStrip
        case nil:      EmptyView()
        }
    }

    private var isoChipStrip: some View {
        let values = [100, 200, 400, 800, 1600, 3200, 6400, 12800]
        return chipStripContainer {
            ForEach(values, id: \.self) { v in
                chipButton(label: "\(v)", isActive: vm.iso == v) {
                    vm.iso = v
                    Task { await vm.setISO(v) }
                    withAnimation(.easeInOut(duration: 0.15)) { activeStrip = nil }
                }
            }
        }
    }

    private var wbChipStrip: some View {
        let presets: [(String, Int)] = [
            ("DAYLIGHT", 5600), ("CLOUDY", 6500), ("SHADE", 7500),
            ("TUNGSTEN", 3200), ("FLUORO", 4000), ("FLASH", 5500),
        ]
        return chipStripContainer {
            ForEach(presets, id: \.1) { name, kelvin in
                wbChipButton(name: name, kelvin: kelvin, isActive: vm.wbKelvin == kelvin) {
                    vm.wbKelvin = kelvin
                    Task { await vm.setWB(kelvin) }
                    withAnimation(.easeInOut(duration: 0.15)) { activeStrip = nil }
                }
            }
        }
    }

    private var shutterChipStrip: some View {
        let angles: [Double] = [45, 90, 135, 180, 270, 360]
        return chipStripContainer {
            ForEach(angles, id: \.self) { a in
                chipButton(label: "\(Int(a))°", isActive: vm.shutterAngle == a) {
                    vm.shutterAngle = a
                    Task { await vm.setShutterAngle(a) }
                    withAnimation(.easeInOut(duration: 0.15)) { activeStrip = nil }
                }
            }
        }
    }

    private func chipStripContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Theme.surface.opacity(0.98))
    }

    // Single-line chip (ISO, shutter)
    private func chipButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.label(size: 11))
                .fontWeight(isActive ? .semibold : .regular)
                .tracking(Theme.labelTracking)
                .foregroundStyle(isActive ? Theme.background : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? settings.activeColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.clear : Theme.rule, lineWidth: Theme.ruleWidth)
                )
        }
        .buttonStyle(.plain)
    }

    // Two-line chip for WB (preset name + kelvin)
    private func wbChipButton(name: String, kelvin: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(name)
                    .font(Theme.label(size: 9))
                    .fontWeight(isActive ? .semibold : .regular)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(isActive ? Theme.background : Theme.text2)
                Text("\(kelvin)K")
                    .font(Theme.label(size: 8))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(isActive ? Theme.background : Theme.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isActive ? settings.activeColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? Color.clear : Theme.rule, lineWidth: Theme.ruleWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Still image page (used by BMPCC and CAM sub-pages)

private struct StillImagePage: View {
    @ObservedObject var poller: StillPoller
    var recordingState: RecordingState = .idle
    @State private var showFullscreen  = false

    var body: some View {
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
                    Text("CONNECTING")
                        .font(Theme.dataLabel())
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if poller.isManual {
                Text("MANUAL")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 12)
                    .padding(.top, 6)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(image: image, isPresented: $showFullscreen)
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let image = poller.latestImage {
                FullscreenImageView(image: image, isPresented: $showFullscreen)
            }
        }
        #endif
    }
}

// MARK: – Still capture button

private struct StillCaptureButton: View {
    let action: () -> Void
    @State private var captureFlash = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.08)) { captureFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.08)) { captureFlash = false }
            }
            action()
        } label: {
            Image(systemName: "camera.aperture")
                .font(.system(size: 24))
                .foregroundStyle(captureFlash ? Theme.recordingRed : Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}
