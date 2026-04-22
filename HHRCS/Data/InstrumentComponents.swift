import SwiftUI

// MARK: – Section header + rule
struct SectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Theme.sectionHeader())
                .tracking(Theme.headerTracking)
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Theme.rule)
                .frame(height: Theme.ruleWidth)
        }
    }
}

// MARK: – Thin horizontal rule
struct HRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: Theme.ruleWidth)
    }
}

// MARK: – Section card wrapper
struct SectionCard<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.headerTracking)
                .foregroundStyle(Theme.cardLabel)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Theme.cardBackgroundActive : Theme.cardBackground)
        .cornerRadius(8)
    }
}

// MARK: – Single metric cell
struct MetricCell: View {
    let value: String
    let label: String
    var valueSize: CGFloat = 22
    var valueColor: Color  = .white
    var monospaced: Bool   = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(monospaced ? Theme.dataValue(size: valueSize) : Theme.dataValueText(size: valueSize))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(Theme.dataLabel())
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: – Inline bar + percentage
struct BarCell: View {
    let label:   String
    let percent: Double        // 0–100
    var warnAt:  Double = 85
    var critAt:  Double = 95

    private var barColor: Color {
        if percent >= critAt { return Color.red }
        if percent >= warnAt { return Theme.accent }
        return Theme.secondary
    }

    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "%.1f", percent) + "%")
                .font(Theme.dataValue(size: 22))
                .foregroundStyle(.white)
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: 2)
                    Rectangle()
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(percent / 100), height: 2)
                }
            }
            .frame(height: 2)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

// MARK: – Status pill (ACTIVE / HOLDING / T–n)
struct StatusPill: View {
    let text:  String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.dataValueText(size: 22))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: Theme.ruleWidth)
            )
    }
}

// MARK: – Forecast day cell
struct ForecastCell: View {
    let day:    String
    let icon:   String
    let maxC:   Double
    let minC:   Double

    var body: some View {
        VStack(spacing: 4) {
            Text(day)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            Text(String(format: "%+.0f°", maxC))
                .font(Theme.dataValue(size: 14))
                .foregroundStyle(.white)
            Text(String(format: "%+.0f°", minC))
                .font(Theme.dataValue(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
