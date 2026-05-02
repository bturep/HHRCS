import SwiftUI

struct StillsGalleryView: View {
    @EnvironmentObject var vm: DataViewModel

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
        if vm.stills.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(vm.stills) { still in
                        StillCell(still: still, timeFormatter: Self.timeFormatter) {
                        vm.stills.removeAll { $0.id == still.id }
                    }
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Theme.background)
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
            Text("tap the camera button in the FEED tab to capture")
                .font(Theme.statusCaption())
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: – Cell

private struct StillCell: View {
    let still: CapturedStill
    let timeFormatter: DateFormatter
    let onDelete: () -> Void

    @State private var showDeleteAlert = false
    @State private var showFullscreen  = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            thumbnailView
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .cornerRadius(4)
                .onTapGesture { showFullscreen = true }
                .onLongPressGesture { showDeleteAlert = true }

            HStack(spacing: 4) {
                Text(timeFormatter.string(from: still.timestamp))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)

                if still.bmpccFilename != nil {
                    Text("BMPCC")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.12))
                        .cornerRadius(2)
                }
                Spacer()
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let data = still.piCamImageData, let img = PlatformImage(data: data) {
                FullscreenImageView(image: img, isPresented: $showFullscreen)
            } else {
                placeholderFullscreen
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let data = still.piCamImageData, let img = PlatformImage(data: data) {
                FullscreenImageView(image: img, isPresented: $showFullscreen)
            } else {
                placeholderFullscreen
            }
        }
        #endif
        .alert("Delete this still?", isPresented: $showDeleteAlert) {
            Button("DELETE", role: .destructive) { onDelete() }
            Button("CANCEL", role: .cancel) { }
        }
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
