import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum PhysicalOrientation: Equatable {
    case portrait
    case landscapeLeft
    case landscapeRight
    case other

    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }
}

final class DeviceOrientationObserver: ObservableObject {
    @Published var orientation: PhysicalOrientation = .portrait

    init() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    #if canImport(UIKit)
    @objc private func orientationChanged() {
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown:
            DispatchQueue.main.async { self.orientation = .portrait }
        case .landscapeLeft:
            DispatchQueue.main.async { self.orientation = .landscapeLeft }
        case .landscapeRight:
            DispatchQueue.main.async { self.orientation = .landscapeRight }
        default:
            break
        }
    }
    #endif
}
