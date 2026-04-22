import SwiftUI

struct SettingsTabView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var latText = ""
    @State private var lngText = ""
    @State private var isEditingURL = false

    // PIN change state
    @State private var showPINChange = false
    @State private var currentPINEntry = ""
    @State private var newPINEntry = ""
    @State private var confirmPINEntry = ""
    @State private var pinChangeMessage = ""

    // Owner mode state
    @State private var showOwnerUnlock      = false
    @State private var showOwnerPWChange    = false
    @State private var newOwnerPW           = ""
    @State private var confirmOwnerPW       = ""
    @State private var ownerPWChangeMsg     = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ownerModeSection
                deploymentSection
                coordinatesSection
                serverSection
                systemSection
                agentSection
                pinSection
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .onAppear {
            latText = String(format: "%.6f", settings.latitude)
            lngText = String(format: "%.6f", settings.longitude)
        }
    }

    // MARK: – Owner Mode
    private var ownerModeSection: some View {
        SectionCard(title: "OWNER MODE") {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text(settings.ownerModeEnabled ? "ACTIVE" : "LOCKED")
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
                            PINField(label: "NEW PIN",  text: $newOwnerPW)
                            HRule()
                            PINField(label: "CONFIRM",  text: $confirmOwnerPW)

                            if !ownerPWChangeMsg.isEmpty {
                                Text(ownerPWChangeMsg)
                                    .font(Theme.statusCaption(size: 11))
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
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Theme.accent.opacity(0.4), lineWidth: 0.5)
                                    )
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

    // MARK: – Deployment
    private var deploymentSection: some View {
        SectionCard(title: "DEPLOYMENT") {
            VStack(spacing: 0) {
                SettingsField(label: "NAME") {
                    TextField("HUNTER HOUSE", text: $settings.deploymentName)
                        .font(Theme.dataValueText(size: 20))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .submitLabel(.next)
                }
                SettingsField(label: "POSITION") {
                    TextField("POSITION 1", text: $settings.positionName)
                        .font(Theme.dataValueText(size: 17))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .submitLabel(.done)
                }
            }
        }
    }

    // MARK: – Coordinates
    private var coordinatesSection: some View {
        SectionCard(title: "COORDINATES") {
            VStack(spacing: 10) {
                SettingsField(label: "LATITUDE") {
                    TextField("48.515000", text: $latText)
                        .font(Theme.dataValueText(size: 17))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.next)
                        .onSubmit { commitCoords() }
                }

                HRule()

                SettingsField(label: "LONGITUDE") {
                    TextField("-123.408000", text: $lngText)
                        .font(Theme.dataValueText(size: 17))
                        .foregroundColor(.white)
                        .tint(Theme.accent)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .onSubmit { commitCoords() }
                }
                .onChange(of: latText) { _, _ in commitCoords() }
                .onChange(of: lngText) { _, _ in commitCoords() }

                Text("Prospect Lake, Saanich  ·  \(String(format: "%.4f", settings.latitude)), \(String(format: "%.4f", settings.longitude))")
                    .font(Theme.statusCaption(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: – Pi Server
    private var serverSection: some View {
        SectionCard(title: "PI SERVER") {
            VStack(alignment: .leading, spacing: 5) {
                Text("URL")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.tertiary)

                HStack(spacing: 10) {
                    if isEditingURL {
                        TextField("http://192.168.x.x:5000", text: $settings.piServerURL)
                            .font(Theme.dataValueText(size: 17))
                            .foregroundColor(.white)
                            .tint(Theme.accent)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { isEditingURL = false }
                    } else {
                        Text(settings.piServerURL.isEmpty ? "not set" : settings.piServerURL)
                            .font(Theme.dataValueText(size: 17))
                            .foregroundStyle(settings.piServerURL.isEmpty ? Theme.tertiary : .white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Button(isEditingURL ? "DONE" : "EDIT") {
                        isEditingURL.toggle()
                    }
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }
                HRule()
            }
        }
    }

    // MARK: – System toggles
    private var systemSection: some View {
        SectionCard(title: "SYSTEM") {
            VStack(spacing: 0) {
                ToggleRow(label: "SIMULATION MODE",        isOn: $settings.simulationMode)
                HRule()
                ToggleRow(label: "DAWN / DUSK WINDOWS",    isOn: $settings.dawnDuskWindows)
                HRule()
                ToggleRow(label: "DETECTION TRIGGER",      isOn: $settings.detectionTrigger)
                HRule()
                ToggleRow(label: "PUSH NOTIFICATIONS",     isOn: $settings.pushNotificationsEnabled, onChange: { enabled in
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
                ToggleRow(label: "30-MIN STILLS",          isOn: $settings.thirtyMinStills)
                HRule()
                ToggleRow(
                    label: "PI AGENT LOG",
                    subtitle: "Show autonomous observations in Log",
                    isOn: $settings.piAgentLogEnabled
                )
            }
        }
    }

    // MARK: – Agent
    @State private var isEditingAPIKey = false

    private var agentSection: some View {
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
                            .foregroundStyle(settings.anthropicAPIKey.isEmpty ? Theme.tertiary : .white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Button(isEditingAPIKey ? "DONE" : "EDIT") {
                        isEditingAPIKey.toggle()
                    }
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }
                HRule()
            }
        }
    }

    // MARK: – PIN
    private var pinSection: some View {
        SectionCard(title: "CONTROL PIN") {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: { showPINChange.toggle(); pinChangeMessage = "" }) {
                    HStack {
                        Text("CHANGE PIN")
                            .font(Theme.dataLabel())
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Image(systemName: showPINChange ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if showPINChange {
                    HRule()
                    VStack(spacing: 8) {
                        PINField(label: "CURRENT", text: $currentPINEntry)
                        HRule()
                        PINField(label: "NEW PIN", text: $newPINEntry)
                        HRule()
                        PINField(label: "CONFIRM", text: $confirmPINEntry)

                        if !pinChangeMessage.isEmpty {
                            Text(pinChangeMessage)
                                .font(Theme.statusCaption(size: 11))
                                .foregroundStyle(pinChangeMessage == "PIN updated" ? Theme.accent : Theme.tertiary)
                        }

                        Button(action: commitPINChange) {
                            Text("UPDATE")
                                .font(Theme.dataLabel())
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Theme.accent.opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: – Helpers
    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    private func commitCoords() {
        if let d = Double(latText) { settings.latitude  = d }
        if let d = Double(lngText) { settings.longitude = d }
    }

    private func commitPINChange() {
        guard currentPINEntry == settings.controlPIN else {
            pinChangeMessage = "Current PIN incorrect"; return
        }
        guard newPINEntry.count == 4, newPINEntry.allSatisfy(\.isNumber) else {
            pinChangeMessage = "PIN must be 4 digits"; return
        }
        guard newPINEntry == confirmPINEntry else {
            pinChangeMessage = "PINs do not match"; return
        }
        settings.controlPIN = newPINEntry
        currentPINEntry = ""; newPINEntry = ""; confirmPINEntry = ""
        pinChangeMessage = "PIN updated"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showPINChange = false; pinChangeMessage = ""
        }
    }
}

// MARK: – Settings field helper
private struct SettingsField<F: View>: View {
    let label: String
    @ViewBuilder let field: () -> F

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            field()
            HRule()
        }
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
                        .font(Theme.statusCaption(size: 10))
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
                .font(.system(size: 28, weight: .regular))
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
