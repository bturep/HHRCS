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
    let image:       PlatformImage
    @Binding var isPresented: Bool
    var bins:        [Int]   = []
    var clippedLow:  Double  = 0
    var clippedHigh: Double  = 0

    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0
    @State private var offset:     CGSize  = .zero
    @State private var lastOffset: CGSize  = .zero

    var body: some View {
        // ZStack does NOT have ignoresSafeArea — controls layer respects safe area automatically.
        // Background and image each opt out individually, extending behind Dynamic Island.
        ZStack {
            Theme.background.ignoresSafeArea()

            // Image in its own GeometryReader so geo.size covers the full screen for clamping.
            GeometryReader { geo in
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
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
            }
            .ignoresSafeArea()

            // Controls float over the image. ZStack respects safe area so this VStack
            // starts below the Dynamic Island — no manual inset calculation needed.
            VStack {
                HStack {
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
                .padding(.top, 8)
                Spacer()
                if !bins.isEmpty {
                    HistogramView(bins: bins, clippedLow: clippedLow, clippedHigh: clippedHigh)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Theme.cardBackground.opacity(0.75))
                }
            }
        }
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
