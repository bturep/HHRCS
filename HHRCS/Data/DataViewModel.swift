import Foundation
import Combine
import SwiftUI

enum TriggerState: Equatable {
    case holding
    case active
    case countdown(Int)
}

@MainActor
final class DataViewModel: ObservableObject {

    // MARK: – Light
    @Published var lux:        Double = 1240
    @Published var ev:         Double = 10.2
    @Published var ndPosition: Int    = 4
    @Published var iso:        Int    = 400

    // MARK: – Camera
    @Published var isRecording:      Bool   = true
    @Published var recordingSeconds: Int    = 7243
    @Published var ssdRemainingGB:   Double = 312.4
    @Published var ssdTotalGB:       Double = 480.0

    // MARK: – Trigger
    @Published var triggerState:       TriggerState = .holding
    @Published var lastDetectionClass: String       = "deer"
    @Published var lastDetectionTime:  Date         = Date().addingTimeInterval(-127)
    @Published var countdownValue:     Int          = 0

    // MARK: – Enclosure
    @Published var enclosureTempC:    Double = 18.3
    @Published var enclosureHumidity: Double = 61.5
    @Published var pressure:          Double = 1013.2
    @Published var cpuTemp:           Double = 52.4
    @Published var smpteTimecode:     String = "00:00:00:00"

    var dewPoint: Double {
        enclosureTempC - ((100.0 - enclosureHumidity) / 5.0)
    }

    // MARK: – Storage
    @Published var driveUsedPercent: Double = 47.3
    let driveTotalTB: Double = 6.0
    var driveUsedTB: Double { driveTotalTB * driveUsedPercent / 100.0 }

    // MARK: – Still capture
    @Published var lastStillData:        Data? = nil
    @Published var lastStillCapturedAt:  Date? = nil
    @Published var stills:               [CapturedStill] = []

    // MARK: – Connectivity
    @Published var lastPollAt: Date = Date()

    // MARK: – Camera controls
    @Published var shutterAngle: Double = 180.0
    @Published var wbKelvin:     Int    = 5600
    @Published var fps:          Int    = 24

    // MARK: – AI Agent Log
    @Published var aiLogEntries: [AILogEntry] = []

    // MARK: – Weather & Astro
    @Published var weather:      WeatherData?
    @Published var weatherError: String?
    @Published var astro:        AstroData?
    @Published var astroError:   String?

    // MARK: – Private
    private var simTask:     Task<Void, Never>?
    private var trigTask:    Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let detectionClasses = ["deer", "fox", "raccoon", "coyote",
                                    "bird", "squirrel", "cat", "person"]

