import SwiftUI

private enum FieldSegment: String, CaseIterable {
    case stills = "STILLS"
    case agent  = "AGENT"
    case log    = "LOG"
}

struct NotesTabView: View {
    @EnvironmentObject var dataVM: DataViewModel
    @ObservedObject private var settings = AppSettings.shared

    @StateObject private var logStore = SessionLogStore()
    @State private var segment: FieldSegment = .stills
    @State private var agentQueryDraft = ""
    @State private var hasSentQuery      = false
    @State private var startupQueryFired  = false
    @State private var startupScrollDone  = false
    @State private var startupFiredAt: Date? = nil
    @State private var startupChatWasEmpty = true
    @State private var pendingUserMessage: String? = nil
    @State private var isAgentTyping = false

    @FocusState private var composerFocused: Bool

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
                        Text(s.rawValue)
                            .font(Theme.label(size: 11))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(segment == s ? settings.activeColor : Theme.tertiary)
                            .fontWeight(segment == s ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)
            .frame(height: 32)

            HRule().padding(.horizontal, Theme.pagePadding)

            TabView(selection: $segment) {
                StillsGalleryView()
                    .tag(FieldSegment.stills)
                agentContent
                    .tag(FieldSegment.agent)
                logContent
                    .tag(FieldSegment.log)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.background)
        .onChange(of: segment) { _, newSeg in
            if newSeg == .log { dataVM.startDetectionHistoryPolling() }
            else { dataVM.stopDetectionHistoryPolling() }
        }
        .onDisappear { dataVM.stopDetectionHistoryPolling() }
    }

    // MARK: – LOG tab

    private var logContent: some View {
        SessionLogView(
            store: logStore,
            agentEntries: settings.piAgentLogEnabled
                ? dataVM.aiLogEntries.filter { $0.type == "summary" }
                : [],
            detectionEntries: dataVM.detectionHistory
        )
        .onAppear  { dataVM.startDetectionHistoryPolling() }
        .onDisappear { dataVM.stopDetectionHistoryPolling() }
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
                        // Optimistic: show pending user message + typing indicator
                        if let pending = pendingUserMessage {
                            pendingUserBubble(text: pending)
                        }
                        if isAgentTyping {
                            TypingIndicatorView()
                        }
                        Color.clear.frame(height: 0).id("bottomAnchor")
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    withAnimation(.none) { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
                    guard !startupQueryFired else { return }
                    startupChatWasEmpty = queries.isEmpty
                    startupQueryFired   = true
                    startupFiredAt      = Date()
                    Task { await fireStartupQuery() }
                }
                .onChange(of: queries.count) { oldCount, newCount in
                    // New entry arrived — clear pending state
                    if newCount > oldCount {
                        pendingUserMessage = nil
                        isAgentTyping = false
                    }
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
                .onChange(of: isAgentTyping) { _, typing in
                    if typing {
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
                    pendingUserMessage  = nil
                    isAgentTyping      = false
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
                    .tint(Theme.text1)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { submitAgentQuery() }
                    .focused($composerFocused)
                Button(action: submitAgentQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSendQuery ? settings.activeColor : Theme.tertiary)
                }
                .disabled(!canSendQuery)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
            .background(Theme.background)
            .environment(\.colorScheme, .dark)

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
        composerFocused = false
        hasSentQuery = true
        pendingUserMessage = text
        isAgentTyping = true
        Task {
            let base = AppSettings.shared.piServerURL
            guard !base.isEmpty, let url = URL(string: base + "/agent-log/query") else {
                pendingUserMessage = nil
                isAgentTyping = false
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["question": text])
            req.timeoutInterval = 30
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

// MARK: – Pending user bubble (optimistic render)

extension NotesTabView {
    @ViewBuilder
    func pendingUserBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.secondary, lineWidth: 1)
                )
        }
    }
}

// MARK: – Typing indicator (three pulsing dots)

private struct TypingIndicatorView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var phase: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.text3)
                        .frame(width: 5, height: 5)
                        .opacity(i == phase ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(settings.activeColor.opacity(0.15))
            .cornerRadius(10)
            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: – Chat exchange (user question + agent response)

private struct ChatExchangeView: View {
    let entry: AILogEntry
    @ObservedObject private var settings = AppSettings.shared

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

            // Agent bubble — left-aligned, warm tint background
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.content)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.text1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(settings.activeColor.opacity(0.15))
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
