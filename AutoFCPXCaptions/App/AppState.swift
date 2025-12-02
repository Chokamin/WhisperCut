import Foundation
import SwiftUI

/// Supported recognition languages
enum RecognitionLanguage: String, CaseIterable, Identifiable {
    case chineseSimplified = "简体中文"
    case chineseTraditional = "繁體中文"
    case english = "English"

    var id: String { rawValue }

    /// Language code used by Whisper
    var whisperCode: String {
        switch self {
        case .chineseSimplified: return "zh"
        case .chineseTraditional: return "zh"
        case .english: return "en"
        }
    }

    /// Display label for pickers
    var displayName: String { rawValue }
}

/// Processing state of the application
enum ProcessingState: Equatable {
    case idle
    case downloadingModel
    case loadingModel
    case extractingAudio
    case transcribing(progress: Double)
    case generatingXML
    case completed
    case error(message: String)

    var isProcessing: Bool {
        switch self {
        case .idle, .completed, .error:
            return false
        default:
            return true
        }
    }

    var isTranscribing: Bool {
        if case .transcribing = self {
            return true
        }
        return false
    }

    var statusMessage: String {
        switch self {
        case .idle:
            return "Ready"
        case .downloadingModel:
            return "Downloading model..."
        case .loadingModel:
            return "Loading model..."
        case .extractingAudio:
            return "Extracting audio..."
        case .transcribing(let progress):
            return "Transcribing... \(Int(progress * 100))%"
        case .generatingXML:
            return "Generating FCPXML..."
        case .completed:
            return "Completed!"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// Available model sizes for WhisperKit
enum WhisperModelSize: String, CaseIterable, Identifiable {
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3 = "large-v3"

    var id: String { rawValue }

    /// Short display name for picker
    var displayName: String {
        switch self {
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largev3: return "Large-v3"
        }
    }

    /// Size description
    var sizeDescription: String {
        switch self {
        case .base: return "~150MB"
        case .small: return "~500MB"
        case .medium: return "~1.5GB"
        case .largev3: return "~3GB"
        }
    }

    /// Quality description
    var qualityDescription: String {
        switch self {
        case .base: return "Fast, lower accuracy"
        case .small: return "Balanced (Recommended)"
        case .medium: return "Good accuracy"
        case .largev3: return "Best accuracy"
        }
    }

    /// Full description for display
    var fullDescription: String {
        "\(displayName) (\(sizeDescription)) - \(qualityDescription)"
    }
}

/// Main application state managed as an ObservableObject
@MainActor
class AppState: ObservableObject {
    // MARK: - Settings
    @Published var selectedFrameRate: FrameRate = .fps25
    @Published var selectedLanguage: RecognitionLanguage = .chineseSimplified
    @Published var selectedModelSize: WhisperModelSize = .small

    // MARK: - Media
    @Published var mediaURL: URL?
    @Published var mediaFileName: String = ""

    // MARK: - Processing
    @Published var processingState: ProcessingState = .idle
    @Published var segments: [SubtitleSegment] = []
    @Published var mediaDuration: TimeInterval = 0
    @Published var transcriptionProgress: Double = 0

    // MARK: - Output
    @Published var generatedXMLURL: URL?

    // MARK: - Model Management
    @Published var showModelDownloadSheet: Bool = false
    @Published var modelReady: Bool = false
    @Published var isDeletingModel: Bool = false
    @Published var modelDeletionComplete: Bool = false

    // MARK: - Services
    let whisperService = WhisperService()
    private let audioExtractor = AudioExtractor()
    private let srtGenerator = SRTGenerator()

    // MARK: - Computed Properties

    /// Check if model is ready
    var hasModel: Bool {
        whisperService.isInitialized
    }

    // MARK: - Methods

    /// Reset to initial state
    func reset() {
        mediaURL = nil
        mediaFileName = ""
        processingState = .idle
        segments = []
        generatedXMLURL = nil
        mediaDuration = 0
        transcriptionProgress = 0
    }

    /// Clear only media-related state (keeps settings intact)
    func clearMedia() {
        mediaURL = nil
        mediaFileName = ""
        processingState = .idle
        segments = []
        generatedXMLURL = nil
        mediaDuration = 0
        transcriptionProgress = 0
    }

    /// Handle dropped media file
    func handleDroppedFile(_ url: URL) {
        let supportedExtensions = ["mp4", "mov", "m4a", "mp3", "wav"]
        let fileExtension = url.pathExtension.lowercased()

        guard supportedExtensions.contains(fileExtension) else {
            processingState = .error(message: "Unsupported file format. Please use: \(supportedExtensions.joined(separator: ", "))")
            return
        }

        mediaURL = url
        mediaFileName = url.lastPathComponent
        processingState = .idle
        segments = []
    }

    /// Start the transcription process
    func startTranscription() async {
        guard let mediaURL = mediaURL else {
            processingState = .error(message: "No media file selected")
            return
        }

        // Clear previous segments and reset progress
        segments = []
        transcriptionProgress = 0

        do {
            // 1. Initialize Whisper model if needed
            try await initializeWhisperIfNeeded()

            // 2. Get media duration for progress calculation
            mediaDuration = try await audioExtractor.getMediaDuration(from: mediaURL)
            print("Media duration: \(mediaDuration) seconds")

            // 3. Extract audio
            processingState = .extractingAudio
            let audioURL = try await audioExtractor.extractAudio(from: mediaURL)

            // 4. Transcribe based on selected engine
            processingState = .transcribing(progress: 0.0)

            // Clear segments before starting (in case of re-transcription)
            self.segments = []

            let transcribedSegments = try await transcribeWithWhisper(audioURL: audioURL)

            // Wait a moment for any pending segment handlers to complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

            // Use transcribed segments as final source of truth
            self.segments = transcribedSegments
            self.transcriptionProgress = 1.0
            print("AppState segments count: \(self.segments.count)")

            // 5. Cleanup temp audio file
            try? FileManager.default.removeItem(at: audioURL)

            processingState = .completed

        } catch {
            processingState = .error(message: error.localizedDescription)
        }
    }

    /// Initialize Whisper service if needed
    private func initializeWhisperIfNeeded() async throws {
        if !whisperService.isReady {
            let modelAlreadyDownloaded = isModelDownloaded(selectedModelSize)

            if !modelAlreadyDownloaded {
                showModelDownloadSheet = true
                processingState = .downloadingModel
            } else {
                processingState = .loadingModel
            }

            do {
                try await whisperService.initialize(modelName: selectedModelSize.rawValue)
                modelReady = true
            } catch {
                showModelDownloadSheet = false
                throw error
            }
            showModelDownloadSheet = false
        }
    }

    /// Transcribe using Whisper
    private func transcribeWithWhisper(audioURL: URL) async throws -> [SubtitleSegment] {
        return try await whisperService.transcribe(
            audioURL: audioURL,
            language: selectedLanguage,
            mediaDuration: mediaDuration,
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.transcriptionProgress = progress
                    self?.processingState = .transcribing(progress: progress)
                }
            },
            segmentHandler: { [weak self] segment in
                Task { @MainActor in
                    guard let self = self else { return }
                    if !self.segments.contains(where: { $0.id == segment.id }) {
                        self.segments.append(segment)
                    }
                }
            }
        )
    }

    /// Merge segments with gaps less than 2 seconds
    /// If the gap between two segments is less than 2 seconds, extend the previous segment to the start of the next one
    private func mergeCloseSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard segments.count > 1 else { return segments }
        
        // Sort segments by start time to ensure correct processing order
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        
        var result: [SubtitleSegment] = []
        let minGap: TimeInterval = 2.0 // 2 seconds
        
        for (index, segment) in sortedSegments.enumerated() {
            if index == 0 {
                // First segment, just add it
                result.append(segment)
            } else {
                var previousSegment = result[result.count - 1]
                let gap = segment.startTime - previousSegment.endTime
                
                if gap < minGap && gap >= 0 {
                    // Gap is less than 2 seconds (including 0 for overlapping segments)
                    // Extend previous segment to start of current segment to eliminate gap
                    previousSegment.endTime = segment.startTime
                    result[result.count - 1] = previousSegment
                    result.append(segment)
                } else if gap < 0 {
                    // Segments overlap, extend previous segment to current segment's start
                    previousSegment.endTime = segment.startTime
                    result[result.count - 1] = previousSegment
                    result.append(segment)
                } else {
                    // Gap is 2 seconds or more, keep as is
                    result.append(segment)
                }
            }
        }
        
        return result
    }

