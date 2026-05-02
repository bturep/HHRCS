import SwiftUI

struct StillFrameView: View {
    @EnvironmentObject var vm: DataViewModel

    @State private var showFullscreen = false
    @State private var hasLoaded      = false

    private var capturedImage: PlatformImage? {
        guard let data = vm.lastStillData else { return nil }
        return PlatformImage(data: data)
    }

    var body: some View {
        ZStack {
            Theme.background

            if vm.isCapturingStill {
                capturingView
            } else if let image = capturedImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
                    .onTapGesture { showFullscreen = true }
            } else {
                emptyState
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            Task { await vm.captureStill() }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let image = capturedImage {
                FullscreenImageView(image: image, isPresented: $showFullscreen)
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let image = capturedImage {
                FullscreenImageView(image: image, isPresented: $showFullscreen)
            }
        }
        #endif
    }

    // MARK: – Capturing indicator

    private var capturingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.1)
            Text("CAPTURING")
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: – Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.tertiary)
            Text("NO STILL CAPTURED")
                .font(Theme.dataLabel())
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: – Fullscreen viewer with pinch-to-zoom + pan

struct FullscreenImageView: View {
    let image: PlatformImage
    @Binding var isPresented: Bool

    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0
    @State private var offset:     CGSize  = .zero
    @State private var lastOffset: CGSize  = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()

                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in
                                scale = max(1.0, lastScale * v)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                let (maxX, maxY) = clampBounds(in: geo)
                                let clamped = CGSize(
                                    width:  min(maxX,  max(-maxX,  offset.width)),
                                    height: min(maxY, max(-maxY, offset.height))
                                )
                                withAnimation(.spring()) { offset = clamped }
                                lastOffset = clamped
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                let (maxX, maxY) = clampBounds(in: geo)
                                offset = CGSize(
                                    width:  min(maxX,  max(-maxX,  lastOffset.width  + v.translation.width)),
                                    height: min(maxY, max(-maxY, lastOffset.height + v.translation.height))
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )

                VStack {
                    HStack {
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(20)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    private func clampBounds(in geo: GeometryProxy) -> (CGFloat, CGFloat) {
        let size = geo.size
        guard size.width > 0, size.height > 0,
              image.size.width > 0, image.size.height > 0 else { return (0, 0) }
        let imgAspect = image.size.width / image.size.height
        let ctrAspect = size.width / size.height
        let rw: CGFloat
        let rh: CGFloat
        if imgAspect > ctrAspect {
            rw = size.width
            rh = size.width / imgAspect
        } else {
            rh = size.height
            rw = size.height * imgAspect
        }
        return (max(0, (rw * scale - size.width)  / 2),
                max(0, (rh * scale - size.height) / 2))
    }
}
