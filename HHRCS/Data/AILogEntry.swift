import Foundation

struct AILogEntry: Identifiable, Codable {
    let id:        UUID
    let timestamp: Date
    let type:      String           // observation / anomaly / window_summary / alert / inference
    let source:    String           // "pi_agent" for autonomous entries
    let content:   String
    let data:      [String: String]?

    static func simulatedEntries() -> [AILogEntry] {
        let now = Date()
        let h   = 3600.0
        let d   = 86400.0

        return [
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-1.2 * h),
                type: "observation",
                source: "pi_agent",
                content: "Deer entered north meadow via east treeline. Movement consistent with feeding — slow traverse, frequent pauses. Estimated 2 individuals. Trigger duration 312s.",
                data: ["class": "deer", "confidence": "0.94", "duration_s": "312", "individuals": "2"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-3.8 * h),
                type: "inference",
                source: "pi_agent",
                content: "Rabbit activity window inferred: 06:15–07:40 local time, based on 4-day trigger pattern. Peak activity correlates with civil dawn ±30 min. Consistent with crepuscular feeding behaviour.",
                data: ["pattern_days": "4", "confidence": "0.87", "peak_start": "06:15", "peak_end": "07:40"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-5.1 * h),
                type: "window_summary",
                source: "pi_agent",
                content: "Dawn window summary: 3 triggers between 05:42–07:18. Species — deer ×2, rabbit ×1. Lux at civil dawn 180 lx, peak 1420 lx. ND4 active throughout.",
                data: ["triggers": "3", "lux_dawn": "180", "lux_peak": "1420", "nd": "4"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-8.4 * h),
                type: "anomaly",
                source: "pi_agent",
                content: "Dew point anomaly: enclosure dew point rose to within 2.1°C of enclosure temperature for 18 minutes (09:12–09:30). Condensation risk elevated. Conditions self-resolved as ambient temperature increased. No hardware fault detected.",
                data: ["dew_margin_c": "2.1", "duration_min": "18", "resolved": "true"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 0.9 * h),
                type: "observation",
                source: "pi_agent",
                content: "Single deer at 22:14, entering from north. Unusual nocturnal visit — no prior nocturnal deer triggers this week. Lux 0.3 lx. ISO 3200, ND clear.",
                data: ["class": "deer", "lux": "0.3", "iso": "3200", "nd": "0"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 4.7 * h),
                type: "observation",
                source: "pi_agent",
                content: "Corvid cluster: 3 triggers in 22 minutes (14:38–15:00), all bird. Behaviour consistent with foraging. No mammals detected during this window.",
                data: ["class": "bird", "subclass": "corvid", "trigger_count": "3", "window_min": "22"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 7.2 * h),
                type: "window_summary",
                source: "pi_agent",
                content: "Dusk window summary: 1 trigger at 20:34 (rabbit), 144s, 2 files. Lux at trigger 390 lx and declining. No further triggers post-civil dusk.",
                data: ["triggers": "1", "lux_at_trigger": "390", "files": "2", "species": "rabbit"]
            ),
            AILogEntry(
                id: UUID(),
                timestamp: now.addingTimeInterval(-d - 11.5 * h),
                type: "inference",
                source: "pi_agent",
                content: "Multi-day rabbit feeding pattern confirmed over 5 observed days: activity concentrated between civil dawn and +90 min, and again 45–15 min before civil dusk. Daytime activity near zero. Pattern is stable.",
                data: ["pattern_days": "5", "morning_window": "dawn+90min", "evening_window": "dusk-45 to dusk-15"]
            ),
        ]
    }
}
