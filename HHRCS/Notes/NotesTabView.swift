import SwiftUI

private enum NoteSegment: String, CaseIterable {
    case notes  = "NOTES"
    case log    = "LOG"
    case stills = "STILLS"
    case agent  = "AGENT"
}

struct NotesTabView: View {
    @EnvironmentObject var store:  NotesStore
    @EnvironmentObject var dataVM: DataViewModel

    @StateObject private var logStore = SessionLogStore()
    @ObservedObject private var settings = AppSettings.shared

    @State private var segment: NoteSegment = .notes
    @State private var draftName = ""
    @State private var draftText = ""

    @AppStorage("hhrcs.lastNoteName") private var savedName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Custom segment toggle
            HStack(spacing: 24) {
                ForEach(NoteSegment.allCases, id: \.self) { s in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { segment = s } }) {
                        VStack(spacing: 5) {
                            Text(s.rawValue)
                                .font(Theme.dataLabel(size: 11))
                                .tracking(Theme.labelTracking)
                                .foregroundStyle(segment == s ? .white : Theme.tertiary)
                                .fontWeight(segment == s ? .medium : .regular)
                            Rectangle()
                                .fill(segment == s ? Theme.accent : Color.clear)
                                .frame(height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HRule().padding(.horizontal, Theme.pagePadding)

            if segment == .notes {
                notesContent
            } else if segment == .log {
                SessionLogView(
                    store: logStore,
                    agentEntries: settings.piAgentLogEnabled
                        ? dataVM.aiLogEntries.filter { $0.source == "pi_agent" }
                        : []
                )
            } else if segment == .stills {
                StillsGalleryView()
            } else {
                FieldAgentView()
            }

            if segment == .notes {
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1)

                composeBar
                    .background(Color(red: 0.102, green: 0.102, blue: 0.094))
            }
        }
        .background(Theme.background)
        .onAppear {
            if draftName.isEmpty { draftName = savedName }
        }
    }

    // MARK: – Notes list
    @ViewBuilder
    private var notesContent: some View {
        if store.notes.isEmpty {
            Spacer()
            Text("no notes yet")
                .font(Theme.statusCaption())
                .foregroundStyle(Theme.tertiary)
            Spacer()
        } else {
            List {
                ForEach(notesByDay, id: \.header) { group in
                    Section {
                        ForEach(group.notes) { note in
                            NoteRow(note: note)
                                .listRowBackground(Theme.background)
                                .listRowSeparatorTint(Theme.rule)
                                .listRowInsets(EdgeInsets(
                                    top: 10, leading: Theme.pagePadding,
                                    bottom: 10, trailing: Theme.pagePadding
                                ))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        store.deleteNote(withID: note.id)
                                    } label: {
                                        Text("DELETE")
                                    }
                                    .tint(Theme.accent)
                                }
                        }
                    } header: {
                        Text(group.header)
                            .font(Theme.dataLabel(size: 9))
                            .tracking(Theme.headerTracking)
                            .foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.background)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .background(Theme.background)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: – Day groups (newest day first)
    private struct NoteGroup { let header: String; let notes: [Note] }

    private var notesByDay: [NoteGroup] {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "EEE d MMM"

        var groups: [NoteGroup] = []
        var lastDay: Date? = nil
        var batch: [Note] = []

        for note in store.notes {
            let day = cal.startOfDay(for: note.timestamp)
            if let last = lastDay, cal.isDate(last, inSameDayAs: note.timestamp) {
                batch.append(note)
            } else {
                if !batch.isEmpty, let last = lastDay {
                    groups.append(NoteGroup(header: fmt.string(from: last).uppercased(), notes: batch))
                }
                lastDay = day
                batch = [note]
            }
        }
        if !batch.isEmpty, let last = lastDay {
            groups.append(NoteGroup(header: fmt.string(from: last).uppercased(), notes: batch))
        }
        return groups
    }

    // MARK: – Compose bar
    private var composeBar: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                Text("FROM")
                    .font(Theme.dataLabel(size: 9))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.tertiary)
                TextField("name", text: $draftName)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(Theme.accent)
                    .submitLabel(.next)
                    .onChange(of: draftName) { _, v in savedName = v }
            }
            .padding(.horizontal, Theme.pagePadding)
            HRule()
                .padding(.vertical, 10)
                .padding(.horizontal, Theme.pagePadding)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("note", text: $draftText, axis: .vertical)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(Theme.accent)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { post() }
                Button(action: post) {
                    ZStack {
                        Circle()
                            .fill(canPost ? Theme.accent : Color.white.opacity(0.07))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canPost ? .white : Theme.tertiary)
                    }
                }
                .disabled(!canPost)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 14)
        }
    }

    private var canPost: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !draftText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func post() {
        guard canPost else { return }
        let recentStill = dataVM.lastStillCapturedAt.map { abs($0.timeIntervalSinceNow) < 120 } ?? false
        store.add(
            authorName:        draftName.trimmingCharacters(in: .whitespaces),
            text:              draftText.trimmingCharacters(in: .whitespaces),
            lux:               dataVM.lux,
            isRecording:       dataVM.isRecording,
            triggerLabel:      dataVM.triggerStateLabel,
            enclosureTempC:    dataVM.enclosureTempC,
            recordingDuration: dataVM.recordingDurationString,
            hasThumbnail:      recentStill
        )
        draftText = ""
    }
}

// MARK: – Note row
private struct NoteRow: View {
    let note: Note
    @ObservedObject private var settings = AppSettings.shared

    private static let absFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM HH:mm"
        f.timeZone   = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.authorName)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Text(Self.absFormatter.string(from: note.timestamp))
                    .font(Theme.dataLabel(size: 9))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiary)
            }
            Text("\(settings.deploymentName) · \(settings.positionName)")
                .font(.system(size: 10, weight: .regular))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiary)
                .textCase(.uppercase)
            Text(note.text)
                .font(Theme.bodyMono(size: 13))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if note.hasThumbnail {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.165, green: 0.165, blue: 0.157))
                    .frame(width: 80, height: 45)
            }
        }
    }
}
