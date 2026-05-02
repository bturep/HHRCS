import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var vm: DataViewModel
    @ObservedObject private var settings = AppSettings.shared

    private enum DeploymentField: Hashable { case name, position, latitude, longitude }
    @FocusState private var deploymentFocus: DeploymentField?

    @State private var latText = ""
    @State private var lngText = ""
    @State private var isEditingAPIKey = false
    @State private var showAddURL      = false
    @State private var newURLDraft     = ""

    @State private var isRestartingHhrcs    = false
    @State private var isRestartingDetector = false
    @State private var showLog:   Bool           = false
    @State private var activeDot: DiagnosticDot? = nil

    @State private var piDepActive        = false
    @State private var piDepID            = ""
    @State private var piDepName          = ""
    @State private var piDepPosition      = ""
    @State private var piDepClipCount     = 0
    @State private var piDepStartedAt     = ""
    @State private var isLoadingDep       = false
    @State private var showNewDepSheet    = false
    @State private var showCloseDepSheet  = false

    private static let pollTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    @State private var showOwnerUnlock    = false
    @State private var showOwnerPWChange  = false
    @State private var newOwnerPW         = ""
    @State private var confirmOwnerPW     = ""
    @State private var ownerPWChangeMsg   = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                diagnosticCard
                deploymentCard
                accessCard
                systemCard
                agentCard
                notificationsCard
                versionRow
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .clipShape(BottomRoundedRectangle(radius: Theme.cardRadius))
        .onAppear {
            latText = String(format: "%.6f", settings.latitude)
            lngText = String(format: "%.6f", settings.longitude)
            Task { await pollDeploymentStatus() }
        }
    }

    // MARK: – Version row

    private var versionRow: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "—"
        return Text("Version \(v) (build \(b))")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    // MARK: – DIAGNOSTIC

    private var diagnosticCard: some View {
        SectionCard(title: "DIAGNOSTIC") {
            VStack(spacing: 0) {
                Text(systemAdvisory.text)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(systemAdvisory.color)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HStack(spacing: 0) {
                    diagnosticDotButton(.pi,     status: vm.healthPiReachable ? .green : .red)
                    diagnosticDotButton(.bridge, status: vm.healthBridgeReachable ? .green : .red)
                    diagnosticDotButton(.ble,    status: vm.healthBleConnected ? .green : .red)
                    diagnosticDotButton(.yolo,   status: yoloStatus)
                    diagnosticDotButton(.ssd,    status: ssdStatus)
                }

                if let dot = activeDot {
                    HRule()
                    dotDetailPanel(dot)
                } else if showLog {
                    HRule()
                    logPanelView
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLog.toggle()
                        if showLog { activeDot = nil }
                    }
                } label: {
                    Image(systemName: showLog ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLog)
        .animation(.easeInOut(duration: 0.2), value: activeDot)
    }

    @ViewBuilder
    private func diagnosticDotButton(_ dot: DiagnosticDot, status: HealthStatus) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if activeDot == dot {
                    activeDot = nil
                } else {
                    activeDot = dot
                    showLog = false
                }
            }
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(dot.rawValue)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dotDetailPanel(_ dot: DiagnosticDot) -> some View {
        switch dot {
        case .pi:     PiDetailView().environmentObject(vm)
        case .bridge: BridgeDetailView().environmentObject(vm)
        case .ble:    BleDetailView().environmentObject(vm)
        case .yolo:   YoloDetailView().environmentObject(vm)
        case .ssd:    SsdDetailView().environmentObject(vm)
        }
    }

    private var logPanelView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EventLogFilter.allCases, id: \.self) { filter in
                        Button { vm.eventLogFilter = filter } label: {
                            Text(filter.rawValue)
                                .font(Theme.dataLabel(size: 9))
                                .foregroundStyle(vm.eventLogFilter == filter
                                    ? Theme.background : Theme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(vm.eventLogFilter == filter ? Theme.accent : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .stroke(
                                        vm.eventLogFilter == filter ? Theme.accent : Theme.tertiary,
                                        lineWidth: 0.5
                                    ))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            if vm.filteredEventLog.isEmpty {
                Text(vm.healthPiReachable ? "No events in window" : "Pi unreachable")
                    .font(Theme.bodyMono(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.filteredEventLog) { line in
                            DiagnosticEventRow(line: line)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }

    private var systemAdvisory: (text: String, color: Color) {
        if !vm.healthPiReachable {
            return ("PI UNREACHABLE · ALL SYSTEMS OFFLINE", Theme.recordingRed)
        }
        if !vm.healthBridgeReachable {
            return ("BRIDGE OFFLINE · BLE AND CAMERA UNAVAILABLE", Theme.recordingRed)
        }
        if vm.healthEsp32BleState != "Connected" {
            return ("BLE DISCONNECTED · TAP BLE TO RECOVER", Theme.accentOrange)
        }
        if vm.healthYoloSimMode || !vm.healthYoloRunning {
            return ("DETECTOR IN SIM MODE · TAP YOLO TO RESET", Theme.accentOrange)
        }
        return ("ALL SYSTEMS NOMINAL", Theme.tertiary)
    }

    private var yoloStatus: HealthStatus {
        guard vm.healthPiReachable else { return .grey }
        if !vm.healthYoloRunning { return .red }
        return vm.healthYoloSimMode ? .yellow : .green
    }

    private var ssdStatus: HealthStatus {
        guard vm.healthSsdMounted else { return .red }
        if vm.healthSsdFreePct < 5  { return .red }
        if vm.healthSsdFreePct < 10 { return .yellow }
        return .green
    }

    // MARK: – DEPLOYMENT

    private var deploymentCard: some View {
        SectionCard(title: "DEPLOYMENT") {
            VStack(spacing: 0) {
                deploymentField(label: "SITE") {
                    TextField("Hunter House", text: $settings.deploymentName)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .submitLabel(.next)
                        .focused($deploymentFocus, equals: .name)
                }

                deploymentField(label: "POSITION") {
                    TextField("e.g. North Meadow facing NE", text: $settings.positionName)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .submitLabel(.next)
                        .focused($deploymentFocus, equals: .position)
                }

                deploymentField(label: "LATITUDE") {
                    TextField("48.515000", text: $latText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(deploymentFocus == .latitude ? .white : Color(Theme.secondary))
                        .tint(Theme.accent)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.next)
                        .focused($deploymentFocus, equals: .latitude)
                        .onSubmit { commitCoords() }
                        .onChange(of: latText) { _, _ in commitCoords() }
                }

                deploymentField(label: "LONGITUDE") {
                    TextField("-123.408000", text: $lngText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(deploymentFocus == .longitude ? .white : Color(Theme.secondary))
                        .tint(Theme.accent)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.next)
                        .focused($deploymentFocus, equals: .longitude)
                        .onSubmit { commitCoords() }
                        .onChange(of: lngText) { _, _ in commitCoords() }
                }

                Text("Prospect Lake, Saanich  ·  \(String(format: "%.4f", settings.latitude)), \(String(format: "%.4f", settings.longitude))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)

                HRule()

                // URL selector
                VStack(alignment: .leading, spacing: 0) {
                    Text("URL")
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.bottom, 6)

                    ForEach(settings.savedServerURLs, id: \.self) { url in
                        Button {
                            settings.piServerURL = url
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(settings.piServerURL == url ? Theme.accentOrange : Color.clear)
                                    .overlay(Circle().stroke(
                                        settings.piServerURL == url ? Theme.accentOrange : Theme.tertiary,
                                        lineWidth: 1))
                                    .frame(width: 6, height: 6)
                                Text(url)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(settings.piServerURL == url ? Theme.secondary : Theme.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        HRule()
                    }

                    if showAddURL {
                        HStack(spacing: 10) {
                            TextField("http://", text: $newURLDraft)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white)
                                .tint(Theme.accent)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .submitLabel(.done)
                                .onSubmit { saveNewURL() }
                            Button("SAVE") { saveNewURL() }
                                .font(Theme.dataLabel(size: 9))
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Theme.accent)
                                .buttonStyle(.plain)
                            Button("CANCEL") { newURLDraft = ""; showAddURL = false }
                                .font(Theme.dataLabel(size: 9))
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Theme.tertiary)
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 7)
                        HRule()
                    } else {
                        Button("+ ADD") { showAddURL = true }
                            .font(Theme.dataLabel(size: 9))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                            .padding(.vertical, 7)
                        HRule()
                    }
                }
                .padding(.top, 4)

                // Pi deployment status
                piDeploymentSection
            }
        }
        .sheet(isPresented: $showNewDepSheet) {
            NewDeploymentSheet(isPresented: $showNewDepSheet) {
                Task {
                    await pollDeploymentStatus()
                    vm.resetForNewDeployment()
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCloseDepSheet) {
            CloseDeploymentSheet(
                isPresented: $showCloseDepSheet,
                deploymentName: piDepName
            ) { notes in
                Task { await closeDeployment(notes: notes) }
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var piDeploymentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HRule()
                .padding(.top, 12)
            HStack {
                Button("NEW DEPLOYMENT") { showNewDepSheet = true }
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.accentOrange)
                    .buttonStyle(.plain)
                Spacer()
                if piDepActive {
                    Button("CLOSE") { showCloseDepSheet = true }
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.accentOrange)
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func deploymentField<F: View>(label: String, @ViewBuilder content: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            content()
            HRule()
        }
        .padding(.bottom, 10)
    }

    // MARK: – ACCESS

    private var accessCard: some View {
        SectionCard(title: "ACCESS") {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text(settings.ownerModeEnabled ? "Active" : "Locked")
                        .font(Theme.dataLabel(size: 11))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(settings.ownerModeEnabled ? Theme.accent : Theme.tertiary)
                    Spacer()
                    if settings.ownerModeEnabled {
                        Button("LOCK") { settings.lockOwnerMode() }
                            .font(Theme.dataLabel(size: 9))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.secondary)
                            .buttonStyle(.plain)
                    } else {
                        Button("UNLOCK") { showOwnerUnlock = true }
                            .font(Theme.dataLabel(size: 9))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)

                if settings.ownerModeEnabled {
                    HRule()
                    Button(action: { showOwnerPWChange.toggle(); ownerPWChangeMsg = "" }) {
                        HStack {
                            Text("CHANGE PASSWORD")
                                .font(Theme.dataLabel())
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Theme.secondary)
                            Spacer()
                            Image(systemName: showOwnerPWChange ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.tertiary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if showOwnerPWChange {
                        HRule()
                        VStack(spacing: 8) {
                            PINField(label: "NEW PIN", text: $newOwnerPW)
                            HRule()
                            PINField(label: "CONFIRM", text: $confirmOwnerPW)
                            if !ownerPWChangeMsg.isEmpty {
                                Text(ownerPWChangeMsg)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(ownerPWChangeMsg == "Password updated"
                                        ? Theme.accent : Theme.tertiary)
                            }
                            Button(action: commitOwnerPWChange) {
                                Text("UPDATE")
                                    .font(Theme.dataLabel())
                                    .tracking(Theme.labelTracking)
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .overlay(RoundedRectangle(cornerRadius: 3)
                                        .stroke(Theme.accent.opacity(0.4), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            }
        }
        .sheet(isPresented: $showOwnerUnlock) {
            OwnerUnlockSheet(isPresented: $showOwnerUnlock)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: – SYSTEM

    private var systemCard: some View {
        SectionCard(title: "SYSTEM") {
            VStack(spacing: 0) {
                ToggleRow(label: "SIMULATION MODE",     isOn: $settings.simulationMode)
                HRule()
                ToggleRow(label: "DAWN / DUSK WINDOWS", isOn: $settings.dawnDuskWindows)
                HRule()
                ToggleRow(label: "DETECTION TRIGGER",   isOn: $settings.detectionTrigger)
                HRule()
                ToggleRow(label: "PUSH NOTIFICATIONS",  isOn: $settings.pushNotificationsEnabled, onChange: { enabled in
                    if enabled {
                        NotificationManager.shared.requestPermission()
                        if settings.simulationMode {
                            NotificationManager.shared.scheduleSimulatedDetection(
                                deploymentName: settings.deploymentName,
                                positionName: settings.positionName
                            )
                        }
                    }
                })
                HRule()
                ToggleRow(label: "30-MIN STILLS",       isOn: $settings.thirtyMinStills)
                HRule()
                ToggleRow(
                    label:    "PI AGENT LOG",
                    subtitle: "Show autonomous observations in Log",
                    isOn:     $settings.piAgentLogEnabled
                )
            }
        }
    }

    private func saveNewURL() {
        let trimmed = newURLDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.savedServerURLs.contains(trimmed) else {
            newURLDraft = ""; showAddURL = false; return
        }
        settings.savedServerURLs.append(trimmed)
        settings.piServerURL = trimmed
        newURLDraft = ""
        showAddURL = false
    }

    private func restartHhrcs() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/system/restart-hhrcs") else { return }
        isRestartingHhrcs = true
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        isRestartingHhrcs = false
    }

    private func restartDetector() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/system/restart-detector") else { return }
        isRestartingDetector = true
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        isRestartingDetector = false
    }

    // MARK: – NOTIFICATIONS

    private var notificationsCard: some View {
        SectionCard(title: "NOTIFICATIONS") {
            VStack(spacing: 0) {
                ToggleRow(label: "RECORDING & STILLS", isOn: $settings.notifyRecording)
                HRule()
                ToggleRow(label: "ANIMAL DETECTIONS",  isOn: $settings.notifyDetections)
                HRule()
                ToggleRow(label: "DEPLOYMENTS",        isOn: $settings.notifyDeployments)
            }
        }
    }

    // MARK: – AGENT

    private var agentCard: some View {
        SectionCard(title: "AGENT") {
            VStack(alignment: .leading, spacing: 5) {
                Text("API KEY")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.tertiary)
                HStack(spacing: 10) {
                    if isEditingAPIKey {
                        TextField("sk-ant-...", text: $settings.anthropicAPIKey)
                            .font(Theme.dataValueText(size: 14))
                            .foregroundColor(.white)
                            .tint(Theme.accent)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { isEditingAPIKey = false }
                    } else {
                        Text(settings.anthropicAPIKey.isEmpty ? "not set" : maskedKey(settings.anthropicAPIKey))
                            .font(Theme.dataValueText(size: 14))
                            .foregroundStyle(settings.anthropicAPIKey.isEmpty ? Theme.tertiary : Theme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Button(isEditingAPIKey ? "DONE" : "EDIT") { isEditingAPIKey.toggle() }
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
                HRule()
            }
        }
    }

    // MARK: – Helpers

    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(7))...\(key.suffix(4))"
    }

    private func pollDeploymentStatus() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/deployments/active") else { return }
        isLoadingDep = true
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let active = json["active"] as? Bool ?? false
            if active, let dep = json["deployment"] as? [String: Any] {
                piDepActive    = true
                piDepID        = dep["id"] as? String ?? ""
                piDepName      = dep["name"] as? String ?? ""
                piDepPosition  = dep["position"] as? String ?? ""
                piDepClipCount = dep["clip_count"] as? Int ?? 0
                piDepStartedAt = dep["started_at"] as? String ?? ""
            } else {
                piDepActive = false
                piDepID = ""; piDepName = ""; piDepPosition = ""
                piDepClipCount = 0; piDepStartedAt = ""
            }
        }
        isLoadingDep = false
    }

    private func closeDeployment(notes: String = "") async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/deployments/close") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !notes.isEmpty {
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["notes": notes])
        }
        req.timeoutInterval = 8
        _ = try? await URLSession.shared.data(for: req)
        await pollDeploymentStatus()
    }

    private func commitCoords() {
        if let d = Double(latText) { settings.latitude  = d }
        if let d = Double(lngText) { settings.longitude = d }
    }

    private func commitOwnerPWChange() {
        guard newOwnerPW.count == 4, newOwnerPW.allSatisfy(\.isNumber) else {
            ownerPWChangeMsg = "PIN must be 4 digits"; return
        }
        guard newOwnerPW == confirmOwnerPW else {
            ownerPWChangeMsg = "PINs do not match"; return
        }
        settings.ownerPassword = newOwnerPW
        newOwnerPW = ""; confirmOwnerPW = ""
        ownerPWChangeMsg = "Password updated"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showOwnerPWChange = false; ownerPWChangeMsg = ""
        }
    }

}

// MARK: – New deployment sheet

private struct NewDeploymentSheet: View {
    @Binding var isPresented: Bool
    let onCreated: () -> Void

    @State private var name     = ""
    @State private var position = ""
    @State private var lat      = ""
    @State private var lng      = ""
    @State private var bearing  = ""
    @State private var notes    = ""
    @State private var isPosting = false
    @State private var errorMsg  = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("NEW DEPLOYMENT")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    Button("CANCEL") { isPresented = false }
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.secondary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, 16)

                HRule().padding(.horizontal, Theme.pagePadding)

                ScrollView {
                    VStack(spacing: 0) {
                        newDepField(label: "SITE") {
                            TextField("Hunter House", text: $name)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                        }
                        newDepField(label: "POSITION") {
                            TextField("e.g. North Meadow facing NE", text: $position)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                        }
                        newDepField(label: "LATITUDE") {
                            TextField("48.515000", text: $lat)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        newDepField(label: "LONGITUDE") {
                            TextField("-123.408000", text: $lng)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        newDepField(label: "BEARING") {
                            TextField("e.g. 045 (optional)", text: $bearing)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        newDepField(label: "NOTES") {
                            TextField("Optional notes", text: $notes, axis: .vertical)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white).tint(Theme.accent)
                                .lineLimit(1...3)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
                }

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 8)
                }

                HRule().padding(.horizontal, Theme.pagePadding)

                Button { Task { await submit() } } label: {
                    Text(isPosting ? "Creating…" : "CREATE DEPLOYMENT")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(canSubmit ? Theme.accentOrange : Theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .onAppear {
            name     = AppSettings.shared.deploymentName
            position = AppSettings.shared.positionName
            lat      = String(format: "%.6f", AppSettings.shared.latitude)
            lng      = String(format: "%.6f", AppSettings.shared.longitude)
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isPosting
    }

    @ViewBuilder
    private func newDepField<F: View>(label: String, @ViewBuilder content: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            content()
            HRule()
        }
        .padding(.bottom, 10)
    }

    private func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/deployments") else {
            errorMsg = "Pi URL not configured"; return
        }
        isPosting = true
        errorMsg = ""
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var payload: [String: Any] = [
            "name":        trimmed,
            "position":    position.trimmingCharacters(in: .whitespaces),
            "notes":       notes.trimmingCharacters(in: .whitespaces),
            "app_version": appVersion,
        ]
        if let d = Double(lat)     { payload["lat"]     = d }
        if let d = Double(lng)     { payload["lng"]     = d }
        if let d = Double(bearing) { payload["bearing"] = d }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 10
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 201 {
            isPresented = false
            onCreated()
        } else {
            errorMsg = "Failed — check Pi connection"
        }
        isPosting = false
    }
}

// MARK: – Toggle row

private struct ToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.secondary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.accent)
                .scaleEffect(0.75)
                .frame(width: 38, height: 24)
                .onChange(of: isOn) { _, v in onChange?(v) }
        }
        .padding(.vertical, 8)
    }
}

// MARK: – Owner unlock sheet (numpad)

private struct OwnerUnlockSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    @Binding var isPresented: Bool

    @State private var pinEntry = ""
    @State private var pinShake: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 36) {
                Spacer()

                Text("OWNER MODE")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.headerTracking)
                    .foregroundStyle(Theme.cardLabel)

                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < pinEntry.count ? Theme.accent : Theme.rule)
                            .frame(width: 10, height: 10)
                    }
                }
                .offset(x: pinShake)

                VStack(spacing: 10) {
                    ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.first!) { row in
                        HStack(spacing: 10) {
                            ForEach(row, id: \.self) { digit in
                                numKey(label: "\(digit)") { appendPIN("\(digit)") }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 80, height: 52)
                        numKey(label: "0") { appendPIN("0") }
                        Button(action: deletePIN) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 80, height: 52)
                                .background(Theme.cardBackground)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(Theme.pagePadding)
        }
    }

    private func numKey(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 80, height: 52)
                .background(Theme.cardBackground)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func appendPIN(_ digit: String) {
        guard pinEntry.count < 4 else { return }
        pinEntry += digit
        if pinEntry.count == 4 {
            if settings.unlockOwnerMode(password: pinEntry) {
                isPresented = false
            } else {
                shakePIN()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pinEntry = "" }
            }
        }
    }

    private func deletePIN() {
        guard !pinEntry.isEmpty else { return }
        pinEntry.removeLast()
    }

    private func shakePIN() {
        let spring = Animation.spring(response: 0.12, dampingFraction: 0.3)
        withAnimation(spring) { pinShake = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(spring) { pinShake = -8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(spring) { pinShake = 0 }
            }
        }
    }
}

