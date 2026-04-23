import SwiftUI

// MARK: – Status enum

enum HealthStatus {
    case green, yellow, red, grey

    var color: Color {
        switch self {
        case .green:  return Color(red: 0.22, green: 0.60, blue: 0.32)
        case .yellow: return Color(red: 0.82, green: 0.63, blue: 0.12)
        case .red:    return Color(red: 0.75, green: 0.25, blue: 0.20)
        case .grey:   return Theme.tertiary
        }
    }
}

// MARK: – Tappable dot

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
                title:     detailTitle,
                state:     detailState,
                lastSeen:  lastSeen,
                error:     error
            )
        }
    }
}

// MARK: – Detail sheet

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
            // Header
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
                        detailRow(label: "ERROR", value: err, valueColor: Color(red: 0.75, green: 0.25, blue: 0.20))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.cardBackground)
        .presentationDetents([.fraction(0.35)])
        .presentationDragIndicator(.visible)
    }

    private func detailRow(label: String, value: String, valueColor: Color = .white) -> some View {
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
