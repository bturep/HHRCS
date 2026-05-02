import Foundation

struct EventLogLine: Identifiable {
    let id    = UUID()
    let raw:   String
    let label: String
    let time:  String
    let body:  String

    // Pi format: "HH:MM:SS  LABEL___  message"
    //             0      7  8       9 10     17  18 19 20+
    // fields are fixed-width: 8-char time, 2 spaces, 8-char label (left-aligned), 2 spaces, message
    static func parse(_ raw: String) -> EventLogLine? {
        guard raw.count > 20 else { return nil }
        let s = raw.startIndex
        let idx8  = raw.index(s, offsetBy: 8)
        let idx10 = raw.index(s, offsetBy: 10)
        let idx18 = raw.index(s, offsetBy: 18)
        let idx20 = raw.index(s, offsetBy: 20)
        let time  = String(raw[s..<idx8])
        let label = String(raw[idx10..<idx18]).trimmingCharacters(in: .whitespaces)
        let body  = String(raw[idx20...])
        guard !time.isEmpty, !label.isEmpty else { return nil }
        return EventLogLine(raw: raw, label: label, time: time, body: body)
    }
}

enum EventLogFilter: String, CaseIterable {
    case all     = "ALL"
    case trigger = "TRIGGER"
    case state   = "STATE"
    case rec     = "REC"
    case ble     = "BLE"
}
