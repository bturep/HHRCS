import SwiftUI

struct StillFrameView: View {
    @EnvironmentObject var vm: DataViewModel

    @State private var showFullscreen = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    private var capturedImage: PlatformImage? {
        guard let data = vm.lastStillData else { return nil }
        return PlatformImage(data: data)
    }

    private var capturedAt: Date {
        vm.lastStillCapturedAt ?? Date().addingTimeInterval(-840)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background

            if let image = capturedImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
                    .onTapGesture { showFullscreen = true }

                // Timestamp above capture button
                VStack(spacing: 0) {
                    Spacer()
                    HStack {
                        Text(Self.timeFormatter.string(from: capturedAt))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.tertiary.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                        Spacer()
                    }
                    captureBar
                }
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "photo")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(Theme.tertiary)
                    Text("NO STILL CAPTURED")
                        .font(Theme.dataLabel())
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.tertiary)
                    Text("tap to capture")
                        .font(Theme.statusCaption())
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                captureBar
            }
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

    private var captureBar: some View {
        Button {
            Task { await vm.triggerStill() }
        } label: {
            Text("CAPTURE STILL")
                .font(Theme.dataLabel(size: 11))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Theme.cardBackground)
        }
        .buttonStyle(.plain)
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
            Color.black.ignoresSafeArea()

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
                        .onEnded { v in
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
