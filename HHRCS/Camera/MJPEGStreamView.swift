import SwiftUI

private let primaryStreamURL = URL(string: "http://raspberrypi.local:8080/stream")!

struct MJPEGStreamView: View {
    let streamURL: URL
    let fallbackURL: URL?
    var onConnectionChange: ((Bool) -> Void)? = nil
    @StateObject private var player: MJPEGPlayer

    init(streamURL: URL = primaryStreamURL,
         onConnectionChange: ((Bool) -> Void)? = nil) {
        self.streamURL          = streamURL
        self.fallbackURL        = nil
        self.onConnectionChange = onConnectionChange
        _player = StateObject(wrappedValue: MJPEGPlayer(url: streamURL, fallbackURL: nil))
    }

    var body: some View {
        ZStack {
            Theme.background

            if let frame = player.currentFrame {
                Image(platformImage: frame)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                offlineOverlay
            }
        }
        .onAppear  { player.start() }
        .onDisappear { player.stop() }
        .onChange(of: player.isConnected) { _, v in onConnectionChange?(v) }
    }

    private var offlineOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Theme.tertiary)
            Text(player.statusText)
                .font(Theme.dataLabel())
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
        }
    }
}
