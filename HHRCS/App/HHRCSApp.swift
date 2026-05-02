import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Handles opportunistic background fetch — calls NotificationPoller so users
// get routine notifications even when the app isn't foregrounded.
#if canImport(UIKit)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await NotificationPoller.shared.pollAndSurface()
            completionHandler(.newData)
        }
    }
}
#endif

@main
struct HHRCSApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var dataVM              = DataViewModel()
    @StateObject private var orientationObserver = DeviceOrientationObserver()
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(orientationObserver)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:                dataVM.resume()
            case .inactive, .background: dataVM.suspend()
            @unknown default:            break
            }
        }
    }

    private func configureAppearance() {
        #if canImport(UIKit)
        let accent = UIColor(red: 0.769, green: 0.443, blue: 0.290, alpha: 1)
        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(white: 0.28, alpha: 1)
        #endif
    }
}
