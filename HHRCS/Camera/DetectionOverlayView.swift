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
    @StateObject private var sim = DetectionSimulator()

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
        }
    }
}
