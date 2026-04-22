import SwiftUI

@main
struct HHRCSApp: App {
    @StateObject private var dataVM             = DataViewModel()
    @StateObject private var notesStore         = NotesStore()
    @StateObject private var orientationObserver = DeviceOrientationObserver()

    init() {
        configureAppearance()
        NotificationManager.shared.requestPermission()
        #if canImport(UIKit)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataVM)
                .environmentObject(notesStore)
                .environmentObject(orientationObserver)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }

    private func configureAppearance() {
        #if canImport(UIKit)
        let accent = UIColor(red: 0.769, green: 0.443, blue: 0.290, alpha: 1)
        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(white: 0.28, alpha: 1)
        #endif
    }
}