// MARK: – Diagnostic event log row

private struct DiagnosticEventRow: View {
    let line: EventLogLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.time)
                .font(Theme.bodyMono(size: 11))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 58, alignment: .leading)
            Text(line.label)
                .font(Theme.bodyMono(size: 11))
                .foregroundStyle(labelColor)
                .frame(width: 56, alignment: .leading)
            Text(line.body)
                .font(Theme.bodyMono(size: 11))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var labelColor: Color {
        switch line.label {
        case "TRIGGER", "REC": return Theme.accent
        case "ERROR":          return Theme.tertiary
        default:               return Theme.secondary
        }
    }
}

// MARK: – PIN entry field

private struct PINField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
                .frame(width: 64, alignment: .leading)
            SecureField("••••", text: $text)
                .font(Theme.dataValue(size: 17))
                .foregroundColor(.white)
                .tint(Theme.accent)
                .keyboardType(.numberPad)
        }
    }
}

// MARK: – Bottom-only rounded rectangle

private struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(
            center:     CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius:     radius,
            startAngle: .degrees(0),
            endAngle:   .degrees(90),
            clockwise:  false
        )
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(
            center:     CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius:     radius,
            startAngle: .degrees(90),
            endAngle:   .degrees(180),
            clockwise:  false
        )
        p.closeSubpath()
        return p
    }
}

// MARK: – Close deployment sheet

private struct CloseDeploymentSheet: View {
    @Binding var isPresented: Bool
    let deploymentName: String
    let onConfirm: (String) -> Void

    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        ZStack {
            Theme.cardBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("CLOSE DEPLOYMENT")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    Button("CANCEL") { isPresented = false }
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.secondary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, 16)

                HRule().padding(.horizontal, Theme.pagePadding)

                VStack(alignment: .leading, spacing: 6) {
                    Text(deploymentName)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("NOTES")
                        .font(Theme.dataLabel(size: 9))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 12)

                    TextField("Optional closing notes", text: $notes, axis: .vertical)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .tint(Theme.accentOrange)
                        .lineLimit(1...4)
                        .focused($notesFocused)
                        .padding(10)
                        .background(Theme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Theme.accentOrange, lineWidth: 1)
                        )
                }
                .padding(.horizontal, Theme.pagePadding)

                Spacer()

                HRule().padding(.horizontal, Theme.pagePadding)

                Button {
                    let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    onConfirm(trimmed)
                    isPresented = false
                } label: {
                    Text("CONFIRM CLOSE")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Theme.accentOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
