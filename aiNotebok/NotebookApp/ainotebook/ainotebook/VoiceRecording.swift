import Foundation

struct VoiceRecording: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
}
