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
    case pi   = "PI"
    case cam  = "CAM"
    case yolo = "YOLO"
    case card = "CARD"
    case ssd  = "SSD"
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
                .foregroundStyle(Theme.dotGreen)
                .frame(width: 8, height: 8)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.dotRed)
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
                .foregroundStyle(Theme.dotRed)
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
                    valueColor: vm.healthPiReachable ? Theme.accentOrange : Theme.dotRed)
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

// MARK: – CAM detail

struct CamDetailView: View {
    @EnvironmentObject var vm: DataViewModel
    @State private var showingRecovery = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone   = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if showingRecovery {
                RecoveryFlowView(title: "CAM RECOVERY",
                                 steps: camSteps(),
                                 onBack: { showingRecovery = false })
            } else {
                diagRow("STATUS",
                        value:      vm.camReachable ? "Reachable" : "Unreachable",
                        valueColor: vm.camReachable ? Theme.accentOrange : Theme.dotRed)
                HRule()
                diagRow("RECORDING",
                        value:      vm.camRecording ? "Recording" : "Idle",
                        valueColor: vm.camRecording ? Theme.dotRed : Theme.secondary)
                HRule()
                diagRow("FORMAT",
                        value:      "\(vm.camCodec) @ \(vm.camFrameRate)",
                        valueColor: Theme.secondary)
                HRule()
                diagRow("RESOLUTION",
                        value:      vm.camResolution,
                        valueColor: Theme.secondary)
                HRule()
                diagRow("ISO",
                        value:      vm.camIso.map { "\($0)" } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
                diagRow("WB",
                        value:      vm.camWhiteBalance.map { "\($0)K" } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
                diagRow("MEDIA",
                        value:      vm.camActiveMediaSlot,
                        valueColor: Theme.secondary)
                HRule()
                diagRow("LAST POLL",
                        value:      vm.healthLastPollAt.map { Self.fmt.string(from: $0) } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
                diagRecoveryButton("CAM RECOVERY") { showingRecovery = true }
            }
        }
    }

    private func camSteps() -> [RecoveryStep] {
        let base = AppSettings.shared.piServerURL
        return [
            RecoveryStep(label: "PINGING CAMERA") {
                await vm.refreshHealth()
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await vm.refreshHealth()
                    if vm.camReachable { return .pass("Reachable") }
                }
                return .fail("Check ethernet cable, camera power, and adapter LED")
            },
            RecoveryStep(label: "CHECKING API") {
                guard let url = URL(string: base + "/camera/status") else { return .fail("Bad URL") }
                var req = URLRequest(url: url); req.timeoutInterval = 5
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200 {
                    return .pass("200 OK")
                }
                return .fail("API not responding")
            },
            RecoveryStep(label: "VERIFYING") {
                await vm.refreshHealth()
                return vm.camReachable ? .pass("All clear") : .fail("Still unreachable")
            },
        ]
    }
}

// MARK: – CARD detail

struct CardDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            diagRow("MEDIA SLOT",
                    value:      vm.camActiveMediaSlot,
                    valueColor: vm.camActiveMediaSlot == "—" ? Theme.dotRed : Theme.accentOrange)
            HRule()
            diagRow("RECORDING",
                    value:      vm.camRecording ? "Recording" : "Idle",
                    valueColor: vm.camRecording ? Theme.dotRed : Theme.secondary)
            HRule()
            diagRow("TIME REMAINING",
                    value:      vm.camRemainingRecordTime.map { "\($0 / 60)m \($0 % 60)s" } ?? "—",
                    valueColor: Theme.secondary)
            HRule()
            Text("PHYSICAL MEDIA — SITE VISIT REQUIRED FOR SWAP")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
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
                        valueColor: vm.healthYoloRunning ? Theme.accentOrange : Theme.dotRed)
                HRule()
                diagRow("MODE",
                        value:      vm.healthYoloSimMode ? "Simulation" : "Live inference",
                        valueColor: vm.healthYoloSimMode ? Theme.dotAmber : Theme.accentOrange)
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
                    valueColor: vm.healthSsdMounted ? Theme.accentOrange : Theme.dotRed)
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
        if vm.healthSsdFreePct < 5  { return Theme.dotRed }
        if vm.healthSsdFreePct < 10 { return Theme.dotAmber }
        return Theme.accentOrange
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
