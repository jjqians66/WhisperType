import SwiftUI
import ServiceManagement

/// Settings window with General and Transcription tabs
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TranscriptionSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Dictation Hotkey")
                    Spacer()
                    Text("⌥D")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .font(.system(.body, design: .monospaced))
                }

                Text("Press Option + D to toggle dictation on/off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text("Required for global hotkey and text paste")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        openAccessibilitySettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = appState.launchAtLogin
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.launchAtLogin = enabled
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Transcription Tab

struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var apiKeySaved = false

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Transcription Engine", selection: $appState.transcriptionBackend) {
                    ForEach(TranscriptionBackend.allCases) { backend in
                        VStack(alignment: .leading) {
                            Text(backend.displayName)
                            Text(backend.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(backend)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("OpenAI API Key") {
                HStack {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)

                    Button("Save") {
                        appState.transcriptionService.openAIAPIKey = apiKey
                        apiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            apiKeySaved = false
                        }
                    }
                }

                if apiKeySaved {
                    Text("✓ API key saved to Keychain")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text("Used for both Realtime and Whisper APIs. Stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.transcriptionBackend == .realtime {
                Section("Realtime Model") {
                    Picker("Model", selection: $appState.realtimeModel) {
                        Text("GPT-4o Mini Realtime (Fast, Cheaper)")
                            .tag("gpt-4o-mini-realtime-preview")
                        Text("GPT-4o Realtime (Best Quality)")
                            .tag("gpt-4o-realtime-preview")
                    }
                    .pickerStyle(.radioGroup)
                }
            }

            Section("Language") {
                Picker("Default Language", selection: $appState.language) {
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

                Text("Auto Detect works well for Chinese and English. Setting a specific language can improve accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Post-Processing") {
                Toggle("Enable LLM Enhancement", isOn: $appState.enablePostProcessing)
                Text("After transcription, use GPT-4o-mini to improve readability and formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = appState.transcriptionService.openAIAPIKey ?? ""
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)

            Text("WhisperType")
                .font(.title)
                .fontWeight(.bold)

            Text("v2.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Real-time speech-to-text powered by OpenAI.\nSupports Chinese, English, and 90+ languages.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Powered by OpenAI Realtime API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Built with SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
