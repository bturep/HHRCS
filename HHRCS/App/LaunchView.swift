import SwiftUI

struct LaunchView: View {
    let onAdvance: (Int) -> Void

    private enum Phase { case p1, p2, p3, failed(String) }

    @State private var phase:        Phase              = .p1
    @State private var dotCount:     Int                = 0
    @State private var ellipsisTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: -6) {
                letterRow(letter: "H", word: "UNTER")
                letterRow(letter: "H", word: "OUSE")
                letterRow(letter: "R", word: "EMOTE")
                letterRow(letter: "C", word: "AMERA")
                letterRow(letter: "S", word: "YSTEM")
            }

            VStack {
                Spacer()
                statusBlock
                    .padding(.bottom, 20)
            }
        }
        .onAppear { Task { @MainActor in await runPreflight() } }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if case .failed(let msg) = phase {
            failedView(msg)
        } else {
            activeView
        }
    }

    @ViewBuilder
    private var activeView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(phaseLabel)
                Text(String(repeating: ".", count: dotCount)
                     + String(repeating: " ", count: 3 - dotCount))
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .tracking(2.0)
            .foregroundStyle(Theme.tertiary)

            Text(versionString)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(white: 0.28))
        }
    }

    @ViewBuilder
    private func failedView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Text("NO SIGNAL")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Theme.accentOrange)

            if !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { onAdvance(0) } label: {
                Text("CONTINUE OFFLINE")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accentOrange)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button { Task { @MainActor in await runPreflight() } } label: {
                Text("RETRY")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)

            Button { onAdvance(3) } label: {
                Text("OPEN SETTINGS →")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color(white: 0.38))
            }
            .buttonStyle(.plain)

            Text(versionString)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(white: 0.28))
        }
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

    private var phaseLabel: String {
        switch phase {
        case .p1:     return "INITIALIZING"
        case .p2:     return "ESTABLISHING LINK"
        case .p3:     return "CONNECTING TO FIELD"
        case .failed: return ""
        }
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "—"
        return "v\(v) (\(b))"
    }

    // MARK: – Preflight sequence

    @MainActor
    private func runPreflight() async {
        phase = .p1
        startEllipsis()

        // Phase 1: INITIALIZING — /status (advance when done, min 2s display)
        let t1 = Date()
        let (ok, errMsg) = await pingStatus()
        let remain = 2.0 - Date().timeIntervalSince(t1)
        if remain > 0 { try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000)) }

        guard ok else {
            stopEllipsis()
            phase = .failed(errMsg)
            return
        }

        // Phase 2: ESTABLISHING LINK — wait for camReachable (max 4s)
        phase = .p2
        let base2 = AppSettings.shared.piServerURL
        var camUp = false
        if !base2.isEmpty, let camURL = URL(string: base2 + "/camera/status") {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                var req = URLRequest(url: camURL)
                req.timeoutInterval = 1.5
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reachable = json["cam_reachable"] as? Bool, reachable {
                    camUp = true
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        if !camUp {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Phase 3: CONNECTING TO FIELD — 4s
        phase = .p3
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        stopEllipsis()
        onAdvance(0)
    }

    private func startEllipsis() {
        ellipsisTask?.cancel()
        dotCount = 0
        ellipsisTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { break }
                dotCount = (dotCount + 1) % 4
            }
        }
    }

    private func stopEllipsis() {
        ellipsisTask?.cancel()
        ellipsisTask = nil
        dotCount = 0
    }

    private func pingStatus() async -> (Bool, String) {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/status") else {
            return (false, "No URL configured — open Settings")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            UserDefaults.standard.set(data, forKey: "lastKnownStatus")
            return (true, "")
        } catch {
            return (false, buildOfflineSummary())
        }
    }

    private func buildOfflineSummary() -> String {
        if let cached = UserDefaults.standard.data(forKey: "lastKnownStatus"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            var parts: [String] = []
            if let sim = json["yolo_sim_mode"] as? Bool { parts.append(sim ? "sim" : "live") }
            if let cam = json["cam_reachable"] as? Bool { parts.append(cam ? "cam OK" : "cam unreachable") }
            parts.append("check power and network")
            return parts.joined(separator: " · ")
        }
        return "Pi unreachable · check power and network"
    }
}
