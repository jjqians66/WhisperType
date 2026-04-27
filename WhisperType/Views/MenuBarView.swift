import SwiftUI

/// Menu bar dropdown content
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) var openSettings

    var body: some View {
        VStack(spacing: 0) {
            statusSection

            Divider()
                .padding(.vertical, 4)

            recordingSection

            Divider()
                .padding(.vertical, 4)

            languageSection

            Divider()
                .padding(.vertical, 4)

            backendSection

            Divider()
                .padding(.vertical, 4)

            // Last transcription
            if !appState.lastTranscription.isEmpty {
                lastTranscriptionSection
                Divider()
                    .padding(.vertical, 4)
            }

            // Error message
            if let error = appState.errorMessage {
                errorSection(error)
                Divider()
                    .padding(.vertical, 4)
            }

            bottomSection
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Sections

    private var statusSection: some View {
        HStack {
            Image(systemName: appState.menuBarIcon)
                .font(.title2)
                .foregroundStyle(appState.recordingState == .recording ? .red : .primary)
                .symbolEffect(.pulse, isActive: appState.recordingState == .recording)

            VStack(alignment: .leading, spacing: 2) {
                Text("WhisperType")
                    .font(.headline)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.recordingState == .recording {
                AudioLevelView(level: appState.audioLevel)
                    .frame(width: 40, height: 20)
            }
        }
    }

    private var recordingSection: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack {
                Image(systemName: appState.recordingState == .idle ? "record.circle" : "stop.circle.fill")
                    .foregroundStyle(appState.recordingState == .recording ? .red : .primary)
                Text(recordButtonTitle)
                Spacer()
                Text("⌥D")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
        .disabled(appState.recordingState == .processing || appState.recordingState == .connecting)
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Language", selection: $appState.language) {
                Text("Auto Detect").tag("auto")
                Divider()
                Text("English").tag("en")
                Text("中文 (Chinese)").tag("zh")
                Text("日本語 (Japanese)").tag("ja")
                Text("한국어 (Korean)").tag("ko")
                Text("Español (Spanish)").tag("es")
                Text("Français (French)").tag("fr")
                Text("Deutsch (German)").tag("de")
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backend")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Backend", selection: $appState.transcriptionBackend) {
                ForEach(TranscriptionBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var lastTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last Transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(appState.lastTranscription)
                .font(.caption)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 4) {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Settings…")
                }
                .buttonStyle(.plain)
            } else {
                Button("Settings…") {
                    openSettings()
                }
                .buttonStyle(.plain)
            }

            Button("Quit WhisperType") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed

    private var statusText: String {
        switch appState.recordingState {
        case .idle: return "Ready — Press ⌥D to dictate"
        case .connecting: return "Connecting to OpenAI…"
        case .recording: return "Recording… Press ⌥D to stop"
        case .processing: return "Transcribing…"
        }
    }

    private var recordButtonTitle: String {
        switch appState.recordingState {
        case .idle: return "Start Dictation"
        case .connecting: return "Connecting…"
        case .recording: return "Stop & Transcribe"
        case .processing: return "Transcribing…"
        }
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(.green.gradient)
                .frame(width: geo.size.width * CGFloat(level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.1), value: level)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }
}