    /// Export to FCPXML and open in Final Cut Pro
    func exportToFCPX() async {
        print("exportToFCPX called. Segments count: \(segments.count)")

        guard !segments.isEmpty else {
            print("No segments to export!")
            processingState = .error(message: "No subtitles to export")
            return
        }

        processingState = .generatingXML

        do {
            // 1. Merge segments with gaps less than 2 seconds
            let mergedSegments = mergeCloseSegments(segments)
            print("After merging: \(mergedSegments.count) segments (was \(segments.count))")
            
            // 2. Generate FCPXML
            print("Generating FCPXML with \(mergedSegments.count) segments...")
            let generator = FCPXMLGenerator(frameRate: selectedFrameRate)
            let xmlURL = try generator.generate(segments: mergedSegments, mediaFileName: mediaFileName)

            print("FCPXML generated at: \(xmlURL.path)")

            // 2. Store the URL
            generatedXMLURL = xmlURL

            // 3. Copy to Desktop for easy access
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let destinationURL = desktopURL.appendingPathComponent("AutoCaptions_\(mediaFileName).fcpxml")

            // Remove existing file
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: xmlURL, to: destinationURL)

            print("FCPXML copied to: \(destinationURL.path)")

            // 4. Open with Final Cut Pro
            let workspace = NSWorkspace.shared
            workspace.open(destinationURL)

            processingState = .completed
        } catch {
            print("Export error: \(error)")
            processingState = .error(message: error.localizedDescription)
        }
    }

    /// Download SRT file with save dialog
    func downloadSRT() async {
        guard !segments.isEmpty else {
            processingState = .error(message: "No subtitles to export")
            return
        }

        do {
            // Merge segments with gaps less than 2 seconds
            let mergedSegments = mergeCloseSegments(segments)
            let tempURL = try srtGenerator.generate(segments: mergedSegments, mediaFileName: mediaFileName)
            let suggestedName = mediaFileName.isEmpty ? "subtitles" : (mediaFileName as NSString).deletingPathExtension
            _ = await SRTGenerator.saveWithDialog(from: tempURL, suggestedName: suggestedName)

            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("SRT export error: \(error)")
            processingState = .error(message: error.localizedDescription)
        }
    }

    /// Download FCPXML file with save dialog
    func downloadFCPXML() async {
        guard !segments.isEmpty else {
            processingState = .error(message: "No subtitles to export")
            return
        }

        do {
            // Merge segments with gaps less than 2 seconds
            let mergedSegments = mergeCloseSegments(segments)
            let generator = FCPXMLGenerator(frameRate: selectedFrameRate)
            let tempURL = try generator.generate(segments: mergedSegments, mediaFileName: mediaFileName)
            let suggestedName = mediaFileName.isEmpty ? "subtitles" : (mediaFileName as NSString).deletingPathExtension
            _ = await FCPXMLGenerator.saveWithDialog(from: tempURL, suggestedName: suggestedName)

            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("FCPXML export error: \(error)")
            processingState = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Model Management

    /// Get the model cache directory path (WhisperKit downloads to Documents/huggingface)
    static var modelCachePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
    }

    /// Get model cache directory path as string
    static var modelCachePathString: String {
        modelCachePath.path
    }

    /// Check if model cache exists
    static var modelCacheExists: Bool {
        FileManager.default.fileExists(atPath: modelCachePath.path)
    }

    /// Get model cache size in bytes
    static func getModelCacheSize() -> Int64 {
        guard modelCacheExists else { return 0 }

        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(at: modelCachePath, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    /// Get formatted model cache size
    static func getFormattedCacheSize() -> String {
        let size = getModelCacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Delete all model cache
    func deleteModelCache() {
        let fileManager = FileManager.default
        let cachePath = AppState.modelCachePath

        guard fileManager.fileExists(atPath: cachePath.path) else { return }

        do {
            try fileManager.removeItem(at: cachePath)
            modelReady = false
            whisperService.resetState()
            print("Model cache deleted successfully")
        } catch {
            print("Failed to delete model cache: \(error)")
        }
    }

    /// Open model cache folder in Finder
    func openModelCacheInFinder() {
        let cachePath = AppState.modelCachePath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cachePath.path)
    }

    /// Switch to a different model (resets the current model state)
    func switchModel(to newModel: WhisperModelSize) {
        if selectedModelSize != newModel {
            selectedModelSize = newModel
            modelReady = false
            whisperService.resetState()
        }
    }

    /// Check if a specific model is downloaded
    func isModelDownloaded(_ model: WhisperModelSize) -> Bool {
        // WhisperKit stores models in: ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-{model}
        let cachePath = AppState.modelCachePath

        guard FileManager.default.fileExists(atPath: cachePath.path) else { return false }

        // Check for model directory directly
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: cachePath.path) else {
            return false
        }

        // Model directories look like: openai_whisper-medium, openai_whisper-large-v3
        for item in contents {
            if item.hasPrefix("openai_whisper-") && item.lowercased().contains(model.rawValue.lowercased()) {
                return true
            }
        }
        return false
    }

    /// Delete specific model from cache
    func deleteSpecificModel(_ model: WhisperModelSize) async {
        isDeletingModel = true
        modelDeletionComplete = false

        let cachePath = AppState.modelCachePath

        guard FileManager.default.fileExists(atPath: cachePath.path) else {
            isDeletingModel = false
            return
        }

        // Find and delete model-specific folders
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cachePath.path) {
            for item in contents {
                if item.hasPrefix("openai_whisper-") && item.lowercased().contains(model.rawValue.lowercased()) {
                    let itemPath = cachePath.appendingPathComponent(item)
                    try? FileManager.default.removeItem(at: itemPath)
                    print("Deleted model directory: \(itemPath.path)")
                }
            }
        }

        // Reset model state if we deleted the currently selected model
        if model == selectedModelSize {
            modelReady = false
            whisperService.resetState()
        }

        // Small delay for visual feedback
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

        isDeletingModel = false
        modelDeletionComplete = true

        // Reset completion flag after a short delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        modelDeletionComplete = false
    }
}
