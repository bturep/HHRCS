import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: – Panel state machine

enum DiagnosticPanelMode: Equatable {
    case closed
    case log
    case detail(DiagnosticDot)
}

enum DiagnosticDot: String, CaseIterable {
    case pi     = "PI"
    case bridge = "BRIDGE"
    case ble    = "BLE"
    case yolo   = "YOLO"
    case ssd    = "SSD"
}

// MARK: – Recovery step model

enum StepResult {
    case pass(String)
    case fail(String)
}

struct RecoveryStep {
    let label:  String
    let action: () async -> StepResult
}

// MARK: – Recovery flow view

struct RecoveryFlowView: View {
    let title:  String
    let steps:  [RecoveryStep]
    let onBack: () -> Void

    @State private var states: [StepState] = []
    @State private var isDone = false

    fileprivate enum StepState: Equatable {
        case pending
        case running
        case success(String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Theme.accentOrange)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps.indices, id: \.self) { i in
                    let state = states.indices.contains(i) ? states[i] : StepState.pending
                    HStack(spacing: 10) {
                        stepIndicator(state)
                        Text(steps[i].label)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(labelColor(state))
                        Spacer()
                        stepStatus(state)
                    }
                }
            }
            .padding(.bottom, 12)

            if isDone {
                Button(action: onBack) {
                    Text("← BACK")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            states = Array(repeating: .pending, count: steps.count)
            Task { await runFlow() }
        }
    }

    @ViewBuilder
    private func stepIndicator(_ state: StepState) -> some View {
        switch state {
        case .pending:
            Circle()
                .stroke(Theme.tertiary, lineWidth: 1)
                .frame(width: 8, height: 8)
        case .running:
            Circle()
                .fill(Theme.accentOrange)
                .frame(width: 8, height: 8)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.32))
                .frame(width: 8, height: 8)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(red: 0.75, green: 0.25, blue: 0.20))
                .frame(width: 8, height: 8)
        }
    }

    private func labelColor(_ state: StepState) -> Color {
        switch state {
        case .pending:          return Theme.tertiary
        case .running:          return Theme.accentOrange
        case .success, .failed: return Theme.secondary
        }
    }

    @ViewBuilder
    private func stepStatus(_ state: StepState) -> some View {
        switch state {
        case .success(let msg):
            Text(msg)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.75, green: 0.25, blue: 0.20))
                .lineLimit(1)
        default:
            EmptyView()
        }
    }

    private func runFlow() async {
        for i in steps.indices {
            states[i] = .running
            switch await steps[i].action() {
            case .pass(let msg):
                states[i] = .success(msg)
            case .fail(let msg):
                states[i] = .failed(msg)
                isDone = true
                return
            }
        }
        isDone = true
    }
}

// MARK: – PI detail

struct PiDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone   = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            diagRow("STATUS",
                    value:      vm.healthPiReachable ? "Reachable" : "Unreachable",
                    valueColor: vm.healthPiReachable ? Theme.accent : Color(red: 0.75, green: 0.25, blue: 0.20))
            HRule()
            diagRow("LAST POLL",
                    value:      vm.healthLastPollAt.map { Self.fmt.string(from: $0) } ?? "—",
                    valueColor: Theme.secondary)
            HRule()
            Text("PHYSICAL ACCESS REQUIRED FOR HARDWARE RESET")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
    }
}

// MARK: – Bridge detail

struct BridgeDetailView: View {
    @EnvironmentObject var vm: DataViewModel
    @State private var showingRecovery = false

    var body: some View {
        VStack(spacing: 0) {
            if showingRecovery {
                RecoveryFlowView(title: "RESTART BRIDGE",
                                 steps: bridgeSteps(),
                                 onBack: { showingRecovery = false })
            } else {
                diagRow("BRIDGE",
                        value:      vm.healthBridgeReachable ? "Reachable" : "Unreachable",
                        valueColor: vm.healthBridgeReachable ? Theme.accent : Color(red: 0.75, green: 0.25, blue: 0.20))
                HRule()
                diagRow("BLE STATE",
                        value:      vm.healthEsp32BleState,
                        valueColor: vm.healthBleConnected ? Theme.accent : Theme.secondary)
                HRule()
                diagRecoveryButton("RESTART BRIDGE") { showingRecovery = true }
            }
        }
    }

    private func bridgeSteps() -> [RecoveryStep] {
        let base = AppSettings.shared.piServerURL
        return [
            RecoveryStep(label: "RESTARTING BRIDGE SERVICE") {
                guard let url = URL(string: base + "/system/restart-bridge") else { return .fail("Bad URL") }
                var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 8
                _ = try? await URLSession.shared.data(for: req)
                return .pass("Sent")
            },
            RecoveryStep(label: "WAITING FOR BRIDGE") {
                for _ in 0..<16 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if vm.healthBridgeReachable { return .pass("Reachable") }
                }
                return .fail("Timeout")
            },
            RecoveryStep(label: "WAITING FOR BLE") {
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if vm.healthBleConnected { return .pass("Connected") }
                }
                return .fail("BLE not connecting")
            },
            RecoveryStep(label: "VERIFYING") {
                await vm.refreshHealth()
                if vm.healthBridgeReachable && vm.healthBleConnected { return .pass("All clear") }
                return vm.healthBridgeReachable ? .fail("BLE not connected") : .fail("Bridge still down")
            },
        ]
    }
}

// MARK: – BLE / ESP32 detail

struct BleDetailView: View {
    @EnvironmentObject var vm: DataViewModel
    @State private var showingRecovery = false

