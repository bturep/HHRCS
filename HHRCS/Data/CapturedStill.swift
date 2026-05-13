import Foundation

struct CapturedStill: Identifiable {
    let id:              UUID
    let timestamp:       Date
    var piCamImageData:  Data?
    var bmpccFilename:   String?
    let triggerType:     String   // "manual" / "scheduled" / "detection"
    var sessionId:       String?

    init(id: UUID = UUID(), timestamp: Date = Date(),
         piCamImageData: Data? = nil, bmpccFilename: String? = nil,
         triggerType: String = "manual", sessionId: String? = nil) {
        self.id             = id
        self.timestamp      = timestamp
        self.piCamImageData = piCamImageData
        self.bmpccFilename  = bmpccFilename
        self.triggerType    = triggerType
        self.sessionId      = sessionId
    }

    var sourceLabel: String { triggerType == "hdmi" ? "BMPCC" : "CAM" }

    static func simulatedEntries() -> [CapturedStill] {
        let now     = Date()
        let offsets: [TimeInterval] = [-300, -1800, -7200, -18000, -86400, -90000]
        let types   = ["manual", "detection", "manual", "scheduled", "detection", "manual"]
        return zip(offsets, types).map { offset, type in
            CapturedStill(timestamp: now.addingTimeInterval(offset), triggerType: type)
        }
    }
}
