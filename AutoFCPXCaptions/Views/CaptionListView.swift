import SwiftUI

/// Displays the list of generated subtitle segments
struct CaptionListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GroupBox {
            if appState.segments.isEmpty {
                emptyState
            } else {
                segmentList
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .font(.headline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No subtitles yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Drop a media file and start transcription")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var segmentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.segments) { segment in
                        SegmentRow(segment: segment)
                            .id(segment.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: appState.segments.count) { _ in
                // Auto-scroll to latest segment
                if let lastSegment = appState.segments.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
    }
}

/// A single row displaying a subtitle segment
struct SegmentRow: View {
    let segment: SubtitleSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timecode
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(segment.startTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))

                Text(formatTime(segment.endTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 80, alignment: .leading)

            // Text
            Text(segment.text)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 25) // Assuming 25fps for display

        if hours > 0 {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
        } else {
            return String(format: "%02d:%02d:%02d", minutes, secs, frames)
        }
    }
}

#Preview {
    CaptionListView()
        .environmentObject({
            let state = AppState()
            state.segments = [
                SubtitleSegment(text: "Hello, this is a test subtitle.", startTime: 0.0, endTime: 2.5),
                SubtitleSegment(text: "This is another line of text.", startTime: 2.6, endTime: 5.0),
                SubtitleSegment(text: "And here's one more for good measure.", startTime: 5.1, endTime: 8.0)
            ]
            return state
        }())
        .padding()
        .frame(width: 500)
}
