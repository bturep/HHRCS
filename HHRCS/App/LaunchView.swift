import SwiftUI

struct LaunchView: View {
    let onAdvance: (Int) -> Void

    private enum Phase { case p1, failed(String) }

    @State private var phase:        Phase              = .p1
    @State private var dotCount:     Int                = 0
    @State private var ellipsisTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Image("LaunchBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45))

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
                .foregroundStyle(Theme.text1)

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
                    .foregroundStyle(Theme.text1)
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
    private func letterRow(letter: String, word: String, letterColor: Color = Theme.text1) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(letter)
                .font(.system(size: 36, weight: .heavy, design: .default))
                .foregroundStyle(letterColor.opacity(0.82))
            Text(word)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(4.0)
                .foregroundStyle(.white)
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .p1:     return "INITIALIZING"
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
        // Purely cosmetic — 2.5s display, then ContentView fades it out over 0.5s.
        // Connectivity is reflected in the DATA tab health dots once the app is open.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
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

}
