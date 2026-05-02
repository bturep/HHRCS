import SwiftUI

struct LaunchView: View {
    let onAdvance: (Int) -> Void

    @ObservedObject private var settings = AppSettings.shared

    @State private var statusText:  String = "CONNECTING..."
    @State private var statusColor: Color  = Theme.tertiary
    @State private var summaryText: String = ""
    @State private var showSummary: Bool   = false
    @State private var showActions: Bool   = false
    @State private var opacity:     Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Center block — HHRCS letter stack
            VStack(alignment: .leading, spacing: -6) {
                letterRow(letter: "H", word: "UNTER")
                letterRow(letter: "H", word: "OUSE")
                letterRow(letter: "R", word: "EMOTE")
                letterRow(letter: "C", word: "AMERA")
                letterRow(letter: "S", word: "YSTEM")
            }

            // Bottom overlay
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    Text(statusText)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(statusColor)

                    if showSummary {
                        Text(summaryText)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 32)
                    }

                    if showActions {
                        Button { advance(toTab: 3) } label: {
                            Text("OPEN SETTINGS →")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(Theme.accentOrange)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        Button { Task { await attemptConnection() } } label: {
                            Text("RETRY")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(Theme.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }

                    Text(appVersionString)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.bottom, 16)
            }
        }
        .opacity(opacity)
        .onAppear { Task { await attemptConnection() } }
    }

    @ViewBuilder
    private func letterRow(letter: String, word: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(letter)
                .font(.system(size: 36, weight: .heavy, design: .default))
                .foregroundStyle(Theme.accentOrange.opacity(0.82))
            Text(word)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(4.0)
                .foregroundStyle(.white)
        }
    }

    // MARK: – Version

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "—"
        return "v\(v) (\(b))"
    }

    // MARK: – Connection

    private func attemptConnection() async {
        statusText  = "CONNECTING..."
        statusColor = Theme.tertiary
        showSummary = false
        showActions = false

        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/status") else {
            statusText  = "NO URL CONFIGURED"
            statusColor = Theme.accentOrange
            summaryText = "Set Pi server URL in Settings to connect."
            showSummary = true
            showActions = true
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            UserDefaults.standard.set(data, forKey: "lastKnownStatus")
            withAnimation(.easeInOut(duration: 0.2)) {
                statusText  = "CONNECTED"
                statusColor = Theme.text
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            advance(toTab: 0)
        } catch {
            await handleFailure(base: base)
        }
    }

    private func handleFailure(base: String) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            statusText  = "PI UNREACHABLE"
            statusColor = Theme.accentOrange
        }

        if let url = URL(string: base + "/diagnostics") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 4
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                summaryText = buildSummary(fromDiagnostics: json)
                withAnimation { showSummary = true; showActions = true }
                return
            }
        }

        if let cached = UserDefaults.standard.data(forKey: "lastKnownStatus"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            summaryText = buildSummary(fromStatus: json)
        } else {
            summaryText = "No prior connection data available."
        }
        withAnimation { showSummary = true; showActions = true }
    }

    private func buildSummary(fromDiagnostics json: [String: Any]) -> String {
        if let line = json["summary_line"] as? String { return line }
        var parts: [String] = []
        if let sim = json["sim_mode"]       as? Bool   { parts.append(sim ? "sim mode" : "live mode") }
        if let ble = json["ble_state"]      as? String { parts.append("BLE \(ble.lowercased())") }
        if let n   = json["detections_24h"] as? Int    { parts.append("\(n) detections today") }
        parts.append("Check power and network")
        return parts.joined(separator: " · ")
    }

    private func buildSummary(fromStatus json: [String: Any]) -> String {
        var parts: [String] = ["Last known"]
        if let sim = json["yolo_sim_mode"]   as? Bool   { parts.append(sim ? "sim mode" : "live mode") }
        if let ble = json["esp32_ble_state"] as? String { parts.append("BLE \(ble.lowercased())") }
        parts.append("Check power and network")
        return parts.joined(separator: " · ")
    }

    // MARK: – Navigation

    private func advance(toTab tab: Int) {
        withAnimation(.easeIn(duration: 0.35)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onAdvance(tab) }
    }
}
