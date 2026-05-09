import Foundation
import Combine
import SwiftUI

// Tri-state BMPCC recording state — idle / actively recording / BMPCC finalizing clip to SSD
enum RecordingState: Equatable {
    case idle
    case recording
    case finalizing  // ~10s clip flush after stop; resolves to idle once Pi confirms
}

struct DetectionHistoryItem: Identifiable, Decodable {
    let id = UUID()
    let ts:             String
    let detectionClass: String
    let confidence:     Double
    let bbox:           [Double]   // [x_min, y_min, x_max, y_max] normalized 0–1
    let frameW:         Int
    let frameH:         Int

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var timestamp: Date { Self.isoFmt.date(from: ts) ?? Date(timeIntervalSince1970: 0) }

    var cgRect: CGRect {
        guard bbox.count == 4 else { return .zero }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2] - bbox[0], height: bbox[3] - bbox[1])
    }

    enum CodingKeys: String, CodingKey {
        case ts
        case detectionClass = "class"
        case confidence, bbox
        case frameW = "frame_w"
        case frameH = "frame_h"
    }
}

struct ExternalDrive: Decodable, Identifiable {
    var id: String { name }
    let name:       String
    let usedBytes:  Int
    let totalBytes: Int
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
    var usedTB:  Double { Double(usedBytes)  / 1_000_000_000_000 }
    var totalTB: Double { Double(totalBytes) / 1_000_000_000_000 }
    enum CodingKeys: String, CodingKey {
        case name
        case usedBytes  = "used_bytes"
        case totalBytes = "total_bytes"
    }
}

