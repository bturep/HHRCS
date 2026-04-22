import SwiftUI

enum Theme {
    // MARK: – Colors
    static let background           = Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
    static let cardBackground       = Color(red: 0.133, green: 0.133, blue: 0.125) // #222220
    static let cardBackgroundActive = Color(red: 0.165, green: 0.125, blue: 0.094) // #2A2018
    static let accent             = Color(red: 0.769, green: 0.443, blue: 0.290) // #C4714A
    static let cardLabel          = Color(white: 0.333) // #555550
    static let text               = Color.white
    static let secondary          = Color(white: 0.55)
    static let tertiary           = Color(white: 0.30)
    static let rule               = Color(white: 0.20)

    // MARK: – Typography
    static func dataValue(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func dataValueText(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .regular)
    }
    static func dataLabel(size: CGFloat = 9) -> Font {
        .system(size: size, weight: .regular)
    }
    static func sectionHeader(size: CGFloat = 9) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func statusCaption(size: CGFloat = 12) -> Font {
        .custom("Georgia", size: size).italic()
    }
    static func bodyMono(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // MARK: – Dimensions
    static let ruleWidth:      CGFloat = 0.5
    static let pagePadding:    CGFloat = 20
    static let sectionGap:     CGFloat = 28
    static let labelTracking:  CGFloat = 1.8
    static let headerTracking: CGFloat = 2.5
}

// MARK: – PlatformImage typealias
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
