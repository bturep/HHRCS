import SwiftUI

// MARK: – Model

private struct ChatMessage: Identifiable {
    let id   = UUID()
    let role: String   // "user" or "assistant"
    var content: String
}

// MARK: – View

struct FieldAgentView: View {
    @EnvironmentObject var dataVM:  DataViewModel
    @EnvironmentObject var store:   NotesStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var messages:   [ChatMessage] = []
    @State private var draft:      String        = ""
    @State private var isSending:  Bool          = false
    @State private var errorText:  String?       = nil
    @State private var scrollID:   UUID?         = nil

    private let suggestions = [
        "What happened this morning?",
        "Any patterns this week?",
        "Is tonight a good session?"
    ]

    var body: some View {
        if settings.anthropicAPIKey.isEmpty {
            noKeyState
        } else {
            chatView
        }
    }

    private var noKeyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No API key")
                .font(Theme.dataLabel(size: 11))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.secondary)
            Text("Add your Anthropic API key in Settings › Agent")
                .font(Theme.statusCaption(size: 11))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            if messages.isEmpty && !isSending {
                emptyState
            } else {
                messageList
            }

            if let err = errorText {
                Text(err)
                    .font(Theme.statusCaption(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 4)
            }

            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(height: 1)

            composeBar
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
                .background(Color(red: 0.102, green: 0.102, blue: 0.094))
        }
    }

    // MARK: – Empty state with suggestion pills

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Field assistant")
                .font(Theme.dataLabel(size: 11))
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { pill in
                    Button(action: { sendMessage(pill) }) {
                        Text(pill)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.rule, lineWidth: Theme.ruleWidth)
                            )
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    // MARK: – Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if isSending {
                        HStack(spacing: 6) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(Theme.tertiary)
                                    .frame(width: 4, height: 4)
                                    .opacity(0.5)
                            }
                        }
                        .padding(.leading, Theme.pagePadding)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, Theme.pagePadding)
            }
            .onChange(of: scrollID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    // MARK: – Compose bar

    private var composeBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("ask the agent...", text: $draft, axis: .vertical)
                .font(Theme.bodyMono(size: 13))
                .foregroundStyle(.white)
                .tint(Theme.accent)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { sendCurrentDraft() }
            Button(action: sendCurrentDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Theme.accent : Theme.tertiary)
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    private func sendCurrentDraft() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        sendMessage(text)
    }

    private func isCommandIntent(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = ["start", "stop", "record", "change", "set", "trigger",
                        "capture", "adjust", "switch", "enable", "disable"]
        return keywords.contains { lower.contains($0) }
    }

    private func sendMessage(_ text: String) {
        errorText = nil

        if !settings.ownerModeEnabled && isCommandIntent(text) {
            let userMsg = ChatMessage(role: "user", content: text)
            messages.append(userMsg)
            let blockMsg = ChatMessage(
                role: "assistant",
                content: "Operator access required to send commands. You can ask questions about current conditions and session history."
            )
            messages.append(blockMsg)
            scrollID = blockMsg.id
            return
        }

        let userMsg = ChatMessage(role: "user", content: text)
        messages.append(userMsg)
        scrollID = userMsg.id
        isSending = true

        Task {
            do {
                let reply = try await callClaudeAPI(userMessage: text)
                let assistantMsg = ChatMessage(role: "assistant", content: reply)
                messages.append(assistantMsg)
                scrollID = assistantMsg.id
                if messages.count > 40 {
                    messages.removeFirst(messages.count - 40)
                }
            } catch {
                errorText = error.localizedDescription
            }
            isSending = false
        }
    }

    // MARK: – Claude API

    private func callClaudeAPI(userMessage: String) async throws -> String {
        let apiKey = settings.anthropicAPIKey
        guard !apiKey.isEmpty else {
            throw AgentError.noAPIKey
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AgentError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,                forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",          forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 30

        let payload: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": buildSystemPrompt(),
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                throw AgentError.apiError(body)
            }
            throw AgentError.apiError("Unexpected response")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = (json?["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else {
            throw AgentError.parseError
        }
        return text
    }

    private func buildSystemPrompt() -> String {
        let vm = dataVM
        let s  = settings

        var parts: [String] = []
        parts.append("""
        You are a field assistant for a wildlife camera deployment called \(s.deploymentName), \
        position \(s.positionName). You help interpret sensor data, camera logs, and animal \
        detection events. Keep responses concise and practical — the operator is in the field.
        """)

        parts.append("""
        CURRENT SENSOR STATE
        Light: \(String(format: "%.0f", vm.lux)) lx  EV \(String(format: "%.1f", vm.ev))  ND\(vm.ndPosition)  ISO \(vm.iso)
        Camera: \(vm.isRecording ? "recording" : "standby")  \(vm.recordingDurationString)  SSD \(String(format: "%.1f", vm.ssdRemainingGB))GB remaining
        Enclosure: \(String(format: "%.1f", vm.enclosureTempC))°C  \(String(format: "%.1f", vm.enclosureHumidity))% RH  \
        dew point \(String(format: "%.1f", vm.dewPoint))°C  CPU \(String(format: "%.1f", vm.cpuTemp))°C
        Trigger: \(vm.triggerStateLabel)  last detection: \(vm.lastDetectionClass) at \(vm.lastDetectionTimeString)
        """)

        if !vm.aiLogEntries.isEmpty {
            let recentAI = vm.aiLogEntries.prefix(8)
            let logLines = recentAI.map { e -> String in
                let ts = DateFormatter.localizedString(from: e.timestamp, dateStyle: .none, timeStyle: .short)
                return "[\(ts)] [\(e.type)] \(e.content)"
            }.joined(separator: "\n")
            parts.append("PI AGENT LOG (recent)\n" + logLines)
        }

        let recentNotes = store.notes.prefix(20)
        if !recentNotes.isEmpty {
            let noteLines = recentNotes.map { n -> String in
                let ts = DateFormatter.localizedString(from: n.timestamp, dateStyle: .none, timeStyle: .short)
                return "[\(ts)] \(n.authorName): \(n.text)"
            }.joined(separator: "\n")
            parts.append("FIELD NOTES (recent)\n" + noteLines)
        }

        if let w = vm.weather {
            parts.append("""
            WEATHER  \(String(format: "%.1f", w.current.temperatureC))°C  \
            wind \(String(format: "%.0f", w.current.windspeedKmh)) km/h  code \(w.current.weatherCode)
            """)
        }

        if let a = vm.astro {
            parts.append("""
            ASTRO  civil dawn \(AstroService.format(a.civilDawn))  \
            sunrise \(AstroService.format(a.sunrise))  \
            sunset \(AstroService.format(a.sunset))  \
            civil dusk \(AstroService.format(a.civilDusk))
            """)
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: – Message bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color(red: 0.165, green: 0.165, blue: 0.157) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isUser ? Color.clear : Theme.rule, lineWidth: isUser ? 0 : Theme.ruleWidth)
                )
                .cornerRadius(4)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: – Errors

private enum AgentError: LocalizedError {
    case noAPIKey
    case invalidURL
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:        return "No API key — set one in SETTINGS › AGENT"
        case .invalidURL:      return "Invalid API URL"
        case .apiError(let m): return "API error: \(m)"
        case .parseError:      return "Unexpected response format"
        }
    }
}
