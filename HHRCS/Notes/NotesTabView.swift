import SwiftUI

private enum FieldSegment: String, CaseIterable {
    case agent  = "AGENT"
    case stills = "STILLS"
    case log    = "LOG"
}

struct NotesTabView: View {
    @EnvironmentObject var dataVM: DataViewModel
    @ObservedObject private var settings = AppSettings.shared

    @StateObject private var logStore = SessionLogStore()
    @State private var segment: FieldSegment = .agent
    @State private var agentQueryDraft = ""
    @State private var hasSentQuery      = false
    @State private var startupQueryFired  = false
    @State private var startupScrollDone  = false
    @State private var startupFiredAt: Date? = nil
    @State private var startupChatWasEmpty = true

    private var queryEntries: [AILogEntry] {
        dataVM.aiLogEntries
            .filter { $0.type == "query" }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var latestSummary: AILogEntry? {
        dataVM.aiLogEntries
            .filter { $0.type == "summary" }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                ForEach(FieldSegment.allCases, id: \.self) { s in
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

            switch segment {
            case .log:    logContent
            case .agent:  agentContent
            case .stills: StillsGalleryView()
            }
        }
        .background(Theme.background)
    }

    // MARK: – LOG tab

    private var logContent: some View {
        SessionLogView(
            store: logStore,
            agentEntries: settings.piAgentLogEnabled
                ? dataVM.aiLogEntries.filter { $0.type == "summary" }
                : []
        )
    }

    // MARK: – AGENT tab

    private var agentContent: some View {
        VStack(spacing: 0) {
            // Pinned summary card — static, does not scroll
            if let summary = latestSummary {
                Text(summary.content)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.vertical, 10)
                    .background(Theme.background)
                HRule().padding(.horizontal, Theme.pagePadding)
            }

            // Chat area — query entries only
            let queries = queryEntries

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(queries) { entry in
                            ChatExchangeView(entry: entry)
                        }
                        Color.clear.frame(height: 0).id("bottomAnchor")
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    withAnimation(.none) { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
                    guard !startupQueryFired else { return }
                    startupChatWasEmpty = queries.isEmpty
                    startupQueryFired   = true
                    startupFiredAt      = Date()
                    Task { await fireStartupQuery() }
                }
                .onChange(of: queries.count) {
                    // Anchor startup response to top only when chat was empty at launch
                    if startupQueryFired && !hasSentQuery && !startupScrollDone && startupChatWasEmpty,
                       let firedAt = startupFiredAt,
                       let last = queries.last,
                       last.timestamp >= firedAt.addingTimeInterval(-30) {
                        withAnimation(.none) { proxy.scrollTo(last.id, anchor: .top) }
                        startupScrollDone = true
                        return
                    }
                    if hasSentQuery || (startupQueryFired && !startupChatWasEmpty) {
                        withAnimation(.none) { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
                    }
                }
                .onChange(of: dataVM.deploymentChangeCount) {
                    // New deployment created — reset chat and fire a fresh startup summary
                    hasSentQuery       = false
                    startupQueryFired  = false
                    startupScrollDone  = false
                    startupFiredAt     = nil
                    startupChatWasEmpty = true
                    startupQueryFired  = true
                    startupFiredAt     = Date()
                    Task { await fireStartupQuery() }
                }
            }

            HRule().padding(.horizontal, Theme.pagePadding)

            HStack(alignment: .center, spacing: 10) {
                TextField("Message", text: $agentQueryDraft, axis: .vertical)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(Theme.accentOrange)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { submitAgentQuery() }
                Button(action: submitAgentQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSendQuery ? Theme.accentOrange : Theme.tertiary)
                }
                .disabled(!canSendQuery)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
            .background(Theme.background)

            HRule().padding(.horizontal, Theme.pagePadding)
        }
    }

    private var canSendQuery: Bool {
        !agentQueryDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitAgentQuery() {
        let text = agentQueryDraft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        agentQueryDraft = ""
        hasSentQuery = true
        Task {
            let base = AppSettings.shared.piServerURL
            guard !base.isEmpty, let url = URL(string: base + "/agent-log/query") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["question": text])
            req.timeoutInterval = 10
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func fireStartupQuery() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/agent-log/startup") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: – Chat exchange (user question + agent response)

private struct ChatExchangeView: View {
    let entry: AILogEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User bubble — right-aligned; hidden for startup (empty question)
            if let question = entry.query, !question.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 60)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(question)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.secondary, lineWidth: 1)
                            )
                        Text(Self.timeFmt.string(from: entry.timestamp))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }

            // Agent bubble — left-aligned
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.content)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.cardBackground)
                        .cornerRadius(10)
                    Text(Self.timeFmt.string(from: entry.timestamp))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 60)
            }
        }
    }
}
