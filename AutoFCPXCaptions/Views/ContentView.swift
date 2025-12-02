import SwiftUI
import UniformTypeIdentifiers

/// Main content view of the application
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragTargeted = false

    /// Check if media file is loaded
    private var hasMedia: Bool {
        appState.mediaURL != nil
    }

    /// Check if we have segments to show
    private var hasSegments: Bool {
        !appState.segments.isEmpty
    }

    /// Track if we've ever had media (to show compact layout after first file)
    @State private var hasEverHadMedia = false

    /// Show compact layout (after first file is loaded, even if deleted)
    private var showCompactLayout: Bool {
        hasMedia || hasEverHadMedia
    }

    var body: some View {
        ZStack {
            // Background with material effect
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Main content - only show when in compact layout
            if showCompactLayout {
                VStack(spacing: 16) {
                    // Header
                    headerSection

                    // Top section: File + Settings (compact layout)
                    compactTopSection
                        .padding(.horizontal)

                    // Action Buttons (always visible in compact mode)
                    actionButtons
                        .padding(.horizontal)

                    // Processing Status / Caption List - this is the main area
                    processingStatusView
                        .padding(.horizontal)
                }
                .padding(.vertical, 16)
            }

            // Drop zone UI - only show on first launch (before any file is loaded)
            if !showCompactLayout {
                // Full area drop zone with border
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragTargeted ? Color.blue : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isDragTargeted ? 3 : 2, dash: [10, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragTargeted ? Color.blue.opacity(0.1) : Color.clear)
                    )
                    .padding(16)
                    .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: isDragTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.3, green: 0.4, blue: 0.95),
                                            Color(red: 0.0, green: 0.8, blue: 0.95),
                                            Color(red: 0.2, green: 0.9, blue: 0.4),
                                            Color(red: 1.0, green: 0.95, blue: 0.3),
                                            Color(red: 1.0, green: 0.6, blue: 0.2),
                                            Color(red: 1.0, green: 0.3, blue: 0.35),
                                            Color(red: 0.95, green: 0.4, blue: 0.7),
                                            Color(red: 0.7, green: 0.3, blue: 0.9)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(isDragTargeted ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isDragTargeted)

                            Text(isDragTargeted ? "Release to Add File" : "Drop Media File Here")
                                .font(.headline)
                                .foregroundColor(isDragTargeted ? Color.primary : Color.primary.opacity(0.8))

                            Text("Supports: MP4, MOV, M4A, MP3, WAV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openFilePicker()
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                        handleDrop(providers: providers)
                    }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $appState.showModelDownloadSheet) {
            ModelDownloadSheet(whisperService: appState.whisperService)
                .environmentObject(appState)
        }
        .onChange(of: hasMedia) { newValue in
            if newValue {
                hasEverHadMedia = true
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        appState.handleDroppedFile(url)
                    }
                } else if let url = item as? URL {
                    DispatchQueue.main.async {
                        appState.handleDroppedFile(url)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Compact Top Section (File info + Settings in one row)

    private var compactTopSection: some View {
        HStack(spacing: 16) {
            // File info - compact
            compactFileInfo
                .frame(maxWidth: .infinity)

            // Settings - compact
            compactSettings
                .frame(maxWidth: .infinity)
        }
    }

    private var compactFileInfo: some View {
        GroupBox {
            if hasMedia {
                // Show file info when media is loaded
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.mediaFileName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if appState.modelReady {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption2)
                                Text("Model: \(appState.selectedModelSize.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        appState.clearMedia()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            } else {
                // Show drop zone when no media
                fileDropZone
            }
        } label: {
            Label("File", systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @State private var isFileDropTargeted = false

    private var fileDropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: isFileDropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan, .green, .yellow, .orange, .red, .pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isFileDropTargeted ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isFileDropTargeted)

            VStack(alignment: .leading, spacing: 2) {
                Text(isFileDropTargeted ? "Release to Add File" : "Drop or Click to Add File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isFileDropTargeted ? Color.primary : Color.secondary)

                Text("MP4, MOV, M4A, MP3, WAV")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFileDropTargeted ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 2])
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFileDropTargeted ? Color.blue.opacity(0.1) : Color.clear)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFileDropTargeted)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onTapGesture {
            openFilePicker()
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.movie,
            UTType.audio,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.mp3,
            UTType.wav
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a media file to transcribe"

        if panel.runModal() == .OK, let url = panel.url {
            appState.handleDroppedFile(url)
        }
    }

    private var compactSettings: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Text("FPS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Picker("", selection: $appState.selectedFrameRate) {
                        ForEach(FrameRate.allCases) { rate in
                            Text(rate.rawValue).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("Lang")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Picker("", selection: $appState.selectedLanguage) {
                        ForEach(RecognitionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { appState.selectedModelSize },
                        set: { appState.switchModel(to: $0) }
                    )) {
                        ForEach(WhisperModelSize.allCases) { size in
                            Text(size.fullDescription).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // Model management buttons
                HStack(spacing: 8) {
                    // Show model path button
                    Button {
                        appState.openModelCacheInFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text("Show Path")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Delete model button
                    Button {
                        if appState.isModelDownloaded(appState.selectedModelSize) {
                            Task {
                                await appState.deleteSpecificModel(appState.selectedModelSize)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if appState.isDeletingModel {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            } else if appState.modelDeletionComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "trash")
                                    .font(.caption2)
                            }
                            Text(appState.isDeletingModel ? "Deleting..." :
                                    appState.modelDeletionComplete ? "Deleted" :
                                    appState.isModelDownloaded(appState.selectedModelSize) ? "Delete Model" : "Not Downloaded")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.isModelDownloaded(appState.selectedModelSize) || appState.isDeletingModel)
                }
            }
            .padding(4)
        } label: {
            Label("Settings", systemImage: "gear")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Processing Status View

    @ViewBuilder
    private var processingStatusView: some View {
        VStack(spacing: 8) {
            // Status indicator at top
            statusIndicator

            // Caption list takes remaining space
            if hasSegments || appState.processingState.isTranscribing {
                CaptionListView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasMedia {
                // Empty state when media loaded but no transcription yet
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch appState.processingState {
        case .downloadingModel:
            VStack(spacing: 8) {
                ProgressView()
                Text("Downloading model...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("First time setup - this may take a few minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .loadingModel:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading model...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

        case .extractingAudio:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Extracting audio...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

        case .transcribing(let progress):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }

                // Progress bar with rainbow gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Rainbow progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan, .green, .yellow, .orange, .red, .pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 8)

        case .completed:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Full progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Rainbow progress (full)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan, .green, .yellow, .orange, .red, .pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 8)

        case .error(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .padding(.vertical, 8)

        case .generatingXML:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating FCPXML...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

        case .idle:
            EmptyView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            Text("WhisperCut")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("Drag. Transcribe. Import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary actions row
            HStack(spacing: 16) {
                // Start Transcription
                Button {
                    Task {
                        await appState.startTranscription()
                    }
                } label: {
                    Label("Start Transcription", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(appState.processingState.isProcessing)

                // Export to FCPX
                Button {
                    print("Export button tapped! Segments: \(appState.segments.count), State: \(appState.processingState)")
                    Task {
                        await appState.exportToFCPX()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image("fcpx_icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                        Text("Import to Final Cut Pro")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .disabled(appState.segments.isEmpty)
            }
            .controlSize(.large)

            // Download buttons row
            HStack(spacing: 16) {
                // Download SRT
                Button {
                    Task {
                        await appState.downloadSRT()
                    }
                } label: {
                    Label("Download SRT", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(appState.segments.isEmpty)

                // Download FCPXML
                Button {
                    Task {
                        await appState.downloadFCPXML()
                    }
                } label: {
                    Label("Download FCPXML", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(appState.segments.isEmpty)
            }
            .controlSize(.large)
        }
    }
}

// MARK: - Visual Effect View (NSVisualEffectView wrapper)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 600, height: 700)
}
