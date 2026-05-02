import Foundation

struct AILogEntry: Identifiable, Codable {
    let id:        UUID
    let timestamp: Date
    let type:      String           // "query" | "summary"
    let source:    String           // "pi_agent" for autonomous entries
    let content:   String           // agent response text
    let query:     String?          // user's question (type == "query" only)
    let data:      [String: String]?

    static func simulatedEntries() -> [AILogEntry] {
        let now = Date()
        let h   = 3600.0
        let d   = 86400.0

        return [
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-1.2 * h),
                type: "query",
                source: "pi_agent",
                content: "Deer entered north meadow via east treeline. Movement consistent with feeding — slow traverse, frequent pauses. Estimated 2 individuals. Trigger duration 312s.",
                query: "anything happen in the last hour?",
                data: ["class": "deer", "confidence": "0.94", "duration_s": "312", "individuals": "2"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-3.8 * h),
                type: "summary",
                source: "pi_agent",
                content: "No detections in last hour. BLE stable. In recording window.",
                query: nil,
                data: nil
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-5.1 * h),
                type: "summary",
                source: "pi_agent",
                content: "3 detections in last hour. BLE stable.",
                query: nil,
                data: nil
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-8.4 * h),
                type: "query",
                source: "pi_agent",
                content: "Dew point anomaly: enclosure dew point rose to within 2.1°C of enclosure temperature for 18 minutes (09:12–09:30). Condensation risk elevated. Conditions self-resolved as ambient temperature increased. No hardware fault detected.",
                query: "how is the enclosure holding up?",
                data: ["dew_margin_c": "2.1", "duration_min": "18", "resolved": "true"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 0.9 * h),
                type: "summary",
                source: "pi_agent",
                content: "1 detection in last hour. BLE stable.",
                query: nil,
                data: nil
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 7.2 * h),
                type: "summary",
                source: "pi_agent",
                content: "No detections in last hour. BLE dropped 1x in last hour.",
                query: nil,
                data: nil
            ),
        ]
    }
}
