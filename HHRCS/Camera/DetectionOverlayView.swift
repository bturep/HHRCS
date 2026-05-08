import SwiftUI

struct DetectionOverlayView: View {
    @EnvironmentObject var vm: DataViewModel
    let poller: StillPoller
    var verifyDetection: DetectionHistoryItem? = nil
    var verifyFiveMinCount: Int = 0

    var body: some View {
        ZStack {
            Theme.background

            if let image = poller.latestImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
            }

            GeometryReader { geo in
                let imgRect = scaledToFitRect(in: geo.size, aspect: 16.0 / 9.0)

                ForEach(vm.detections) { det in
                    let r = CGRect(
                        x:      imgRect.minX + det.box.minX * imgRect.width,
                        y:      imgRect.minY + det.box.minY * imgRect.height,
                        width:  det.box.width  * imgRect.width,
                        height: det.box.height * imgRect.height
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

                if let det = verifyDetection {
                    let bbox = det.cgRect
                    let r = CGRect(
                        x:      imgRect.minX + bbox.minX * imgRect.width,
                        y:      imgRect.minY + bbox.minY * imgRect.height,
                        width:  bbox.width  * imgRect.width,
                        height: bbox.height * imgRect.height
                    )
                    let color = verifyBoxColor(for: det.detectionClass)

                    Rectangle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)

                    Text("\(det.detectionClass)  \(String(format: "%.2f", det.confidence))")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                        .background(Theme.background)
                        .position(x: r.minX, y: r.minY - 8)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if verifyFiveMinCount > 0 {
                Text("DETECTIONS: \(verifyFiveMinCount) / 5min")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
        }
    }

    private func scaledToFitRect(in container: CGSize, aspect imageAspect: CGFloat) -> CGRect {
        let containerAspect = container.width / container.height
        if containerAspect > imageAspect {
            let w = container.height * imageAspect
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: container.height)
        } else {
            let h = container.width / imageAspect
            return CGRect(x: 0, y: (container.height - h) / 2, width: container.width, height: h)
        }
    }

    private func verifyBoxColor(for cls: String) -> Color {
        switch cls {
        case "animal":  return Theme.accentColor
        case "person":  return Theme.recordingRed
        default:        return Theme.secondary
        }
    }
}
