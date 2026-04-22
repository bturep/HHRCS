import SwiftUI

// MARK: – Tab definitions

private struct TabDef {
    let label: String
    let icon:  String
    let tag:   Int
}

private let appTabs: [TabDef] = [
    .init(label: "FEED",     icon: "camera",       tag: 0),
    .init(label: "DATA",     icon: "gauge.medium",  tag: 1),
    .init(label: "FIELD",    icon: "doc.text",      tag: 2),
    .init(label: "SETTINGS", icon: "gearshape",     tag: 3),
]

// MARK: – Root view

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraTabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)

                DataTabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)

                NotesTabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)

                SettingsTabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppTabBar(selectedTab: $selectedTab)
        }
        .background(Theme.background)
    }
}

// MARK: – Custom tab bar

private struct AppTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver

    var body: some View {
        HStack(spacing: 0) {
            ForEach(appTabs, id: \.tag) { tab in
                Button {
                    selectedTab = tab.tag
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(selectedTab == tab.tag ? Theme.accent : Color(white: 0.38))
                        Text(tab.label)
                            .font(.system(size: 9, weight: selectedTab == tab.tag ? .semibold : .medium))
                            .tracking(1.0)
                            .foregroundStyle(selectedTab == tab.tag ? Theme.accent : Color(white: 0.38))
                    }
                    .rotationEffect(rotationAngle)
                    .animation(.easeInOut(duration: 0.3), value: rotationAngle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 49)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    private var rotationAngle: Angle {
        switch orientationObserver.orientation {
        case .landscapeLeft:  return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        default:              return .degrees(0)
        }
    }
}
