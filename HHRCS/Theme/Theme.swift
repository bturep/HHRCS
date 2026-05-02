import SwiftUI

enum Theme {
    // MARK: – Colors
    static let background           = Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
    static let cardBackground       = Color(red: 0.098, green: 0.098, blue: 0.090) // #191917
    static let cardBackgroundActive = Color(red: 0.165, green: 0.125, blue: 0.094) // #2A2018
    static let accent             = Color(red: 0.769, green: 0.443, blue: 0.290) // #C4714A
    static let accentOrange       = Color(red: 1.000, green: 0.549, blue: 0.000) // #FF8C00
    static let recordingRed       = Color(red: 0.800, green: 0.200, blue: 0.200) // #CC3333
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
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func dataLabel(size: CGFloat = 9) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func sectionHeader(size: CGFloat = 9) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func statusCaption(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
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
    static let cardRadius:     CGFloat = 8
}

// MARK: – PlatformImage typealias
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
