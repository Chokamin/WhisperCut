import Foundation
import WhisperKit

/// Error types for Whisper transcription
enum WhisperError: LocalizedError {
    case modelNotFound
    case transcriptionFailed(String)
    case invalidAudioFormat
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Whisper model not found"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .initializationFailed(let message):
            return "Failed to initialize Whisper: \(message)"
        }
    }
}

/// Service for transcribing audio using WhisperKit
@MainActor
class WhisperService: ObservableObject {
    @Published var isInitialized: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var statusMessage: String = ""

    private var whisperKit: WhisperKit?

    /// Get available models that can be downloaded
    static func availableModels() async -> [String] {
        do {
            return try await WhisperKit.recommendedModels().supported
        } catch {
            return ["base", "small", "medium", "large-v3"]
        }
    }

    /// Initialize WhisperKit with a specific model (will download if needed)
    func initialize(modelName: String = "base") async throws {
        isInitialized = false
        isDownloading = true
        statusMessage = "Downloading model: \(modelName)..."
        downloadProgress = 0

        do {
            // Set HuggingFace mirror for China users
            // This helps users in China download models faster
            setenv("HF_ENDPOINT", "https://hf-mirror.com", 1)

            // WhisperKit will automatically download the model if not present
            whisperKit = try await WhisperKit(
                model: modelName,
                verbose: true,
                prewarm: true,
                load: true,
                download: true
            )

            isInitialized = true
            isDownloading = false
            statusMessage = "Model ready"
            downloadProgress = 1.0
        } catch {
            isDownloading = false
            statusMessage = "Failed: \(error.localizedDescription)"
            throw WhisperError.initializationFailed(error.localizedDescription)
        }
    }

    /// Transcribe audio file to subtitle segments with real-time progress
    func transcribe(
        audioURL: URL,
        language: RecognitionLanguage,
        mediaDuration: TimeInterval,
        progressHandler: @escaping (Double) -> Void,
        segmentHandler: @escaping (SubtitleSegment) -> Void
    ) async throws -> [SubtitleSegment] {
        guard let whisperKit = whisperKit, isInitialized else {
            throw WhisperError.modelNotFound
        }

        // Configure decoding options
        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperCode,
            wordTimestamps: true
        )

        // Transcribe the audio
        print("Starting transcription for: \(audioURL.path)")
        print("Media duration: \(mediaDuration) seconds")

        // Load audio as Float array to use the method that supports segmentCallback
        let audioSamples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        print("Loaded \(audioSamples.count) audio samples")

        // Track which segments we've already sent to avoid duplicates
        var sentSegmentKeys = Set<String>()

        // Track the latest segment end time for progress calculation
        var latestEndTime: TimeInterval = 0

        // Use transcribe with both callbacks for real-time progress and segment discovery
        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options,
            callback: { progress in
                // The callback is called but progress.timings may not update as expected
                // We'll rely on segmentCallback for progress updates instead
                return nil
            },
            segmentCallback: { discoveredSegments in
                // Process newly discovered segments in real-time
                for segment in discoveredSegments {
                    var text = segment.text
                    text = self.cleanWhisperTokens(text)
                    // Convert between Simplified and Traditional Chinese based on selected language
                    if language == .chineseSimplified {
                        // Convert Traditional to Simplified
                        if let converted = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) {
                            text = converted
                        }
                    } else if language == .chineseTraditional {
                        // Convert Simplified to Traditional
                        if let converted = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) {
                            text = converted
                        }
                    }
                    text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                    guard !text.isEmpty else { continue }

                    // Update latest end time for progress calculation
                    let segmentEndTime = TimeInterval(segment.end)
                    if segmentEndTime > latestEndTime {
                        latestEndTime = segmentEndTime
                        // Calculate and report progress based on segment end time
                        if mediaDuration > 0 {
                            let progressPercent = min(latestEndTime / mediaDuration, 0.99)
                            Task { @MainActor in
                                progressHandler(progressPercent)
                            }
                        }
                    }

                    let subtitleSegment = SubtitleSegment(
                        text: text,
                        startTime: TimeInterval(segment.start),
                        endTime: segmentEndTime
                    )

