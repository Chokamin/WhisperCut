import Foundation

/// Represents a single subtitle segment with timing information
struct SubtitleSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var startTime: TimeInterval // Seconds
    var endTime: TimeInterval   // Seconds

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime - startTime
    }
}
