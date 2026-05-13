import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// ── Diagnostic dot → /status field → threshold mapping ──────────────────────
//
// PI      healthPiReachable      TCP poll success → green; failure → red
//
// BMPCC   camReachable           cam_reachable → green/red; grey if PI down
//
// CAM     healthPiReachable      Pi reachable implies Pi Camera Module 3 active
//                                green if PI up, grey if PI down
//
// YOLO    healthYoloRunning      yolo_running → green/red; grey if PI down
//
// HDMI    hdmiReachable          hdmi_reachable → green/red; grey if PI down
//
// PI SD   piSdUsedPct            pi_sd_used_pct (df on "/" = microSD boot disk)
//                                <80% → green; 80–95% → yellow; >95% → red; grey if PI down
//
// CAM SD  camActiveMediaSlot     cam_active_media_slot (workingset activeDisk entry)
//                                contains "sd" → green; else → grey
//                                remaining time shown only when SD is active slot
//
// CAM CF  camActiveMediaSlot     cam_active_media_slot (same field)
//                                contains "cfast"/"cf" → green; else → grey
//                                remaining time shown only when CF is active slot
// ────────────────────────────────────────────────────────────────────────────

// MARK: – Panel state machine

enum DiagnosticPanelMode: Equatable {
    case closed
    case log
    case detail(DiagnosticDot)
}

enum DiagnosticDot: String, CaseIterable {
    // Connectivity row
    case pi    = "PI"
    case bmpcc = "BMPCC"
    case cam   = "CAM"
    case yolo  = "YOLO"
    case hdmi  = "HDMI"
    // Storage row
    case piSd  = "PI SD"
    case camSd = "CAM SD"
    case camCf = "CAM CF"

    var isStorageDot: Bool {
        switch self {
        case .piSd, .camSd, .camCf: return true
        default: return false
        }
    }
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
                    .foregroundStyle(Theme.text2)
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
                .fill(Theme.ok)
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
        case .running:          return Theme.ok
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
                    valueColor: vm.healthPiReachable ? Theme.ok : Theme.dotRed)
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

// MARK: – BMPCC detail (was CamDetailView)

struct BmpccDetailView: View {
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
                        valueColor: vm.camReachable ? Theme.ok : Theme.dotRed)
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

// MARK: – CAM detail (Pi Camera Module 3)

struct CamDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            diagRow("MODULE",
                    value:      "Pi Camera Module 3",
                    valueColor: Theme.secondary)
            HRule()
            diagRow("STREAM",
                    value:      vm.healthPiReachable ? "Active" : "Unavailable",
                    valueColor: vm.healthPiReachable ? Theme.ok : Theme.dotRed)
            HRule()
            Text("MJPEG STREAM ON :5001/STREAM")
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
                        valueColor: vm.healthYoloRunning ? Theme.ok : Theme.dotRed)
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
            RecoveryStep(label: "VERIFYING") {
                await vm.refreshHealth()
                return vm.healthYoloRunning ? .pass("OK") : .fail("Still not running")
            },
        ]
    }
}

// MARK: – PI SD detail (Pi microSD boot disk)

struct PiSdDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            diagRow("DEVICE",
                    value:      "Pi microSD (boot, /)",
                    valueColor: Theme.secondary)
            HRule()
            diagRow("USED",
                    value:      vm.piSdUsedPct.map { String(format: "%.1f%%", $0) } ?? "—",
                    valueColor: piSdColor)
            HRule()
            Text("WRITE WORKLOAD: METRICS · EVENTS · MODEL · LOGS")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
    }

    private var piSdColor: Color {
        guard let used = vm.piSdUsedPct else { return Theme.tertiary }
        if used > 95 { return Theme.dotRed }
        if used > 80 { return Theme.dotAmber }
        return Theme.ok
    }
}

// MARK: – CAM SD detail (BMPCC SD slot)

struct CamSdDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            let isActive = vm.camActiveMediaSlot.lowercased().contains("sd")
            diagRow("ACTIVE",
                    value:      isActive ? "Yes" : "No",
                    valueColor: isActive ? Theme.text1 : Theme.secondary)
            HRule()
            if isActive {
                diagRow("REMAINING",
                        value:      vm.camRemainingRecordTime.map { "\($0 / 60)m \($0 % 60)s" } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
            }
            diagRow("SLOT",   value: "SD Card (Slot 2)", valueColor: Theme.secondary)
            HRule()
            Text("PHYSICAL ACCESS REQUIRED FOR MEDIA SWAP")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
    }
}

// MARK: – CAM CF detail (BMPCC CFast slot)

struct CamCfDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            let slot = vm.camActiveMediaSlot.lowercased()
            let isActive = slot.contains("cfast") || slot.contains("cf")
            diagRow("ACTIVE",
                    value:      isActive ? "Yes" : "No",
                    valueColor: isActive ? Theme.text1 : Theme.secondary)
            HRule()
            if isActive {
                diagRow("REMAINING",
                        value:      vm.camRemainingRecordTime.map { "\($0 / 60)m \($0 % 60)s" } ?? "—",
                        valueColor: Theme.secondary)
                HRule()
            }
            diagRow("SLOT",   value: "CFast 2.0 (Slot 1)", valueColor: Theme.secondary)
            HRule()
            Text("PHYSICAL ACCESS REQUIRED FOR MEDIA SWAP")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
    }
}

// MARK: – HDMI detail

struct HdmiDetailView: View {
    @EnvironmentObject var vm: DataViewModel

    var body: some View {
        VStack(spacing: 0) {
            diagRow("STATUS",
                    value:      vm.hdmiReachable ? "Streaming" : "Offline",
                    valueColor: vm.hdmiReachable ? Theme.ok : Theme.dotRed)
            HRule()
            diagRow("DEVICE", value: "/dev/video2", valueColor: Theme.secondary)
            HRule()
            diagRow("FORMAT", value: "MJPEG 1920×1080 @ 25fps", valueColor: Theme.secondary)
            HRule()
            Text("GUERMOK USB2 VIDEO CAPTURE — CHECK USB CONNECTION")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
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
            .foregroundStyle(Theme.text1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
}
