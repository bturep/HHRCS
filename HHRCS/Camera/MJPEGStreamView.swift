import SwiftUI

struct MJPEGStreamView: View {
    @ObservedObject var player: MJPEGPlayer

    var body: some View {
        ZStack {
            Theme.background

            if let frame = player.currentFrame {
                Image(platformImage: frame)
                    .resizable()
                    .scaledToFit()
            } else {
                offlineOverlay
            }
        }
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
