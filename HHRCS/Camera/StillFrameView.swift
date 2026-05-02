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
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Image(systemName: "camera")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(Theme.accent.opacity(0.6))
            }
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
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0; lastScale = 1.0
                                    offset = .zero; lastOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { v in
                            offset = CGSize(
                                width:  lastOffset.width  + v.translation.width,
                                height: lastOffset.height + v.translation.height
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
    }
}