                    // Split and send segments
                    let splitSegments = self.splitSegmentAtPunctuation(subtitleSegment)
                    for splitSeg in splitSegments {
                        let key = "\(splitSeg.startTime)-\(splitSeg.text)"
                        if !sentSegmentKeys.contains(key) {
                            sentSegmentKeys.insert(key)
                            Task { @MainActor in
                                segmentHandler(splitSeg)
                            }
                        }
                    }
                }
            }
        )

        print("Transcription completed. Results count: \(results.count)")

        // Process final results to build complete segment list
        var finalSegments: [SubtitleSegment] = []
        for (resultIndex, result) in results.enumerated() {
            print("Result \(resultIndex): \(result.segments.count) segments, text: \(result.text.prefix(100))")

            for segment in result.segments {
                var text = segment.text
                text = cleanWhisperTokens(text)
                // Convert between Simplified and Traditional Chinese based on selected language
                if language == .chineseSimplified {
                    // Convert Traditional to Simplified
                    if let converted = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) {
                        text = converted
                    }
                } else if language == .chineseTraditional {
                    // Convert Simplified to Traditional
                    if let converted = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) {
                        text = converted
                    }
                }
                text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                guard !text.isEmpty else { continue }

                let subtitleSegment = SubtitleSegment(
                    text: text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                )

                let splitSegments = splitSegmentAtPunctuation(subtitleSegment)

                for splitSeg in splitSegments {
                    let key = "\(splitSeg.startTime)-\(splitSeg.text)"
                    print("Segment: [\(splitSeg.startTime) - \(splitSeg.endTime)] \(splitSeg.text.prefix(50))")
                    finalSegments.append(splitSeg)
                    // Only call handler for segments not already sent during streaming
                    if !sentSegmentKeys.contains(key) {
                        segmentHandler(splitSeg)
                    }
                }
            }
        }

        print("Total segments extracted: \(finalSegments.count)")
        progressHandler(1.0)
        return finalSegments
    }

    /// Check if service is ready to transcribe
    var isReady: Bool {
        isInitialized && whisperKit != nil
    }

    /// Reset service state (for switching models)
    func resetState() {
        whisperKit = nil
        isInitialized = false
        isDownloading = false
        downloadProgress = 0
        statusMessage = ""
    }

    /// Clean Whisper special tokens from text
    private func cleanWhisperTokens(_ text: String) -> String {
        var cleaned = text

        // Remove special tokens like <|startoftranscript|>, <|zh|>, <|transcribe|>, <|0.00|>, etc.
        let pattern = "<\\|[^|>]+\\|>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        // Remove any remaining angle bracket tokens
        cleaned = cleaned.replacingOccurrences(of: "<|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "|>", with: "")

        return cleaned
    }

    /// Split a segment at punctuation marks (commas, periods, etc.)
    /// Returns multiple segments with interpolated timestamps
    private func splitSegmentAtPunctuation(_ segment: SubtitleSegment) -> [SubtitleSegment] {
        let text = segment.text

        // Punctuation marks to split on (Chinese and English)
        let splitPattern = "([，。！？,\\.!?])"

        guard let regex = try? NSRegularExpression(pattern: splitPattern, options: []) else {
            return [segment]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        // If no punctuation found, return original segment
        guard !matches.isEmpty else {
            return [segment]
        }

        var segments: [SubtitleSegment] = []
        var lastEnd = 0
        var parts: [String] = []

        // Split text by punctuation, keeping punctuation with the preceding text
        for match in matches {
            let punctuationEnd = match.range.location + match.range.length
            let part = nsText.substring(with: NSRange(location: lastEnd, length: punctuationEnd - lastEnd))
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            lastEnd = punctuationEnd
        }

        // Add remaining text after last punctuation
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty {
                parts.append(remaining)
            }
        }

        // If only one part or empty, return original
        guard parts.count > 1 else {
            return [segment]
        }

        // Calculate total character count for time interpolation
        let totalChars = parts.reduce(0) { $0 + $1.count }
        let totalDuration = segment.duration

        var currentTime = segment.startTime

        for part in parts {
            // Interpolate duration based on character count
            let partDuration = totalDuration * Double(part.count) / Double(totalChars)
            let endTime = currentTime + partDuration

            let newSegment = SubtitleSegment(
                text: part,
                startTime: currentTime,
                endTime: endTime
            )
            segments.append(newSegment)

            currentTime = endTime
        }

        return segments
    }
}
