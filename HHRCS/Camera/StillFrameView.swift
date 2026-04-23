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
                    // Leave room at bottom for capture bar
                    .padding(.bottom, 76)

                VStack(spacing: 0) {
                    Spacer()
                    Text(Self.timeFormatter.string(from: capturedAt))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Theme.tertiary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    captureBar
                }
            } else {
                emptyState
                VStack(spacing: 0) {
                    Spacer()
                    captureBar
                }
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

    // MARK: – Empty state
    // Whole area styled as an invitation to capture; tap triggers BMPCC still.

    private var emptyState: some View {
        Button {
            Task { await vm.triggerStill() }
        } label: {
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
                Text("tap to capture BMPCC still")
                    .font(Theme.statusCaption())
                    .foregroundStyle(Theme.tertiary.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // Reserve space so empty state doesn't bleed into capture bar
        .padding(.bottom, 76)
    }

    // MARK: – Capture bar
    // Two distinct actions, side by side, anchored to the bottom.

    private var captureBar: some View {
        HStack(spacing: 1) {
            captureButton(
                label: "BMPCC STILL",
                icon:  "bolt.fill",
                action: { Task { await vm.triggerStill() } }
            )

            captureButton(
                label: "PI CAM STILL",
                icon:  "camera",
                // Phase 4: Pi cam still trigger wired here
                action: { }
            )
            .opacity(0.4)  // dimmed until Phase 4 wires it up
        }
        .frame(height: 48)
    }

    private func captureButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(Theme.dataLabel(size: 10))
                    .tracking(Theme.labelTracking)
            }
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
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
