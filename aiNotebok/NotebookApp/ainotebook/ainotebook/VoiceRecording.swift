import Foundation

struct VoiceRecording: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let pageID: UUID?
    var title: String
    var transcript: String?
    var notesSummary: String?

    private enum CodingKeys: String, CodingKey {
        case id, fileName, createdAt, duration, pageID, title, transcript, notesSummary
    }

    init(id: UUID = UUID(),
         fileName: String,
         createdAt: Date,
         duration: TimeInterval,
         pageID: UUID?,
         title: String,
         transcript: String? = nil,
         notesSummary: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.pageID = pageID
        self.title = title
        self.transcript = transcript
        self.notesSummary = notesSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        pageID = try container.decodeIfPresent(UUID.self, forKey: .pageID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? VoiceRecording.defaultTitleFallback(date: createdAt)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        notesSummary = try container.decodeIfPresent(String.self, forKey: .notesSummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(pageID, forKey: .pageID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(transcript, forKey: .transcript)
        try container.encodeIfPresent(notesSummary, forKey: .notesSummary)
    }

    private static func defaultTitleFallback(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
}
