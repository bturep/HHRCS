import SwiftUI

struct DetectionOverlayView: View {
    @EnvironmentObject var vm: DataViewModel
    let player: MJPEGPlayer

    var body: some View {
        ZStack {
            MJPEGStreamView(player: player)

            if !vm.detections.isEmpty {
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
                }
            }
        }
    }

    // Returns the CGRect the image occupies inside the container when displayed with scaledToFit.
    private func scaledToFitRect(in container: CGSize, aspect imageAspect: CGFloat) -> CGRect {
        let containerAspect = container.width / container.height
        if containerAspect > imageAspect {
            // Container is wider than image → letterbox on left/right
            let w = container.height * imageAspect
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: container.height)
        } else {
            // Container is taller than image → letterbox on top/bottom
            let h = container.width / imageAspect
            return CGRect(x: 0, y: (container.height - h) / 2, width: container.width, height: h)
        }
    }
}
