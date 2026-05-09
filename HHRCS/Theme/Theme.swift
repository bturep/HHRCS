import SwiftUI

enum Theme {
    // MARK: – Surface
    static let background:           Color = Color.black
    static let surface:              Color = Color(white: 0.055)             // #0E0E0E cards
    static let rule:                 Color = Color.white.opacity(0.06)       // hairlines

    // MARK: – Text tiers
    static let text1:                Color = Color(white: 0.96)              // primary values, active states
    static let text2:                Color = Color.white.opacity(0.62)       // labels, inactive tabs
    static let text3:                Color = Color.white.opacity(0.34)       // tertiary, hints
    static let text4:                Color = Color.white.opacity(0.14)       // disabled

    // MARK: – Semantic — ONLY chromatic colors
    static let recordingRed:         Color = Color(red: 0.800, green: 0.200, blue: 0.200)
    static let ok:                   Color = Color(red: 0.40,  green: 0.78,  blue: 0.55)   // diagnostic dots
    static let danger:               Color = Color(red: 1.0,   green: 0.231, blue: 0.188)  // #FF3B30 destructive / SSD-crit

    // MARK: – WARM UI accent (opt-in — off by default)
    static let warmAccent:           Color = Color(red: 0.78, green: 0.69, blue: 0.55)

    // MARK: – Diagnostic dot tokens — byte-identical, never change
    static let dotGreen:             Color = Color(hex: "00C853")
    static let dotAmber:             Color = Color(hex: "FFB300")
    static let dotRed:               Color = Color(hex: "E53935")

    // MARK: – Migration aliases (compile-time, forward to new tiers)
    static var secondary:            Color { text2 }
    static var tertiary:             Color { text3 }
    static var text:                 Color { text1 }
    static var cardLabel:            Color { text3 }
    static var cardBackground:       Color { surface }
    static var cardBackgroundActive: Color { Color(red: 0.165, green: 0.125, blue: 0.094) }

    // MARK: – Typography — three-size scale
    /// 11pt monospaced — section headings, row labels, tab labels
    static func label(size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    /// 14pt monospaced — values, copy, button text
    static func body(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    /// 17pt monospaced — primary readouts only
    static func display(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // Legacy aliases — forward to three-size scale so existing call sites compile
    @inlinable static func dataValue(size: CGFloat = 22) -> Font     { body(size: size) }
    @inlinable static func dataValueText(size: CGFloat = 22) -> Font { body(size: size) }
    @inlinable static func dataLabel(size: CGFloat = 9) -> Font      { label(size: size) }
    @inlinable static func sectionHeader(size: CGFloat = 9) -> Font  { label(size: size) }
    @inlinable static func statusCaption(size: CGFloat = 12) -> Font { body(size: size) }
    @inlinable static func bodyMono(size: CGFloat = 13) -> Font      { body(size: size) }

    // MARK: – Dimensions
    static let ruleWidth:      CGFloat = 0.5
    static let pagePadding:    CGFloat = 20
    static let sectionGap:     CGFloat = 28
    static let labelTracking:  CGFloat = 1.8
    static let headerTracking: CGFloat = 2.5
    static let cardRadius:     CGFloat = 8
    static let rowVPadding:    CGFloat = 14
    static let cardCorner:     CGFloat = 6
    static let cardInset:      CGFloat = 16
}

// MARK: – Neutral toggle style

struct NeutralToggleStyle: ToggleStyle {
    var activeColor: Color = Theme.text1
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(configuration.isOn ? activeColor.opacity(0.85) : Color.white.opacity(0.10))
            .frame(width: 38, height: 22)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(configuration.isOn ? Color(white: 0.04) : Color.white)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
            }
    }
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