struct StorageSnapshot: Decodable, Identifiable {
    var id: String { date }
    let date:      String
    let usedBytes: Int
    enum CodingKeys: String, CodingKey {
        case date
        case usedBytes = "used_bytes"
    }
}

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
    @Published var lux: Double? = nil
    @Published var ev:  Double? = nil
    @Published var iso: Int     = 400

    // MARK: – Camera
    @Published var isRecording:      Bool            = false
    @Published var recordingState:   RecordingState  = .idle
    @Published var isPiCamRecording: Bool            = false
    @Published var recordingSeconds: Int    = 7243
    @Published var ssdRemainingGB:   Double = 312.4
    @Published var ssdTotalGB:       Double = 480.0

    // MARK: – Trigger
    @Published var triggerState:       TriggerState = .holding
    @Published var lastDetectionClass: String       = "deer"
    @Published var lastDetectionTime:  Date         = Date().addingTimeInterval(-127)
    @Published var countdownValue:     Int          = 0

    // MARK: – Enclosure
    @Published var enclosureTempC:    Double? = nil
    @Published var enclosureHumidity: Double? = nil
    @Published var pressure:          Double? = nil
    @Published var cpuTemp:           Double  = 0.0
    @Published var smpteTimecode:     String  = "00:00:00:00"
    @Published var camTimecode:       String? = nil

    var dewPoint: Double? {
        guard let t = enclosureTempC, let h = enclosureHumidity else { return nil }
        return t - ((100.0 - h) / 5.0)
    }

    // MARK: – Storage
    @Published var driveUsedPercent: Double = 47.3
    let driveTotalTB: Double = 6.0
    var driveUsedTB: Double { driveTotalTB * driveUsedPercent / 100.0 }

    // MARK: – SSD (from Pi storage_monitor)
    @Published var storageFreeGb:           Double? = nil
    @Published var storageTotalGb:          Double? = nil
    @Published var storageUsedPct:          Double? = nil
    @Published var storageDaysRemaining:    Double? = nil
    @Published var storageBurnRateGbPerDay: Double? = nil
    @Published var storageSnapshots:        [StorageSnapshot] = []

    // MARK: – Still capture
    @Published var lastStillData:        Data? = nil
    @Published var lastStillCapturedAt:  Date? = nil
    @Published var stills:               [CapturedStill] = []
    @Published var isCapturingStill:     Bool  = false

    // MARK: – YOLO / machine state (from Pi /status)
    @Published var yoloLocked:        Bool       = false
    @Published var machineState:      String     = "IDLE"
    @Published var detections:        [Detection] = []
    @Published var detectorThreshold: Double     = 0.6
    @Published var detectorFpsActual: Double?    = nil

    // MARK: – Detection history (from /detections/recent, polled when LOG visible)
    @Published var detectionHistory: [DetectionHistoryItem] = []

    // MARK: – HDMI
    @Published var hdmiReachable:   Bool = false
    @Published var uptimeSeconds:   Int?  = nil

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

    // MARK: – System health (polled from Pi /status every 2s)
    @Published var healthPiReachable:          Bool    = false
    @Published var healthYoloRunning:          Bool    = false
    @Published var healthYoloSimMode:          Bool    = true
    @Published var healthIsRecording:          Bool    = false
    @Published var healthSsdMounted:           Bool    = false
    @Published var healthSsdFreePct:           Double  = 0
    @Published var piSdUsedPct:               Double? = nil
    @Published var healthDetectLastAgoSec:     Double? = nil
    @Published var healthLastPollAt:           Date?   = nil
    @Published var healthLastError:            String? = nil

    // MARK: – Camera (BMPCC via ethernet REST API)
    @Published var camReachable:            Bool    = false
    @Published var camRecording:            Bool    = false
    @Published var camCodec:                String  = "—"
    @Published var camFrameRate:            String  = "—"
    @Published var camResolution:           String  = "—"
    @Published var camIso:                  Int?    = nil
    @Published var camWhiteBalance:         Int?    = nil
    @Published var camGain:                 Int?    = nil
    @Published var camActiveMediaSlot:      String  = "—"
    @Published var camRemainingRecordTime:  Int?    = nil
    @Published var camShutterAngle:              Double? = nil
    @Published var camLens:                      String? = nil
    @Published var camCodecVariant:              String? = nil
    @Published var camFormatDetails:             String? = nil
    @Published var camMediaVolume:               String? = nil
    @Published var camMediaClipCount:            Int?    = nil
    @Published var camMediaSpaceRemainingGb:     Double? = nil

    // MARK: – External drives (from Pi /status)
    @Published var externalDrives: [ExternalDrive] = []

    // MARK: – Deployment
    @Published var deploymentChangeCount: Int = 0

    func resetForNewDeployment() {
        eventLog     = []
        aiLogEntries = []
        stills       = []
        deploymentChangeCount += 1
    }

    // MARK: – Private
    private var simTask:                Task<Void, Never>?
    private var trigTask:               Task<Void, Never>?
    private var healthTask:             Task<Void, Never>?
    private var logTask:                Task<Void, Never>?
    private var notificationTask:       Task<Void, Never>?
    private var finalizingTimer:        Task<Void, Never>?
    private var detectionHistoryTask:   Task<Void, Never>?
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
        startAutoStillTimer()
        if AppSettings.shared.piServerURL.isEmpty {
            aiLogEntries = AILogEntry.simulatedEntries()
        }
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
        finalizingTimer?.cancel()
        detectionHistoryTask?.cancel()
    }

    func suspend() {
        healthTask?.cancel()
        logTask?.cancel()
        notificationTask?.cancel()
    }

    func resume() {
        startHealthPolling()
        startLogPolling()
        startNotificationPolling()
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

        struct StorageInfo: Decodable {
            let freeGb:           Double?
            let totalGb:          Double?
            let usedPct:          Double?
            let daysRemaining:    Double?
            let burnRateGbPerDay: Double?
            let snapshots:        [StorageSnapshot]?
            enum CodingKeys: String, CodingKey {
                case freeGb           = "free_gb"
                case totalGb          = "total_gb"
                case usedPct          = "used_pct"
                case daysRemaining    = "days_remaining"
                case burnRateGbPerDay = "burn_rate_gb_per_day"
                case snapshots
            }
        }

        let yoloRunning:                 Bool?
        let yoloSimMode:                 Bool?
        let ssdMounted:                  Bool?
        let ssdFreePct:                  Double?
        let piSdUsedPct:                 Double?
        let detectorLastInferenceAgoSec: Double?
        let detectorThreshold:           Double?
        let detectorFpsActual:           Double?
        let recording:                   Bool?
        let machineState:                String?
        let detections:                  [DetectionItem]?
        let storage:                     StorageInfo?

        let hdmiReachable:           Bool?
        let uptimeS:                 Int?

        let temperatureC:            Double?
        let humidityPct:             Double?
        let dewPointC:               Double?
        let pressureHpa:             Double?
        let luxValue:                Double?
        let evValue:                 Double?
        let cpuTempC:                Double?
        let timecode:                String?

        let camReachable:            Bool?
        let camRecording:            Bool?
        let camCodec:                String?
        let camFrameRate:            String?
        let camResolution:           String?
        let camIso:                  Int?
        let camWhiteBalance:         Int?
        let camGain:                 Int?
        let camActiveMediaSlot:      String?
        let camRemainingRecordTime:  Int?
        let camShutterAngle:             Double?
        let camLens:                     String?
        let camCodecVariant:             String?
        let camFormatDetails:            String?
        let camMediaVolume:              String?
        let camMediaClipCount:           Int?
        let camMediaSpaceRemainingGb:    Double?
        let externalDrives:              [ExternalDrive]?

        enum CodingKeys: String, CodingKey {
            case yoloRunning                 = "yolo_running"
            case yoloSimMode                 = "yolo_sim_mode"
            case ssdMounted                  = "ssd_mounted"
            case ssdFreePct                  = "ssd_free_pct"
            case piSdUsedPct                 = "pi_sd_used_pct"
            case detectorLastInferenceAgoSec = "detector_last_inference_ago_seconds"
            case detectorThreshold           = "detector_threshold"
            case detectorFpsActual           = "detector_fps_actual"
            case recording
            case machineState                = "machine_state"
            case detections
            case storage
            case hdmiReachable               = "hdmi_reachable"
            case uptimeS                     = "uptime_s"
            case temperatureC                = "temperature_c"
            case humidityPct                 = "humidity_pct"
            case dewPointC                   = "dew_point_c"
            case pressureHpa                 = "pressure_hpa"
            case luxValue                    = "lux"
            case evValue                     = "ev"
            case cpuTempC                    = "cpu_temp_c"
            case timecode
            case camReachable                = "cam_reachable"
            case camRecording                = "cam_recording"
            case camCodec                    = "cam_codec"
            case camFrameRate                = "cam_frame_rate"
            case camResolution               = "cam_resolution"
            case camIso                      = "cam_iso"
            case camWhiteBalance             = "cam_white_balance"
            case camGain                     = "cam_gain"
            case camActiveMediaSlot          = "cam_active_media_slot"
            case camRemainingRecordTime      = "cam_remaining_record_time"
            case camShutterAngle             = "cam_shutter_angle"
            case camLens                     = "cam_lens"
            case camCodecVariant             = "cam_codec_variant"
            case camFormatDetails            = "cam_format_details"
            case camMediaVolume              = "cam_media_volume"
            case camMediaClipCount           = "cam_media_clip_count"
            case camMediaSpaceRemainingGb    = "cam_media_space_remaining_gb"
            case externalDrives              = "external_drives"
        }
    }

    func refreshHealth() async {
        await pollHealth()
    }

    // MARK: – Detector threshold

    func setDetectorThreshold(_ value: Double) async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/detector/threshold") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["value": value])
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
        // On failure the next /status poll resets detectorThreshold to server's actual value
    }

    // MARK: – Detection history polling (active only when LOG sub-page visible)

    func startDetectionHistoryPolling() {
        detectionHistoryTask?.cancel()
        detectionHistoryTask = Task {
            while !Task.isCancelled {
                await fetchDetectionHistory()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopDetectionHistoryPolling() {
        detectionHistoryTask?.cancel()
        detectionHistoryTask = nil
    }

    private func fetchDetectionHistory() async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + "/detections/recent") else { return }
        struct Response: Decodable { let detections: [DetectionHistoryItem] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response  = try JSONDecoder().decode(Response.self, from: data)
            detectionHistory = response.detections
        } catch { }
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
            healthPiReachable        = true
            healthYoloRunning        = poll.yoloRunning          ?? false
            healthYoloSimMode        = poll.yoloSimMode          ?? true
            if let t = poll.detectorThreshold { detectorThreshold = t }
            detectorFpsActual        = poll.detectorFpsActual
            healthIsRecording        = poll.recording            ?? false
            healthSsdMounted         = poll.ssdMounted           ?? false
            healthSsdFreePct         = poll.ssdFreePct           ?? 0
            piSdUsedPct              = poll.piSdUsedPct
            healthDetectLastAgoSec   = poll.detectorLastInferenceAgoSec
            healthLastPollAt         = Date()
            healthLastError          = nil

            hdmiReachable = poll.hdmiReachable ?? false
            if let u = poll.uptimeS { uptimeSeconds = u }

            // Sensor data — None from Pi serializes as null → nil here
            enclosureTempC    = poll.temperatureC
            enclosureHumidity = poll.humidityPct
            pressure          = poll.pressureHpa
            lux               = poll.luxValue
            ev                = poll.evValue
            if let c = poll.cpuTempC { cpuTemp = c }
            camTimecode       = poll.timecode

            // Camera (ethernet REST API)
            camReachable           = poll.camReachable        ?? false
            camRecording           = poll.camRecording        ?? false
            camCodec               = poll.camCodec            ?? "—"
            camFrameRate           = poll.camFrameRate        ?? "—"
            camResolution          = poll.camResolution       ?? "—"
            camIso                 = poll.camIso
            camWhiteBalance        = poll.camWhiteBalance
            camGain                = poll.camGain
            camActiveMediaSlot     = poll.camActiveMediaSlot  ?? "—"
            camRemainingRecordTime = poll.camRemainingRecordTime
            camShutterAngle              = poll.camShutterAngle
            camLens                      = poll.camLens
            camCodecVariant              = poll.camCodecVariant
            camFormatDetails             = poll.camFormatDetails
            camMediaVolume               = poll.camMediaVolume
            camMediaClipCount            = poll.camMediaClipCount
            camMediaSpaceRemainingGb     = poll.camMediaSpaceRemainingGb
            if let drives = poll.externalDrives { externalDrives = drives }

            // SSD storage_monitor
            if let s = poll.storage {
                storageFreeGb           = s.freeGb
                storageTotalGb          = s.totalGb
                storageUsedPct          = s.usedPct
                storageDaysRemaining    = s.daysRemaining
                storageBurnRateGbPerDay = s.burnRateGbPerDay
                storageSnapshots        = s.snapshots ?? []
            }

            // Tri-state recording state resolution
            switch recordingState {
            case .finalizing:
                let piStopped = !(poll.camRecording ?? false)
                let machineIdle = (poll.machineState ?? "IDLE") == "IDLE"
                if piStopped && machineIdle {
                    recordingState = .idle
                    finalizingTimer?.cancel()
                    finalizingTimer = nil
                }
            case .idle:
                if poll.camRecording ?? false { recordingState = .recording }
            case .recording:
                break
            }
            isRecording = (recordingState == .recording)

            // Machine state & YOLO lock
            let ms = poll.machineState ?? "IDLE"
            machineState = ms
            yoloLocked   = (ms == "ACTIVE") && camRecording

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
        if isRecording { recordingSeconds += 2 }
        ssdRemainingGB -= isRecording ? 0.0014 : 0

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
        case .active:    return Theme.ok
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
        !healthPiReachable || !camReachable
    }

    // MARK: – Pi commands

    // BMPCC record via Pi → ethernet → camera REST API
    func toggleBmpccRecord() async {
        switch recordingState {
        case .recording:
            await sendPiCommandPUT("/camera/record/stop")
            recordingState = .finalizing
            finalizingTimer?.cancel()
            finalizingTimer = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if recordingState == .finalizing {
                    recordingState = .idle
                    print("[HHRCS] FINALIZING safety timer expired — forced idle")
                }
            }
        case .idle:
            await sendPiCommandPUT("/camera/record/start")
            recordingState = .recording
            await captureAndStoreSnapshot(triggerType: "manual")
        case .finalizing:
            break  // non-interactive during finalization
        }
        await pollHealth()
    }

    // Pi Camera Module 3 record — visual-only toggle, no Pi endpoint yet
    func togglePiCamRecord() {
        isPiCamRecording.toggle()
    }

    func captureHdmiStill() async {
        guard !isCapturingStill else { return }
        isCapturingStill = true
        defer { isCapturingStill = false }
        let piBase = AppSettings.shared.piServerURL
        guard !piBase.isEmpty, let triggerURL = URL(string: piBase + "/hdmi/still") else { return }
        var req = URLRequest(url: triggerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let url = URL(string: piBase + "/hdmi/stills/latest"),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           let http = resp as? HTTPURLResponse,
           http.statusCode == 200,
           !data.isEmpty {
            lastStillData       = data
            lastStillCapturedAt = Date()
            stills.insert(CapturedStill(piCamImageData: data, triggerType: "hdmi"), at: 0)
        }
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
            for path in ["/stills/latest"] {
                guard let url = URL(string: piBase + path) else { continue }
                if let (data, resp) = try? await URLSession.shared.data(from: url),
                   let http = resp as? HTTPURLResponse,
                   http.statusCode == 200,
                   !data.isEmpty {
                    lastStillData       = data
                    lastStillCapturedAt = Date()
                    stills.insert(CapturedStill(piCamImageData: data, triggerType: "manual"), at: 0)
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
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty else {
            stills.insert(CapturedStill(triggerType: triggerType), at: 0)
            lastStillCapturedAt = Date()
            return
        }
        if let url = URL(string: base + "/still/trigger") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            _ = try? await URLSession.shared.data(for: req)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let url = URL(string: base + "/stills/latest"),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           !data.isEmpty {
            lastStillData       = data
            lastStillCapturedAt = Date()
            stills.insert(CapturedStill(piCamImageData: data, triggerType: triggerType), at: 0)
        } else {
            stills.insert(CapturedStill(triggerType: triggerType), at: 0)
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

    private func sendPiCommandPUT(_ path: String) async {
        let base = AppSettings.shared.piServerURL
        guard !base.isEmpty, let url = URL(string: base + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
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
