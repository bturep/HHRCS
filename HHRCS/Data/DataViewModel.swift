import Foundation
import Combine
import SwiftUI

struct Detection: Identifiable {
    let id         = UUID()
    let label:      String
    let confidence: Double
    let box:        CGRect   // normalized 0–1 (x, y = top-left, w, h)
}

enum TriggerState: Equatable {
    case holding
    case active
    case countdown(Int)
}

@MainActor
final class DataViewModel: ObservableObject {

    // MARK: – Light
    @Published var lux: Double = 1240
    @Published var ev:  Double = 10.2
    @Published var iso: Int    = 400

    // MARK: – Camera
    @Published var isRecording:      Bool   = false  // BMPCC via ESP32
    @Published var isPiCamRecording: Bool   = false  // Pi Camera Module 3
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
    @Published var isCapturingStill:     Bool  = false

    // MARK: – YOLO / machine state (from Pi /status)
    @Published var yoloLocked:   Bool       = false
    @Published var machineState: String     = "IDLE"
    @Published var detections:   [Detection] = []

    // MARK: – Connectivity
    @Published var lastPollAt: Date = Date()

    // MARK: – Camera controls
    @Published var shutterAngle: Double = 180.0
    @Published var wbKelvin:     Int    = 5600

    // MARK: – AI Agent Log
    @Published var aiLogEntries: [AILogEntry] = []

    // MARK: – Event Log (live from Pi /log)
    @Published var eventLog:       [EventLogLine]  = []
    @Published var eventLogFilter: EventLogFilter  = .all

    var filteredEventLog: [EventLogLine] {
        guard eventLogFilter != .all else { return eventLog }
        return eventLog.filter { $0.label == eventLogFilter.rawValue }
    }

    // MARK: – Weather & Astro
    @Published var weather:      WeatherData?
    @Published var weatherError: String?
    @Published var astro:        AstroData?
    @Published var astroError:   String?

    // MARK: – System health (polled from Pi /status every 5s)
    @Published var healthPiReachable:     Bool    = false
    @Published var healthBridgeReachable: Bool    = false
    @Published var healthBleConnected:    Bool    = false
    @Published var healthYoloRunning:     Bool    = false
    @Published var healthYoloSimMode:     Bool    = true
    @Published var healthIsRecording:     Bool    = false
    @Published var healthEsp32BleState:   String  = "—"
    @Published var healthSsdMounted:            Bool    = false
    @Published var healthSsdFreePct:            Double  = 0
    @Published var healthDetectLastAgoSec:      Double? = nil
    @Published var healthLastPollAt:            Date?   = nil
    @Published var healthLastError:             String? = nil

    // MARK: – Deployment
    @Published var deploymentChangeCount: Int = 0

    func resetForNewDeployment() {
        eventLog     = []
        aiLogEntries = []
        deploymentChangeCount += 1
    }

    // MARK: – Private
    private var simTask:          Task<Void, Never>?
    private var trigTask:         Task<Void, Never>?
    private var healthTask:       Task<Void, Never>?
    private var logTask:          Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // Cold-start guard: don't let a stale Pi "recording: true" make the button
    // orange on first launch. isRecording can only go true via the poll after
    // we've first received at least one "not recording" response.
    private var seenNotRecording = false

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
        startAutoStillTimer()
        if AppSettings.shared.piServerURL.isEmpty {
            aiLogEntries = AILogEntry.simulatedEntries()
        }
        stills = CapturedStill.simulatedEntries()
        Task { await refreshWeather() }
        Task { await refreshAstro() }
        startHealthPolling()
        startLogPolling()
        startNotificationPolling()

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
        healthTask?.cancel()
        logTask?.cancel()
        notificationTask?.cancel()
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

    // MARK: – Auto-still (checks every 60s, fires when AppSettings.thirtyMinStills && 30min elapsed)

