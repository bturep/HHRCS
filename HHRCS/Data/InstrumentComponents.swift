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
        .cornerRadius(Theme.cardRadius)
    }
}

// MARK: – Single metric cell
struct MetricCell: View {
    let value: String
    let label: String
    var valueSize: CGFloat = 13
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
                .foregroundStyle(Theme.tertiary)
        }
    }
}

// MARK: – Inline bar + percentage
struct BarCell: View {
    let label:     String
    let percent:   Double        // 0–100
    var valueSize: CGFloat = 17
    var warnAt:    Double = 85
    var critAt:    Double = 95

    private var barColor: Color {
        if percent >= critAt { return Theme.danger }
        if percent >= warnAt { return Theme.text2.opacity(0.8) }
        return Theme.text2
    }

    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "%.1f", percent) + "%")
                .font(Theme.dataValue(size: valueSize))
                .foregroundStyle(.white)
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
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
                    .font(Theme.body(size: 11))
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

// MARK: – Health status

enum HealthStatus {
    case green, yellow, red, grey

    var color: Color {
        switch self {
        case .green:  return Theme.dotGreen
        case .yellow: return Theme.dotAmber
        case .red:    return Theme.dotRed
        case .grey:   return Theme.tertiary
        }
    }
}

// MARK: – Tappable health dot

struct HealthDot: View {
    let label:       String
    let status:      HealthStatus
    let detailTitle: String
    let detailState: String
    let lastSeen:    Date?
    let error:       String?

    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            HealthDetailSheet(
                title:    detailTitle,
                state:    detailState,
                lastSeen: lastSeen,
                error:    error
            )
        }
    }
}

// MARK: – Health detail sheet

struct HealthDetailSheet: View {
    let title:    String
    let state:    String
    let lastSeen: Date?
    let error:    String?

    @Environment(\.dismiss) private var dismiss

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            HRule()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailRow(label: "STATE", value: state)
                    HRule()
                    detailRow(label: "LAST SEEN",
                              value: lastSeen.map { Self.fmt.string(from: $0) } ?? "—")
                    if let err = error {
                        HRule()
                        detailRow(label: "ERROR", value: err,
                                  valueColor: Color(red: 0.75, green: 0.25, blue: 0.20))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.cardBackground)
        .presentationDetents([.fraction(0.35)])
        .presentationDragIndicator(.visible)
    }

    private func detailRow(label: String, value: String,
                           valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 12)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
        }
    }
}