    private static let detectionTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Vancouver")
        return f
    }()

    init() {
        startSimulation()
        startTriggerCycle()
        startSMPTETimer()
        aiLogEntries = AILogEntry.simulatedEntries()
        stills = CapturedStill.simulatedEntries()
        Task { await refreshWeather() }
        Task { await refreshAstro() }

        AppSettings.shared.$latitude
            .combineLatest(AppSettings.shared.$longitude)
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _, _ in
                guard let self else { return }
                Task { await self.refreshWeather() }
                Task { await self.refreshAstro() }
            }
            .store(in: &cancellables)
    }

    deinit {
        simTask?.cancel()
        trigTask?.cancel()
    }

    func refreshWeather() async {
        weatherError = nil
        let s = AppSettings.shared
        do {
            weather = try await WeatherService.fetch(latitude: s.latitude, longitude: s.longitude)
        } catch {
            weatherError = error.localizedDescription
        }
    }

    func refreshAstro() async {
        astroError = nil
        let s = AppSettings.shared
        do {
            astro = try await AstroService.fetch(latitude: s.latitude, longitude: s.longitude)
        } catch {
            astroError = error.localizedDescription
        }
    }

    // MARK: – Simulation
    private func startSimulation() {
        simTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                tick()
            }
        }
    }

    private func tick() {
        lastPollAt = Date()
        lux  += Double.random(in: -40...40)
        lux   = max(80, min(8000, lux))
        ev    = lux > 0 ? log2(lux / 2.5) : 0.0
        ev    = (ev * 10).rounded() / 10

        if isRecording { recordingSeconds += 2 }
        ssdRemainingGB -= isRecording ? 0.0014 : 0

        enclosureTempC    += Double.random(in: -0.15...0.15)
        enclosureTempC     = (enclosureTempC * 10).rounded() / 10
        enclosureHumidity += Double.random(in: -0.4...0.4)
        enclosureHumidity  = max(20, min(99, (enclosureHumidity * 10).rounded() / 10))

        cpuTemp  += Double.random(in: -0.3...0.3)
        cpuTemp   = max(40, min(85, (cpuTemp * 10).rounded() / 10))
        pressure += Double.random(in: -0.1...0.1)
        pressure  = (pressure * 10).rounded() / 10

        driveUsedPercent  += 0.002
        driveUsedPercent   = min(100, driveUsedPercent)
    }

    // MARK: – SMPTE timecode (simulated 24fps from wall clock)
    private func startSMPTETimer() {
        Timer.publish(every: 1.0 / 12.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.smpteTimecode = Self.computeSMPTE() }
            .store(in: &cancellables)
    }

    private static func computeSMPTE() -> String {
        let total = Int(Date().timeIntervalSince1970 * 24.0)
        let ff = total % 24
        let ss = (total / 24) % 60
        let mm = (total / 24 / 60) % 60
        let hh = (total / 24 / 3600) % 24
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }

    // MARK: – Trigger state machine
    private func startTriggerCycle() {
        trigTask = Task {
            while !Task.isCancelled {
                let holdSecs = Int.random(in: 8...20)
                try? await Task.sleep(nanoseconds: UInt64(holdSecs) * 1_000_000_000)
                guard !Task.isCancelled else { return }

                triggerState       = .active
                lastDetectionClass = detectionClasses.randomElement()!
                lastDetectionTime  = Date()

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }

                for i in stride(from: 5, through: 1, by: -1) {
                    triggerState = .countdown(i)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                }

                triggerState = .holding
            }
        }
    }

    // MARK: – Formatted helpers
    var recordingDurationString: String {
        let h = recordingSeconds / 3600
        let m = (recordingSeconds % 3600) / 60
        let s = recordingSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var triggerStateLabel: String {
        switch triggerState {
        case .holding:          return "HOLDING"
        case .active:           return "ACTIVE"
        case .countdown(let n): return "T–\(n)"
        }
    }

    var triggerStateColor: Color {
        switch triggerState {
        case .active:    return Theme.accent
        case .holding:   return .white
        case .countdown: return Color(red: 0.541, green: 0.541, blue: 0.522) // #8A8A85
        }
    }

    var lastDetectionTimeString: String {
        Self.detectionTimeFmt.string(from: lastDetectionTime)
    }

    var ssdUsedPercent: Double {
        guard ssdTotalGB > 0 else { return 0 }
        return ((ssdTotalGB - ssdRemainingGB) / ssdTotalGB) * 100
    }

    // MARK: – Pi commands
    func triggerStill() async {
        await sendPiCommand("/still/trigger")
        await captureAndStoreSnapshot(triggerType: "manual")
    }

    func toggleRecord() async {
        await sendPiCommand("/record/toggle")
        isRecording.toggle()
        if isRecording {
            await captureAndStoreSnapshot(triggerType: "manual")
        }
    }

    func setND(_ value: Int) async {
        await sendPiCommand("/nd/\(value)")
        ndPosition = value
    }

    func setISO(_ value: Int) async {
        await sendPiCommand("/iso/\(value)")
        iso = value
    }

    func setShutterAngle(_ angle: Double) async {
        shutterAngle = angle
        await sendPiCommandJSON("/control/shutter", body: ["angle": angle])
    }

    func setWB(_ kelvin: Int) async {
        wbKelvin = kelvin
        guard kelvin > 0 else { return }
        await sendPiCommandJSON("/control/wb", body: ["kelvin": kelvin])
    }

    func setFPS(_ newFPS: Int) async {
        fps = newFPS
        await sendPiCommandJSON("/control/fps", body: ["fps": newFPS])
    }

    private func captureAndStoreSnapshot(triggerType: String) async {
        let base = AppSettings.shared.streamBaseURL
        if !base.isEmpty,
           let url = URL(string: base + "/snapshot"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           !data.isEmpty {
            lastStillData       = data
            lastStillCapturedAt = Date()
            stills.insert(CapturedStill(piCamImageData: data, triggerType: triggerType), at: 0)
        } else {
            let still = CapturedStill(triggerType: triggerType)
            stills.insert(still, at: 0)
            lastStillCapturedAt = Date()
            lastStillData       = nil
        }
    }

    private func sendPiCommand(_ path: String) async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
    }

    private func sendPiCommandJSON(_ path: String, body: [String: Any]) async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
    }
}
