import SwiftUI

/// Displays the list of generated subtitle segments
struct CaptionListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Label
            HStack {
                Label("Subtitles", systemImage: "captions.bubble")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Content area with fixed background
            ZStack {
                // Always show the background to maintain consistent appearance
                segmentListBackground
                
                if appState.segments.isEmpty {
                    emptyState
                } else {
                    segmentList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var segmentListBackground: some View {
        Color.black.opacity(0.85)
            .cornerRadius(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.4))

            Text("No subtitles yet")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Text("Drop a media file and start transcription")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onChange(of: appState.segments.count) { newCount in
                // Auto-scroll to latest segment with smooth animation
                if let lastSegment = appState.segments.last {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)) {
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1), value: appState.segments.count)
    }
}

/// A single row displaying a subtitle segment
struct SegmentRow: View {
    let segment: SubtitleSegment
    @State private var isVisible = false

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
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.92)
        .offset(y: isVisible ? 0 : 8)
        .onAppear {
            // iMessage-style smooth animation
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)) {
                isVisible = true
            }
        }
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
