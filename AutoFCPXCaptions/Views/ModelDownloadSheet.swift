import SwiftUI

/// Sheet view for model download progress
struct ModelDownloadSheet: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var whisperService: WhisperService
    @State private var animationOffset: CGFloat = -1.0

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
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

                Text("Downloading Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(appState.selectedModelSize.fullDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress section
            VStack(spacing: 12) {
                // Status message
                Text(whisperService.statusMessage.isEmpty ? "Preparing..." : whisperService.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Animated rainbow progress bar (indeterminate)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)

                        // Animated rainbow gradient
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan, .green, .yellow, .orange, .red, .pink, .purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * 0.4, height: 8)
                            .offset(x: animationOffset * geometry.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 8)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        animationOffset = 0.6
                    }
                }

                // Loading indicator
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Please wait...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Hint
            Text("First time setup - this may take a few minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

#Preview {
    ModelDownloadSheet(whisperService: WhisperService())
        .environmentObject(AppState())
}
