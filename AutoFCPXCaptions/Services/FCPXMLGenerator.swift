import Foundation
import AppKit
import UniformTypeIdentifiers

/// Error types for FCPXML generation
enum FCPXMLError: LocalizedError {
    case noSegments
    case writeFailed(String)
    case invalidTimecode

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "No subtitle segments to export"
        case .writeFailed(let message):
            return "Failed to write FCPXML: \(message)"
        case .invalidTimecode:
            return "Invalid timecode calculation"
        }
    }
}

/// Service for generating FCPXML files for Final Cut Pro
class FCPXMLGenerator {
    // FCPXML version and DTD
    private let fcpxmlVersion = "1.10"
    private let dtdVersion = "1.10"

    private let frameRate: FrameRate
    private let minGapFrames: Int = 2  // Minimum frames gap between segments

    init(frameRate: FrameRate) {
        self.frameRate = frameRate
    }

    /// Generate FCPXML from subtitle segments
    /// - Parameters:
    ///   - segments: Array of subtitle segments
    ///   - mediaFileName: Original media file name for reference
    /// - Returns: URL to the generated FCPXML file
    func generate(segments: [SubtitleSegment], mediaFileName: String) throws -> URL {
        guard !segments.isEmpty else {
            throw FCPXMLError.noSegments
        }

        // Process segments to ensure proper gaps
        let processedSegments = ensureMinimumGaps(segments)

        // Build XML document
        let xml = buildFCPXML(segments: processedSegments, mediaFileName: mediaFileName)

        // Write to temp file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoFCPXCaptions_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("fcpxml")

        do {
            try xml.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw FCPXMLError.writeFailed(error.localizedDescription)
        }

        return outputURL
    }

    /// Ensure minimum gap between segments to avoid FCPX import conflicts
    private func ensureMinimumGaps(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        var result: [SubtitleSegment] = []
        let minGap = Double(minGapFrames) * frameRate.frameDurationSeconds

        for segment in segments {
            var adjustedSegment = segment

            // Check if this segment overlaps with the previous one
            if let lastSegment = result.last {
                if adjustedSegment.startTime < lastSegment.endTime + minGap {
                    adjustedSegment.startTime = lastSegment.endTime + minGap
                }
            }

            // Ensure segment has positive duration
            if adjustedSegment.endTime <= adjustedSegment.startTime {
                adjustedSegment.endTime = adjustedSegment.startTime + frameRate.frameDurationSeconds
            }

            result.append(adjustedSegment)
        }

        return result
    }

    /// Align time value to frame boundary
    private func alignToFrame(_ time: Double) -> Int {
        let frameDuration = frameRate.frameDurationSeconds
        let frameNumber = round(time / frameDuration)
        return Int(frameNumber * frameDuration * Double(frameRate.timescale))
    }

    /// Build the FCPXML string
    private func buildFCPXML(segments: [SubtitleSegment], mediaFileName: String) -> String {
        let timescale = frameRate.timescale
        let projectName = "AutoFCPXCaptions_\(mediaFileName)"

        // Calculate total duration (aligned to frame)
        let totalDuration = segments.last?.endTime ?? 0
        let totalDurationValue = alignToFrame(totalDuration)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="\(fcpxmlVersion)">
            <resources>
                <format id="r1" name="FFVideoFormat1080p\(frameRateFormatString)" frameDuration="\(frameRate.frameDuration)" width="1920" height="1080"/>
                <effect id="r2" name="Basic Title" uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"/>
            </resources>
            <library>
                <event name="\(projectName)">
                    <project name="\(projectName)">
                        <sequence format="r1" duration="\(totalDurationValue)/\(timescale)s" tcStart="0/\(timescale)s" tcFormat="NDF">
                            <spine>
                                <gap name="Gap" offset="0/\(timescale)s" duration="\(totalDurationValue)/\(timescale)s" start="0/\(timescale)s">

        """

        // Add title clips as connected clips (above the gap)
        for (index, segment) in segments.enumerated() {
            // Align start and end times to frame boundaries
            let startValue = alignToFrame(segment.startTime)
            let endValue = alignToFrame(segment.endTime)
            let durationValue = max(endValue - startValue, alignToFrame(frameRate.frameDurationSeconds))

            // Escape XML special characters in text
            let escapedText = escapeXML(segment.text)

            // Use unique ID for each text-style-def
            let styleId = "ts\(index + 1)"

            xml += """
                                    <title ref="r2" name="\(escapedText)" lane="1" offset="\(startValue)/\(timescale)s" duration="\(durationValue)/\(timescale)s" start="0/\(timescale)s">
                                        <text>
                                            <text-style ref="\(styleId)">\(escapedText)</text-style>
                                        </text>
                                        <text-style-def id="\(styleId)">
                                            <text-style font="Helvetica" fontSize="60" fontColor="1 1 1 1" alignment="center"/>
                                        </text-style-def>
                                    </title>

            """
        }

        xml += """
                                </gap>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """

        return xml
    }

    /// Get frame rate format string for FCPXML
    private var frameRateFormatString: String {
        switch frameRate {
        case .fps23_98: return "2398"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps29_97: return "2997"
        case .fps30: return "30"
        case .fps50: return "50"
        case .fps59_94: return "5994"
        case .fps60: return "60"
        }
    }

    /// Escape special XML characters
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Open the generated FCPXML in Final Cut Pro
    @MainActor
    static func openInFinalCutPro(url: URL) async -> Bool {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()

        // Try to open with Final Cut Pro
        let fcpBundleID = "com.apple.FinalCut"

        do {
            if let fcpURL = workspace.urlForApplication(withBundleIdentifier: fcpBundleID) {
                try await workspace.open([url], withApplicationAt: fcpURL, configuration: configuration)
            } else {
                // Fall back to default application
                try await workspace.open(url, configuration: configuration)
            }
            return true
        } catch {
            print("Failed to open FCPXML: \(error)")
            // Try simple open as fallback
            return workspace.open(url)
        }
    }

    /// Save FCPXML to user-selected location
    @MainActor
    static func saveWithDialog(from tempURL: URL, suggestedName: String) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.xml]
        savePanel.nameFieldStringValue = suggestedName + ".fcpxml"
        savePanel.title = "Save FCPXML"
        savePanel.message = "Choose where to save the FCPXML file"

        let response = await savePanel.beginSheetModal(for: NSApp.keyWindow!)

        guard response == .OK, let destinationURL = savePanel.url else {
            return nil
        }

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to save FCPXML: \(error)")
            return nil
        }
    }
}
