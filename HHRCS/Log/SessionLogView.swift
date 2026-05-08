import SwiftUI

// MARK: – Model

enum LogTriggerType: String {
    case scheduled = "SCHEDULED"
    case deer      = "DEER"
    case rabbit    = "RABBIT"
    case bird      = "BIRD"
}

struct LogEntry: Identifiable {
    let id:              UUID
    let timestamp:       Date
    let triggerType:     LogTriggerType
    let durationSeconds: Int
    let confidence:      Double?
    let fileCount:       Int
    let luxAtStart:      Double
    // Detail
    let iso:             Int
    let ndPosition:      Int
    let avgLux:          Double
    let stateTransitions:[String]
    let stillCount:      Int
    let brawFilename:    String
    let piCamFilename:   String
}

// MARK: – Store

final class SessionLogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    init() { }

    private static func simulatedEntries() -> [LogEntry] {
        let now = Date()
        let day = 86400.0
        let rng: [(offset: Double, type: LogTriggerType, dur: Int, conf: Double?,
                   files: Int, lux: Double, iso: Int, nd: Int, avgLux: Double, stills: Int)] = [
            (-0.5*3600,        .deer,      187, 0.83, 2, 1240, 3200, 4, 1180, 3),
            (-2.1*3600,        .scheduled, 300, nil,  3,  890, 1600, 4,  920, 1),
            (-4.7*3600,        .bird,       62, 0.71, 1,  540,  400, 2,  510, 2),
            (-6.2*3600,        .rabbit,    144, 0.68, 2, 2100, 3200, 6, 2050, 1),
            (-day - 1.3*3600,  .deer,      211, 0.91, 2, 1780, 3200, 4, 1760, 4),
            (-day - 3.8*3600,  .bird,       48, 0.64, 1,  420,  400, 2,  415, 1),
            (-day - 8.1*3600,  .scheduled, 300, nil,  3,  680,  800, 2,  700, 1),
            (-day - 11.4*3600, .rabbit,     93, 0.77, 1,  390,  400, 0,  380, 2),
        ]

        return rng.enumerated().map { i, r in
            let ts = now.addingTimeInterval(r.offset)
            let tsFmt = DateFormatter()
            tsFmt.dateFormat = "yyyyMMdd_HHmmss"
            tsFmt.timeZone = TimeZone(identifier: "America/Vancouver")
            let tsStr = tsFmt.string(from: ts)
            let h = Int(ts.timeIntervalSince1970) % 86400 / 3600
            let m = Int(ts.timeIntervalSince1970) % 3600 / 60
            let s = Int(ts.timeIntervalSince1970) % 60
            let base = String(format: "%02d:%02d:%02d", h, m, s)
            return LogEntry(
                id:              UUID(),
                timestamp:       ts,
                triggerType:     r.type,
                durationSeconds: r.dur,
                confidence:      r.conf,
                fileCount:       r.files,
                luxAtStart:      r.lux,
                iso:             r.iso,
                ndPosition:      r.nd,
                avgLux:          r.avgLux,
                stateTransitions: [
                    "\(base) HOLDING → ACTIVE",
                    String(format: "%02d:%02d:%02d", h, m, s+3) + " ACTIVE → COUNTDOWN",
                    String(format: "%02d:%02d:%02d", h, m, s+8) + " COUNTDOWN → HOLDING",
                ],
                stillCount:    r.stills,
                brawFilename:  "A001C\(String(format: "%03d", i+1))_\(tsStr.prefix(8))_R7UN.braw",
                piCamFilename: "session_\(tsStr).mp4"
            )
        }
    }
}

// MARK: – Combined log item

enum LogItem: Identifiable {
    case session(LogEntry)
    case agent(AILogEntry)
    case detection(DetectionHistoryItem)

    var id: UUID {
        switch self {
        case .session(let e):   return e.id
        case .agent(let e):     return e.id
        case .detection(let e): return e.id
        }
    }
    var timestamp: Date {
        switch self {
        case .session(let e):   return e.timestamp
        case .agent(let e):     return e.timestamp
        case .detection(let e): return e.timestamp
        }
    }
}

