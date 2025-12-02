import Foundation
import AppKit

/// Error types for SRT generation
enum SRTError: LocalizedError {
    case noSegments
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "No subtitle segments to export"
        case .writeFailed(let message):
            return "Failed to write SRT: \(message)"
        }
    }
}

/// Service for generating SRT subtitle files
class SRTGenerator {

    /// Generate SRT from subtitle segments
    /// - Parameters:
    ///   - segments: Array of subtitle segments
    ///   - mediaFileName: Original media file name for reference
    /// - Returns: URL to the generated SRT file
    func generate(segments: [SubtitleSegment], mediaFileName: String) throws -> URL {
        guard !segments.isEmpty else {
            throw SRTError.noSegments
        }

        // Build SRT content
        let srt = buildSRT(segments: segments)

        // Write to temp file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoFCPXCaptions_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("srt")

        do {
            try srt.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw SRTError.writeFailed(error.localizedDescription)
        }

        return outputURL
    }

    /// Build the SRT string
    private func buildSRT(segments: [SubtitleSegment]) -> String {
        var srt = ""

        for (index, segment) in segments.enumerated() {
            // Sequence number (1-based)
            srt += "\(index + 1)\n"

            // Timecode: HH:MM:SS,mmm --> HH:MM:SS,mmm
            let startTimecode = formatSRTTime(segment.startTime)
            let endTimecode = formatSRTTime(segment.endTime)
            srt += "\(startTimecode) --> \(endTimecode)\n"

            // Text content
            srt += "\(segment.text)\n"

            // Blank line between entries
            srt += "\n"
        }

        return srt
    }

    /// Format time as SRT timecode: HH:MM:SS,mmm
    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, ms)
    }

    /// Save SRT to user-selected location
    @MainActor
    static func saveWithDialog(from tempURL: URL, suggestedName: String) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "srt")!]
        savePanel.nameFieldStringValue = suggestedName + ".srt"
        savePanel.title = "Save SRT"
        savePanel.message = "Choose where to save the SRT subtitle file"

        guard let window = NSApp.keyWindow else {
            // Fallback: run modal if no key window
            let response = savePanel.runModal()
            guard response == .OK, let destinationURL = savePanel.url else {
                return nil
            }
            return trySaveFile(from: tempURL, to: destinationURL)
        }

        let response = await savePanel.beginSheetModal(for: window)

        guard response == .OK, let destinationURL = savePanel.url else {
            return nil
        }

        return trySaveFile(from: tempURL, to: destinationURL)
    }

    private static func trySaveFile(from tempURL: URL, to destinationURL: URL) -> URL? {
        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to save SRT: \(error)")
            return nil
        }
    }
}
