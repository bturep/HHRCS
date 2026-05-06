import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: – Tab definitions

private struct TabDef {
    let label: String
    let icon:  String
    let tag:   Int
}

private let appTabs: [TabDef] = [
    .init(label: "FIELD",    icon: "doc.text",      tag: 0),
    .init(label: "FEED",     icon: "camera",        tag: 1),
    .init(label: "DATA",     icon: "gauge.medium",  tag: 2),
    .init(label: "SETTINGS", icon: "gearshape",     tag: 3),
]

// MARK: – Root view

struct ContentView: View {
    @State private var selectedTab  = 1
    @State private var isLaunched   = false
    @State private var tabBarHidden = false
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver

    private var isLandscape: Bool { orientationObserver.orientation.isLandscape }

    var body: some View {
        ZStack {
            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        tabContent
                        if !tabBarHidden { AppTabBar(selectedTab: $selectedTab) }
                    }
                } else {
                    VStack(spacing: 0) {
                        tabContent
                        if !tabBarHidden { AppTabBar(selectedTab: $selectedTab) }
                    }
                }
            }
            .background(Theme.background)

            if !isLaunched {
                LaunchView { targetTab in
                    selectedTab = targetTab
                    withAnimation(.easeIn(duration: 0.5)) { isLaunched = true }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeIn(duration: 0.3), value: isLaunched)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            let dur = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: dur)) { tabBarHidden = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notif in
            let dur = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: dur)) { tabBarHidden = false }
        }
        #endif
    }

    private var tabContent: some View {
        ZStack {
            NotesTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)

            CameraTabView(isActive: selectedTab == 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)

            DataTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 2 ? 1 : 0)
                .allowsHitTesting(selectedTab == 2)

            SettingsTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == 3 ? 1 : 0)
                .allowsHitTesting(selectedTab == 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Custom tab bar

private struct AppTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var orientationObserver: DeviceOrientationObserver
    @EnvironmentObject var dataVM: DataViewModel

    private var isLandscape: Bool { orientationObserver.orientation.isLandscape }

    var body: some View {
        if isLandscape {
            VStack(spacing: 0) {
                Spacer()
                ForEach(appTabs, id: \.tag) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .frame(width: 60)
            .frame(maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
        } else {
            HStack(spacing: 0) {
                ForEach(appTabs, id: \.tag) { tab in
                    tabButton(tab)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            .frame(height: 57)
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: TabDef) -> some View {
        Button {
            selectedTab = tab.tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tabForeground(tab))
                    .overlay(alignment: .topTrailing) {
                        if tab.tag == 3 && dataVM.hasSystemAlert {
                            Circle()
                                .fill(Theme.recordingRed)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -2)
                        }
                    }
                Text(tab.label)
                    .font(.system(size: 9, weight: selectedTab == tab.tag ? .semibold : .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(tabForeground(tab))
            }
            .padding(.vertical, isLandscape ? 10 : 8)
            .padding(.horizontal, isLandscape ? 4 : 0)
        }
        .buttonStyle(.plain)
    }

    private func tabForeground(_ tab: TabDef) -> Color {
        if tab.tag == 1 && (dataVM.isRecording || dataVM.isPiCamRecording) {
            return Theme.recordingRed
        }
        return selectedTab == tab.tag ? Theme.accentColor : Color(white: 0.38)
    }
}
