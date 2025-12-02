import SwiftUI

/// A view that displays the drop zone UI (drag handling is done in ContentView)
struct DragDropView: View {
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [10, 5]
                    )
                )
                .foregroundStyle(Color.secondary.opacity(0.5))

            // Content
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.4, blue: 0.95),  // Blue
                                Color(red: 0.0, green: 0.8, blue: 0.95),  // Cyan
                                Color(red: 0.2, green: 0.9, blue: 0.4),   // Green
                                Color(red: 1.0, green: 0.95, blue: 0.3),  // Yellow
                                Color(red: 1.0, green: 0.6, blue: 0.2),   // Orange
                                Color(red: 1.0, green: 0.3, blue: 0.35),  // Red
                                Color(red: 0.95, green: 0.4, blue: 0.7),  // Pink
                                Color(red: 0.7, green: 0.3, blue: 0.9)    // Purple
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Drop Media File Here")
                    .font(.headline)

                Text("Supports: MP4, MOV, M4A, MP3, WAV")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DragDropView()
        .padding()
        .frame(width: 400, height: 300)
}
