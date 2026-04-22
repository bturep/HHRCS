import Foundation

struct Note: Identifiable, Codable {
    let id:          UUID
    let authorName:  String
    let timestamp:   Date
    let text:        String

    var lux:               Double?
    var isRecording:       Bool?
    var triggerLabel:      String?
    var enclosureTempC:    Double?
    var recordingDuration: String?
    var hasThumbnail:      Bool

    init(authorName: String, text: String,
         lux: Double? = nil, isRecording: Bool? = nil,
         triggerLabel: String? = nil, enclosureTempC: Double? = nil,
         recordingDuration: String? = nil, hasThumbnail: Bool = false) {
        id                    = UUID()
        self.authorName       = authorName
        self.timestamp        = Date()
        self.text             = text
        self.lux              = lux
        self.isRecording      = isRecording
        self.triggerLabel     = triggerLabel
        self.enclosureTempC   = enclosureTempC
        self.recordingDuration = recordingDuration
        self.hasThumbnail     = hasThumbnail
    }

    // Custom decode so old notes without hasThumbnail decode as false
    enum CodingKeys: String, CodingKey {
        case id, authorName, timestamp, text
        case lux, isRecording, triggerLabel, enclosureTempC
        case recordingDuration, hasThumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        authorName        = try c.decode(String.self, forKey: .authorName)
        timestamp         = try c.decode(Date.self,   forKey: .timestamp)
        text              = try c.decode(String.self, forKey: .text)
        lux               = try c.decodeIfPresent(Double.self, forKey: .lux)
        isRecording       = try c.decodeIfPresent(Bool.self,   forKey: .isRecording)
        triggerLabel      = try c.decodeIfPresent(String.self, forKey: .triggerLabel)
        enclosureTempC    = try c.decodeIfPresent(Double.self, forKey: .enclosureTempC)
        recordingDuration = try c.decodeIfPresent(String.self, forKey: .recordingDuration)
        hasThumbnail      = try c.decodeIfPresent(Bool.self,   forKey: .hasThumbnail) ?? false
    }
}