    private func startAutoStillTimer() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.checkAutoStill() }
            }
            .store(in: &cancellables)
    }

    private func checkAutoStill() async {
        guard AppSettings.shared.thirtyMinStills else { return }
        guard let last = lastStillCapturedAt else { return }
        guard Date().timeIntervalSince(last) >= 1800 else { return }
        guard !isCapturingStill else { return }
        await captureStill()
    }

    // MARK: – Health polling (every 5s, real Pi regardless of sim mode)

    private struct HealthPoll: Decodable {
        struct DetectionItem: Decodable {
            let label:      String
            let confidence: Double
            let box:        [Double]   // [x, y, w, h] normalized 0–1
        }

        let esp32Connected:       Bool?
        let esp32BridgeReachable: Bool?
        let esp32BleState:        String?
        let yoloRunning:          Bool?
        let yoloSimMode:          Bool?
        let ssdMounted:                    Bool?
        let ssdFreePct:                    Double?
        let detectorLastInferenceAgoSec:   Double?
        let recording:                     Bool?
        let machineState:         String?
        let detections:           [DetectionItem]?

        enum CodingKeys: String, CodingKey {
            case esp32Connected       = "esp32_connected"
            case esp32BridgeReachable = "esp32_bridge_reachable"
            case esp32BleState        = "esp32_ble_state"
            case yoloRunning          = "yolo_running"
            case yoloSimMode          = "yolo_sim_mode"
            case ssdMounted                  = "ssd_mounted"
            case ssdFreePct                  = "ssd_free_pct"
            case detectorLastInferenceAgoSec = "detector_last_inference_ago_seconds"
            case recording
            case machineState         = "machine_state"
            case detections
        }
    }

    func refreshHealth() async {
        await pollHealth()
    }

    private func startHealthPolling() {
        healthTask = Task {
            while !Task.isCancelled {
                await pollHealth()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollHealth() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/status") else {
            healthPiReachable = false
            healthLastError   = "Pi server URL not configured"
            return
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 4
            let (data, _) = try await URLSession.shared.data(for: req)
            UserDefaults.standard.set(data, forKey: "lastKnownStatus")
            let poll = try JSONDecoder().decode(HealthPoll.self, from: data)
            healthPiReachable     = true
            healthBridgeReachable = poll.esp32BridgeReachable ?? false
            let wasConnected      = healthBleConnected
            healthBleConnected    = poll.esp32Connected       ?? false
            healthEsp32BleState   = poll.esp32BleState        ?? "—"
            healthYoloRunning     = poll.yoloRunning          ?? false
            healthYoloSimMode     = poll.yoloSimMode          ?? true
            healthIsRecording     = poll.recording            ?? false
            let bleUp             = poll.esp32Connected       ?? false
            // Re-arm the cold-start guard on every BLE reconnect so a stale
            // recording:true from the Pi can't immediately light the button.
            if bleUp && !wasConnected { seenNotRecording = false }
            let piRecording       = (poll.recording ?? false) && bleUp
            if !piRecording { seenNotRecording = true }
            isRecording           = seenNotRecording ? piRecording : false
            healthSsdMounted         = poll.ssdMounted                  ?? false
            healthSsdFreePct         = poll.ssdFreePct                  ?? 0
            healthDetectLastAgoSec   = poll.detectorLastInferenceAgoSec
            healthLastPollAt         = Date()
            healthLastError       = nil

            // Machine state & YOLO lock
            let ms = poll.machineState ?? "IDLE"
            machineState = ms
            yoloLocked   = (ms == "ACTIVE") && (poll.recording ?? false)

            // Real detections from Pi
            if let items = poll.detections {
                detections = items.compactMap { item in
                    guard item.box.count == 4 else { return nil }
                    return Detection(
                        label:      item.label,
                        confidence: item.confidence,
                        box: CGRect(x: item.box[0], y: item.box[1],
                                    width: item.box[2], height: item.box[3])
                    )
                }
            } else {
                detections = []
            }
        } catch {
            healthPiReachable = false
            healthLastError   = error.localizedDescription
        }
    }

    // MARK: – Notification polling (every 2s, parallel to health)

    private func startNotificationPolling() {
        notificationTask = Task {
            while !Task.isCancelled {
                await NotificationPoller.shared.pollAndSurface()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: – Event log + agent log polling (every 3s)

    private func startLogPolling() {
        logTask = Task {
            while !Task.isCancelled {
                await pollEventLog()
                await pollAgentLog()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refreshEventLog() async {
        await pollEventLog()
    }

    private func pollEventLog() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/log?window=300") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { EventLogLine.parse($0) }
            .reversed()
        eventLog = Array(lines.prefix(200))
    }

    private struct AgentLogItem: Decodable {
        let type:      String
        let content:   String
        let query:     String?
        let source:    String?
        let timestamp: String?

        enum CodingKeys: String, CodingKey {
            case type
            case content = "response"
            case query
            case source
            case timestamp
        }
    }

    private static let agentLogDateFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let agentLogDateFmtNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func pollAgentLog() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/agent-log?limit=50") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let items = try? JSONDecoder().decode([AgentLogItem].self, from: data) else { return }
        let parsed: [AILogEntry] = items.map { item in
            let ts: Date = {
                guard let s = item.timestamp else { return Date() }
                return Self.agentLogDateFmt.date(from: s)
                    ?? Self.agentLogDateFmtNoFrac.date(from: s)
                    ?? Date()
            }()
            return AILogEntry(
                id:        UUID(),
                timestamp: ts,
                type:      item.type,
                source:    item.source ?? "pi_agent",
                content:   item.content,
                query:     item.query,
                data:      nil
            )
        }
        aiLogEntries = parsed
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

    var hasSystemAlert: Bool {
        !healthPiReachable || !healthBridgeReachable || healthEsp32BleState != "Connected"
    }

    // MARK: – Pi commands

    // BMPCC record via ESP32 bridge
    func toggleBmpccRecord() async {
        print("[REC] toggleBmpccRecord — isRecording=\(isRecording), bleConnected=\(healthBleConnected), bleState=\(healthEsp32BleState)")
        if isRecording {
            print("[REC] → STOP")
            await sendPiCommand("/control/record/stop")
            isRecording = false
        } else {
            print("[REC] → START")
            await sendPiCommand("/control/record/start")
            isRecording = true
            await captureAndStoreSnapshot(triggerType: "manual")
        }
        print("[REC] done — isRecording now \(isRecording)")
    }

    // Pi Camera Module 3 record — visual-only toggle, no Pi endpoint yet
    func togglePiCamRecord() {
        isPiCamRecording.toggle()
    }

    // BMPCC still via ESP32 bridge
    func captureBmpccStill() async {
        await sendPiCommand("/control/still")
    }

    func captureStill() async {
        guard !isCapturingStill else { return }
        isCapturingStill = true
        let piBase = AppSettings.shared.piServerURL
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if !piBase.isEmpty, let url = URL(string: piBase + "/still/trigger") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            _ = try? await URLSession.shared.data(for: req)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !piBase.isEmpty {
            for path in ["/stills/latest", "/snapshot"] {
                guard let url = URL(string: piBase + path) else { continue }
                if let (data, resp) = try? await URLSession.shared.data(from: url),
                   let http = resp as? HTTPURLResponse,
                   http.statusCode == 200,
                   !data.isEmpty {
                    lastStillData       = data
                    lastStillCapturedAt = Date()
                    isCapturingStill    = false
                    return
                }
            }
        }
        isCapturingStill = false
    }

    func setISO(_ value: Int) async {
        await sendPiCommandJSON("/control/iso", body: ["iso": value])
        iso = value
    }

    func setShutterAngle(_ angle: Double) async {
        shutterAngle = angle
        await sendPiCommandJSON("/control/shutter", body: ["angle": angle])
    }

    func setWB(_ kelvin: Int) async {
        wbKelvin = kelvin
        await sendPiCommandJSON("/control/wb", body: ["kelvin": kelvin])
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
        guard !base.isEmpty, let url = URL(string: base + path) else {
            print("[Pi] \(path) — piServerURL not configured")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        if let (data, resp) = try? await URLSession.shared.data(for: req) {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<binary>"
            print("[Pi] POST \(path) → HTTP \(code) | \(body)")
        } else {
            print("[Pi] POST \(path) — network error / timeout")
        }
    }

    private func sendPiCommandJSON(_ path: String, body: [String: Any]) async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + path) else {
            print("[Pi] \(path) \(body) — piServerURL not configured")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 5
        if let (_, resp) = try? await URLSession.shared.data(for: req) {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            print("[Pi] POST \(path) \(body) → HTTP \(code)")
        } else {
            print("[Pi] POST \(path) \(body) — network error")
        }
    }
}
