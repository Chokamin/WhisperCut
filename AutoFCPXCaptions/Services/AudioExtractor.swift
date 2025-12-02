import Foundation
import AVFoundation

/// Error types for audio extraction
enum AudioExtractorError: LocalizedError {
    case invalidInput
    case exportFailed(String)
    case unsupportedFormat
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid input file"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .unsupportedFormat:
            return "Unsupported audio format"
        case .noAudioTrack:
            return "No audio track found in media"
        }
    }
}

/// Service for extracting and converting audio from media files
/// Converts to Whisper-required format: 16kHz, Mono, Float32
class AudioExtractor {
    // Target format for Whisper
    static let targetSampleRate: Double = 16000
    static let targetChannels: AVAudioChannelCount = 1

    /// Extract audio from media file and convert to Whisper-compatible format
    func extractAudio(from inputURL: URL) async throws -> URL {
        let asset = AVAsset(url: inputURL)

        // Check if asset has audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioExtractorError.noAudioTrack
        }

        // Create output URL in temp directory
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        // Extract and convert audio
        try await extractAndConvert(asset: asset, to: outputURL)

        return outputURL
    }

    private func extractAndConvert(asset: AVAsset, to outputURL: URL) async throws {
        // Load duration and audio tracks
        _ = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            throw AudioExtractorError.noAudioTrack
        }

        // Create asset reader
        let reader = try AVAssetReader(asset: asset)

        // Configure output settings for reading
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw AudioExtractorError.exportFailed(reader.error?.localizedDescription ?? "Failed to start reading")
        }

        // Collect all audio samples
        var audioData = Data()

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                if let dataPointer = dataPointer {
                    audioData.append(UnsafeBufferPointer(start: dataPointer, count: length))
                }
            }
        }

        guard reader.status == .completed else {
            throw AudioExtractorError.exportFailed(reader.error?.localizedDescription ?? "Reading failed")
        }

        // Write WAV file
        try writeWAVFile(audioData: audioData, to: outputURL, sampleRate: Int(Self.targetSampleRate), channels: Int(Self.targetChannels), bitsPerSample: 16)
    }

    private func writeWAVFile(audioData: Data, to url: URL, sampleRate: Int, channels: Int, bitsPerSample: Int) throws {
        var header = Data()

        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = audioData.count
        let fileSize = 36 + dataSize

        // RIFF header
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        header.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Combine header and audio data
        var wavData = header
        wavData.append(audioData)

        try wavData.write(to: url)
    }

    /// Clean up temporary audio files
    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Get media duration in seconds
    func getMediaDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}