// MARK: – Embeddable list view

struct SessionLogView: View {
    @ObservedObject var store: SessionLogStore
    var agentEntries: [AILogEntry] = []
    var detectionEntries: [DetectionHistoryItem] = []

    @State private var expandedID: UUID? = nil

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private struct EntryGroup { let header: String; let items: [LogItem] }

    private var grouped: [EntryGroup] {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        let all: [LogItem] = (store.entries.map { .session($0) }
            + agentEntries.map { .agent($0) }
            + detectionEntries.map { .detection($0) })
            .sorted { $0.timestamp > $1.timestamp }

        var groups: [EntryGroup] = []
        var lastDay: Date? = nil
        var batch: [LogItem] = []

        for item in all {
            let day = cal.startOfDay(for: item.timestamp)
            if let last = lastDay, cal.isDate(last, inSameDayAs: item.timestamp) {
                batch.append(item)
            } else {
                if !batch.isEmpty, let last = lastDay {
                    groups.append(EntryGroup(header: Self.dayFmt.string(from: last).uppercased(), items: batch))
                }
                lastDay = day
                batch = [item]
            }
        }
        if !batch.isEmpty, let last = lastDay {
            groups.append(EntryGroup(header: Self.dayFmt.string(from: last).uppercased(), items: batch))
        }
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if grouped.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundStyle(Theme.tertiary)
                        Text("NO ENTRIES")
                            .font(Theme.dataLabel())
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }

                ForEach(grouped, id: \.header) { group in
                    Text(group.header)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(Theme.headerTracking)
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.vertical, 16)

                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                        rowView(for: item)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.vertical, 10)
                        if idx < group.items.count - 1 {
                            HRule().padding(.horizontal, Theme.pagePadding)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func rowView(for item: LogItem) -> some View {
        switch item {
        case .session(let entry):
            LogRow(
                entry: entry,
                isExpanded: expandedID == entry.id,
                onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedID = expandedID == entry.id ? nil : entry.id
                    }
                }
            )
        case .agent(let entry):
            AgentLogRow(entry: entry)
        case .detection(let entry):
            DetectionLogRow(entry: entry)
        }
    }
}

// MARK: – Log row

private struct LogRow: View {
    let entry: LogEntry
    let isExpanded: Bool
    let onTap: () -> Void

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    private var durationLabel: String {
        let m = entry.durationSeconds / 60
        let s = entry.durationSeconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.timeFmt.string(from: entry.timestamp))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                    Text(speciesLabel)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(triggerColor)
                    Spacer()
                    Text(durationLabel)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }

                // Expanded detail
                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        HRule().padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STATE TRANSITIONS")
                                .font(Theme.dataLabel(size: 9))
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(Theme.tertiary)
                                .padding(.top, 2)
                            ForEach(entry.stateTransitions, id: \.self) { t in
                                Text(t)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            fileRow(label: "BRAW", value: entry.brawFilename)
                            fileRow(label: "PI CAM", value: entry.piCamFilename)
                        }
                        .padding(.top, 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var triggerColor: Color {
        entry.triggerType == .scheduled ? Theme.tertiary : .white
    }

    private var speciesLabel: String {
        guard let conf = entry.confidence else { return entry.triggerType.rawValue }
        return "\(entry.triggerType.rawValue) (\(String(format: "%.2f", conf)))"
    }

    private func fileRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.dataLabel(size: 9))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: – Detection log row

private struct DetectionLogRow: View {
    let entry: DetectionHistoryItem

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
            Text(entry.detectionClass.uppercased())
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(classColor)
            Spacer()
            Text(String(format: "%.2f", entry.confidence))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var classColor: Color {
        switch entry.detectionClass {
        case "animal":  return Theme.accentColor
        case "person":  return Theme.recordingRed
        default:        return Theme.secondary
        }
    }
}

// MARK: – Agent log row (summary entries only — rendered as plain log lines)

private struct AgentLogRow: View {
    let entry: AILogEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
            Text(entry.content)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }
}
