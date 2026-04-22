import SwiftUI

struct Detection: Identifiable {
    let id    = UUID()
    let label: String
    let confidence: Double
    let box:   CGRect   // normalized 0–1 (x, y = top-left)
}

@MainActor
final class DetectionSimulator: ObservableObject {
    @Published var detections: [Detection] = []
    private var task: Task<Void, Never>?

    private let classes = ["deer", "fox", "raccoon", "coyote",
                           "bird", "squirrel", "cat", "person"]

    init() { start() }
    deinit { task?.cancel() }

    private func start() {
        task = Task {
            while !Task.isCancelled {
                let count = Int.random(in: 0...3)
                withAnimation(.easeInOut(duration: 0.4)) {
                    detections = (0..<count).map { _ in randomDetection() }
                }
                let interval = Double.random(in: 2.5...5.0)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1e9))
            }
        }
    }

    private func randomDetection() -> Detection {
        let w = Double.random(in: 0.12...0.45)
        let h = Double.random(in: 0.15...0.50)
        let x = Double.random(in: 0.02...(0.98 - w))
        let y = Double.random(in: 0.05...(0.90 - h))
        return Detection(
            label:      classes.randomElement()!,
            confidence: Double.random(in: 0.72...0.99),
            box:        CGRect(x: x, y: y, width: w, height: h)
        )
    }
}

struct DetectionOverlayView: View {
    @EnvironmentObject var vm: DataViewModel
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var sim = DetectionSimulator()
    @State private var showYoloPopover = false

    var body: some View {
        ZStack {
            MJPEGStreamView()

            GeometryReader { geo in
                ForEach(sim.detections) { det in
                    let r = CGRect(
                        x:      det.box.minX * geo.size.width,
                        y:      det.box.minY * geo.size.height,
                        width:  det.box.width * geo.size.width,
                        height: det.box.height * geo.size.height
                    )
                    Rectangle()
                        .stroke(Theme.accent, lineWidth: 1.5)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)

                    Text("\(det.label.uppercased())  \(Int(det.confidence * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .position(x: r.midX, y: r.minY - 8)
                }
            }

            // YOLO badge (tappable)
            VStack {
                HStack {
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
                    .padding(12)
                    Spacer()
                }
                Spacer()
            }

            // Trigger HUD at bottom
            VStack {
                Spacer()
                triggerHUD
                    .padding(.horizontal, 12)
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: – Trigger HUD

    private var triggerHUD: some View {
        HStack(spacing: 8) {
            // State pill
            HStack(spacing: 4) {
                if vm.triggerState == .active {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
                Text(vm.triggerStateLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(vm.triggerStateColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.background.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(vm.triggerStateColor.opacity(0.5), lineWidth: Theme.ruleWidth)
            )

            Text(vm.lastDetectionClass.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.background.opacity(0.6))

            Text(vm.lastDetectionTimeString)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.background.opacity(0.6))

            Spacer()
        }
    }
}

// MARK: – YOLO info popover

private struct YoloInfoPopover: View {
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
