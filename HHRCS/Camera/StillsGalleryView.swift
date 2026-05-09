import SwiftUI

struct StillsGalleryView: View {
    @EnvironmentObject var vm: DataViewModel

    @State private var pendingDelete: CapturedStill? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ZStack {
            if vm.stills.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(vm.stills) { still in
                            StillCell(still: still, timeFormatter: Self.timeFormatter,
                                      onRequestDelete: { pendingDelete = still }) {
                                vm.stills.removeAll { $0.id == still.id }
                            }
                        }
                    }
                    .padding(Theme.pagePadding)
                }
                .background(Theme.background)
            }

            if let still = pendingDelete {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture { pendingDelete = nil }

                ConfirmationCard(
                    title:        "DELETE STILL?",
                    message:      "This cannot be undone.",
                    confirmLabel: "DELETE",
                    onConfirm: {
                        pendingDelete = nil
                        vm.stills.removeAll { $0.id == still.id }
                    },
                    onCancel: { pendingDelete = nil }
                )
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.tertiary)
            Text("NO STILLS CAPTURED")
                .font(Theme.dataLabel())
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Spacer()
        }
    }
}

// MARK: – Cell

private struct StillCell: View {
    let still: CapturedStill
    let timeFormatter: DateFormatter
    let onRequestDelete: () -> Void
    let onDelete: () -> Void

    @State private var showFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 4) {
                thumbnailView
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    .cornerRadius(4)
                    .onTapGesture { showFullscreen = true }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onRequestDelete()
                    }

                Text(still.sourceLabel)
                    .font(Theme.label(size: 9))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(timeFormatter.string(from: still.timestamp))
                .font(Theme.label(size: 10))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let data = still.piCamImageData, let img = PlatformImage(data: data) {
                FullscreenImageView(
                    image: img,
                    isPresented: $showFullscreen,
                    sourceLabel: still.sourceLabel,
                    onDelete: { showFullscreen = false; onDelete() }
                )
            } else {
                placeholderFullscreen
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let data = still.piCamImageData, let img = PlatformImage(data: data) {
                FullscreenImageView(
                    image: img,
                    isPresented: $showFullscreen,
                    sourceLabel: still.sourceLabel,
                    onDelete: { showFullscreen = false; onDelete() }
                )
            } else {
                placeholderFullscreen
            }
        }
        #endif
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let data = still.piCamImageData, let img = PlatformImage(data: data) {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
        } else {
            Theme.cardBackground
        }
    }

    private var placeholderFullscreen: some View {
        Theme.background.ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button { showFullscreen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(20)
                }
                .buttonStyle(.plain)
            }
    }
}
