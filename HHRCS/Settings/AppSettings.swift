import Foundation
import Combine
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var deploymentName: String {
        didSet { UserDefaults.standard.set(deploymentName, forKey: Keys.deploymentName) }
    }
    @Published var latitude: Double {
        didSet { UserDefaults.standard.set(latitude, forKey: Keys.latitude) }
    }
    @Published var longitude: Double {
        didSet { UserDefaults.standard.set(longitude, forKey: Keys.longitude) }
    }
    @Published var deploymentAddress: String {
        didSet { UserDefaults.standard.set(deploymentAddress, forKey: Keys.deploymentAddress) }
    }
    @Published var piServerURL: String {
        didSet { UserDefaults.standard.set(piServerURL, forKey: Keys.piServerURL) }
    }
    @Published var savedServerURLs: [String] {
        didSet { UserDefaults.standard.set(savedServerURLs, forKey: Keys.savedServerURLs) }
    }

    // MARK: – System toggles
    @Published var simulationMode: Bool {
        didSet { UserDefaults.standard.set(simulationMode, forKey: Keys.simulationMode) }
    }
    @Published var dawnDuskWindows: Bool {
        didSet { UserDefaults.standard.set(dawnDuskWindows, forKey: Keys.dawnDuskWindows) }
    }
    @Published var detectionTrigger: Bool {
        didSet { UserDefaults.standard.set(detectionTrigger, forKey: Keys.detectionTrigger) }
    }
    @Published var telegramNotifications: Bool {
        didSet { UserDefaults.standard.set(telegramNotifications, forKey: Keys.telegramNotifications) }
    }
    @Published var thirtyMinStills: Bool {
        didSet { UserDefaults.standard.set(thirtyMinStills, forKey: Keys.thirtyMinStills) }
    }

    @Published var positionName: String {
        didSet { UserDefaults.standard.set(positionName, forKey: Keys.positionName) }
    }
    @Published var pushNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(pushNotificationsEnabled, forKey: Keys.pushNotificationsEnabled) }
    }

    // MARK: – Control PIN
    @Published var controlPIN: String {
        didSet { UserDefaults.standard.set(controlPIN, forKey: Keys.controlPIN) }
    }

    // MARK: – Derived URLs (not persisted)

    /// Base URL for the camera stream server — same host/port as piServerURL.
    var streamBaseURL: String {
        guard !piServerURL.isEmpty,
              var components = URLComponents(string: piServerURL),
              components.host != nil else { return "" }
        components.path = ""
        return components.string ?? ""
    }

    // MARK: – Agent
    @Published var piAgentLogEnabled: Bool {
        didSet { UserDefaults.standard.set(piAgentLogEnabled, forKey: Keys.piAgentLogEnabled) }
    }
    @Published var anthropicAPIKey: String {
        didSet { UserDefaults.standard.set(anthropicAPIKey, forKey: Keys.anthropicAPIKey) }
    }

    // MARK: – Notification category toggles
    @Published var notifyRecordings: Bool {
        didSet { UserDefaults.standard.set(notifyRecordings, forKey: Keys.notifyRecordings) }
    }
    @Published var notifyStills: Bool {
        didSet { UserDefaults.standard.set(notifyStills, forKey: Keys.notifyStills) }
    }
    @Published var notifyDetections: Bool {
        didSet { UserDefaults.standard.set(notifyDetections, forKey: Keys.notifyDetections) }
    }
    @Published var notifyDeployments: Bool {
        didSet { UserDefaults.standard.set(notifyDeployments, forKey: Keys.notifyDeployments) }
    }
    @Published var notifySystemAlerts: Bool {
        didSet { UserDefaults.standard.set(notifySystemAlerts, forKey: Keys.notifySystemAlerts) }
    }
    @Published var notifyAgentActivity: Bool {
        didSet { UserDefaults.standard.set(notifyAgentActivity, forKey: Keys.notifyAgentActivity) }
    }

    // MARK: – WARM UI
    @AppStorage("ui.warmAccent") var warmUI: Bool = true

    var activeColor: Color { warmUI ? Theme.warmAccent : Theme.text1 }

    // MARK: – Owner Mode
    @Published var ownerModeEnabled: Bool {
        didSet { UserDefaults.standard.set(ownerModeEnabled, forKey: Keys.ownerModeEnabled) }
    }
    @Published var ownerPassword: String {
        didSet { UserDefaults.standard.set(ownerPassword, forKey: Keys.ownerPassword) }
    }

    @discardableResult
    func unlockOwnerMode(password: String) -> Bool {
        guard password == ownerPassword else { return false }
        ownerModeEnabled = true
        return true
    }

    func lockOwnerMode() {
        ownerModeEnabled = false
    }

    private enum Keys {
        static let deploymentName           = "hhrcs.deploymentName"
        static let positionName             = "hhrcs.positionName"
        static let latitude                 = "hhrcs.latitude"
        static let longitude                = "hhrcs.longitude"
        static let deploymentAddress        = "hhrcs.deploymentAddress"
        static let piServerURL              = "hhrcs.piServerURL"
        static let savedServerURLs          = "hhrcs.savedServerURLs"
        static let simulationMode           = "hhrcs.simulationMode"
        static let dawnDuskWindows          = "hhrcs.dawnDuskWindows"
        static let detectionTrigger         = "hhrcs.detectionTrigger"
        static let telegramNotifications    = "hhrcs.telegramNotifications"
        static let pushNotificationsEnabled = "hhrcs.pushNotificationsEnabled"
        static let thirtyMinStills          = "hhrcs.thirtyMinStills"
        static let controlPIN               = "hhrcs.controlPIN"
        static let piAgentLogEnabled        = "hhrcs.piAgentLogEnabled"
        static let anthropicAPIKey          = "hhrcs.anthropicAPIKey"
        static let ownerModeEnabled         = "hhrcs.ownerModeEnabled"
        static let ownerPassword            = "hhrcs.ownerPassword"
        static let notifyRecordings         = "hhrcs.notifyRecordings"
        static let notifyStills             = "hhrcs.notifyStills"
        static let notifyDetections         = "hhrcs.notifyDetections"
        static let notifyDeployments        = "hhrcs.notifyDeployments"
        static let notifySystemAlerts       = "hhrcs.notifySystemAlerts"
        static let notifyAgentActivity      = "hhrcs.notifyAgentActivity"
    }

    // TODO: INSERT ANTHROPIC_API_KEY HERE
    private static let anthropicAPIKeyDefault = ""

    private init() {
        let ud = UserDefaults.standard
        deploymentName           = ud.string(forKey: Keys.deploymentName) ?? "HUNTER HOUSE"
        positionName             = ud.string(forKey: Keys.positionName) ?? "POSITION 1"
        latitude                 = ud.object(forKey: Keys.latitude)  as? Double ?? 48.515
        longitude                = ud.object(forKey: Keys.longitude) as? Double ?? -123.408
        deploymentAddress        = ud.string(forKey: Keys.deploymentAddress) ?? ""
        let storedURLs           = ud.stringArray(forKey: Keys.savedServerURLs) ?? []
        let defaultURLs          = storedURLs.isEmpty
            ? ["http://raspberrypi.local:5001", "http://100.118.27.125:5001"]
            : storedURLs
        savedServerURLs          = defaultURLs
        piServerURL              = ud.string(forKey: Keys.piServerURL) ?? defaultURLs[0]
        simulationMode           = ud.object(forKey: Keys.simulationMode) as? Bool ?? true
        dawnDuskWindows          = ud.object(forKey: Keys.dawnDuskWindows) as? Bool ?? false
        detectionTrigger         = ud.object(forKey: Keys.detectionTrigger) as? Bool ?? true
        telegramNotifications    = ud.object(forKey: Keys.telegramNotifications) as? Bool ?? false
        pushNotificationsEnabled = ud.object(forKey: Keys.pushNotificationsEnabled) as? Bool ?? false
        thirtyMinStills          = ud.object(forKey: Keys.thirtyMinStills) as? Bool ?? false
        controlPIN               = ud.string(forKey: Keys.controlPIN) ?? "0000"
        piAgentLogEnabled        = ud.object(forKey: Keys.piAgentLogEnabled) as? Bool ?? true
        anthropicAPIKey          = ud.string(forKey: Keys.anthropicAPIKey) ?? Self.anthropicAPIKeyDefault
        ownerModeEnabled         = ud.object(forKey: Keys.ownerModeEnabled) as? Bool ?? false
        ownerPassword            = ud.string(forKey: Keys.ownerPassword) ?? "0000"
        notifyRecordings         = ud.object(forKey: Keys.notifyRecordings)      as? Bool ?? true
        notifyStills             = ud.object(forKey: Keys.notifyStills)          as? Bool ?? true
        notifyDetections         = ud.object(forKey: Keys.notifyDetections)      as? Bool ?? true
        notifyDeployments        = ud.object(forKey: Keys.notifyDeployments)     as? Bool ?? true
        notifySystemAlerts       = ud.object(forKey: Keys.notifySystemAlerts)    as? Bool ?? true
        notifyAgentActivity      = ud.object(forKey: Keys.notifyAgentActivity)   as? Bool ?? false
    }
}