    var body: some View {
        VStack(spacing: 0) {
            if showingRecovery {
                RecoveryFlowView(title: "RECOVER ESP32",
                                 steps: bleSteps(),
                                 onBack: { showingRecovery = false })
            } else {
                diagRow("BLE STATE",
                        value:      vm.healthEsp32BleState,
                        valueColor: vm.healthBleConnected ? Theme.accent : Color(red: 0.75, green: 0.25, blue: 0.20))
                HRule()
                diagRow("BRIDGE",
                        value:      vm.healthBridgeReachable ? "Reachable" : "Unreachable",
                        valueColor: vm.healthBridgeReachable ? Theme.accent : Theme.secondary)
                HRule()
                diagRecoveryButton("RECOVER ESP32") { showingRecovery = true }
            }
        }
    }

    private func bleSteps() -> [RecoveryStep] {
        let base = AppSettings.shared.piServerURL
        return [
            RecoveryStep(label: "SENDING ESP32 RESET") {
                guard let url = URL(string: base + "/system/reset-esp32") else { return .fail("Bad URL") }
                var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 8
                _ = try? await URLSession.shared.data(for: req)
                return .pass("Sent")
            },
            RecoveryStep(label: "WAITING FOR DISCONNECT") {
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if !vm.healthBleConnected { return .pass("Disconnected") }
                }
                return .pass("Cycling")
            },
            RecoveryStep(label: "WAITING FOR RECONNECT") {
                for _ in 0..<24 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if vm.healthBleConnected { return .pass("Connected") }
                }
                return .fail("BLE not reconnecting")
            },
            RecoveryStep(label: "VERIFYING") {
                await vm.refreshHealth()
                return vm.healthBleConnected ? .pass("Connected") : .fail("Still disconnected")
            },
        ]
    }
}

// MARK: – YOLO detail

struct YoloDetailView: View {
    @EnvironmentObject var vm: DataViewModel
    @State private var showingRecovery = false

    var body: some View {
        VStack(spacing: 0) {
            if showingRecovery {
                RecoveryFlowView(title: "RESET DETECTOR",
                                 steps: yoloSteps(),
                                 onBack: { showingRecovery = false })
            } else {
                diagRow("STATUS",
                        value:      vm.healthYoloRunning ? "Running" : "Not running",
                        valueColor: vm.healthYoloRunning ? Theme.accent : Color(red: 0.75, green: 0.25, blue: 0.20))
                HRule()
                diagRow("MODE",
                        value:      vm.healthYoloSimMode ? "Simulation" : "Live inference",
                        valueColor: vm.healthYoloSimMode ? Theme.accentOrange : Theme.accent)
                HRule()
                diagRow("LAST INFER",
                        value:      vm.healthDetectLastAgoSec.map { String(format: "%.0fs ago", $0) } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
                diagRecoveryButton("RESET DETECTOR") { showingRecovery = true }
            }
        }
    }

    private func yoloSteps() -> [RecoveryStep] {
        let base = AppSettings.shared.piServerURL
        return [
            RecoveryStep(label: "STOPPING DETECTOR") {
                guard let url = URL(string: base + "/system/restart-detector") else { return .fail("Bad URL") }
                var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 5
                _ = try? await URLSession.shared.data(for: req)
                return .pass("OK")
            },
            RecoveryStep(label: "WAITING FOR RESTART") {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if vm.healthYoloRunning { return .pass("Running") }
                }
                return .fail("Timeout")
            },
            RecoveryStep(label: "CHECKING INFERENCE MODE") {
                await vm.refreshHealth()
                if vm.healthYoloRunning && !vm.healthYoloSimMode { return .pass("Live inference") }
                if vm.healthYoloRunning &&  vm.healthYoloSimMode { return .pass("Sim mode") }
                return .fail("Detector not running")
            },
            RecoveryStep(label: "VERIFYING") {
                await vm.refreshHealth()
                return vm.healthYoloRunning ? .pass("OK") : .fail("Still not running")
            },
        ]
    }
}

// MARK: – SSD detail

struct SsdDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            diagRow("STATUS",
                    value:      vm.healthSsdMounted ? "Mounted" : "Not mounted",
                    valueColor: vm.healthSsdMounted ? Theme.accent : Color(red: 0.75, green: 0.25, blue: 0.20))
            HRule()
            diagRow("FREE",
                    value:      vm.healthSsdMounted ? String(format: "%.1f%%", vm.healthSsdFreePct) : "—",
                    valueColor: ssdFreeColor)
            HRule()
            diagRow("STORAGE",
                    value:      vm.healthSsdMounted ? String(format: "%.1f GB", vm.ssdRemainingGB) : "—",
                    valueColor: Theme.secondary)
            HRule()
            Text("PHYSICAL ACCESS REQUIRED FOR REMOUNTING")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
    }

    private var ssdFreeColor: Color {
        guard vm.healthSsdMounted else { return Theme.tertiary }
        if vm.healthSsdFreePct < 5  { return Color(red: 0.75, green: 0.25, blue: 0.20) }
        if vm.healthSsdFreePct < 10 { return Theme.accentOrange }
        return Theme.accent
    }
}

// MARK: – Shared row helpers (file-private)

private func diagRow(_ label: String, value: String, valueColor: Color) -> some View {
    HStack {
        Text(label)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .tracking(Theme.labelTracking)
            .foregroundStyle(Theme.tertiary)
        Spacer()
        Text(value)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(valueColor)
    }
    .padding(.vertical, 8)
}

@ViewBuilder
private func diagRecoveryButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        action()
    } label: {
        Text("\(label) →")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accentOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
}
