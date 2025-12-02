import SwiftUI

/// View showing real-time transcription progress with live subtitles
struct TranscriptionProgressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                Text("Transcribing...")
                    .font(.headline)

                Spacer()

                // Progress percentage
                if case .transcribing(let progress) = appState.processingState {
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Progress bar
            if case .transcribing(let progress) = appState.processingState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            // Live subtitle output (terminal style)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.segments.enumerated()), id: \.element.id) { index, segment in
                            LiveSubtitleRow(segment: segment)
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .onChange(of: appState.segments.count) { newCount in
                    // Auto-scroll to bottom
                    withAnimation {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// Single row showing a subtitle segment in terminal style
struct LiveSubtitleRow: View {
    let segment: SubtitleSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timecode
            Text("[\(formatTimecode(segment.startTime)) --> \(formatTimecode(segment.endTime))]")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.green.opacity(0.9))

            // Text content
            Text(segment.text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.white)
        }
    }

    private func formatTimecode(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, ms)
    }
}

#Preview {
    TranscriptionProgressView()
        .environmentObject({
            let state = AppState()
            state.processingState = .transcribing(progress: 0.45)
            state.segments = [
                SubtitleSegment(text: "菲瑞之恩直萃温和节颜油,清爽水感直萃能量,一触即溶", startTime: 0.0, endTime: 9.0),
                SubtitleSegment(text: "顽固彩妆日常妆容三秒容妆容肤,轻松净卸一冲几净", startTime: 9.0, endTime: 17.0),
                SubtitleSegment(text: "超一线大牌同款成分", startTime: 17.0, endTime: 20.0),
                SubtitleSegment(text: "菲瑞之恩直萃温和节颜油,清爽水感直萃能量,一触即溶", startTime: 20.0, endTime: 27.0),
            ]
            return state
        }())
        .padding()
        .frame(width: 600)
}
