import SwiftUI
import Combine

/// Central app state observable by all views.
/// Manages the recording → streaming → transcription → text insertion flow.
@MainActor
class AppState: ObservableObject {

    // MARK: - Recording State

    enum RecordingState: Equatable {
        case idle
        case connecting
        case recording
        case processing
    }

    @Published var recordingState: RecordingState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 7)
    @Published var streamingText: String = ""
    @Published var lastTranscription: String = ""
    @Published var errorMessage: String?
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Settings

    @AppStorage("transcriptionBackend") var transcriptionBackend: TranscriptionBackend = .realtime
    @AppStorage("language") var language: String = "auto"
    @AppStorage("showOverlay") var showOverlay: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("enablePostProcessing") var enablePostProcessing: Bool = false
    @AppStorage("realtimeModel") var realtimeModel: String = "gpt-4o-mini-realtime-preview"

    // MARK: - Services

    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let textInserter = TextInserter()
    let hotKeyManager = HotKeyManager()
    let realtimeClient = RealtimeClient()
    let textPostProcessor = TextPostProcessor()

    // MARK: - Computed

    var menuBarIcon: String {
        switch recordingState {
        case .idle: return "mic"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        }
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?

    init() {
        checkAccessibilityPermissions()
        setupHotKey()
        setupAudioLevelMonitoring()
        setupRealtimeCallbacks()
    }
    
    private func checkAccessibilityPermissions() {
        // This is the ONLY way to force macOS to prompt the user for Accessibility
        let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptOption: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Setup

    private func setupHotKey() {
        hotKeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        
        hotKeyManager.onSettings = { [weak self] in
            DispatchQueue.main.async {
                if let self = self {
                    SettingsWindowController.shared.showSettings(appState: self)
                }
            }
        }
    }

    private func setupAudioLevelMonitoring() {
        audioRecorder.$currentLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        audioRecorder.$frequencyBands
            .receive(on: DispatchQueue.main)
            .assign(to: &$frequencyBands)
    }

    private func setupRealtimeCallbacks() {
        realtimeClient.onTextDelta = { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                var text = self.realtimeClient.streamingText
                let marker = "[TRANSCRIPT_START]"
                if text.hasPrefix(marker) {
                    text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if text.hasPrefix("[TRANSCRIPT_") {
                    text = "" // Hide partial marker
                }
                self.streamingText = text
            }
        }

        realtimeClient.onResponseDone = { [weak self] finalText in
            Task { @MainActor in
                self?.handleTranscriptionComplete(finalText)
            }
        }

        realtimeClient.onError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error
                self?.recordingState = .idle
                self?.stopTimer()
                self?.audioRecorder.stopRecording()
            }
        }
    }

    // MARK: - Actions

    func toggleRecording() {
        switch recordingState {
        case .idle:
            startRealtimeRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .connecting, .processing:
            break
        }
    }

    // MARK: - Realtime Flow

    private func startRealtimeRecording() {
        guard let apiKey = transcriptionService.openAIAPIKey, !apiKey.isEmpty else {
            errorMessage = "No OpenAI API key. Please set it in Settings."
            return
        }

        errorMessage = nil
        streamingText = ""
        recordingState = .connecting

        Task {
            do {
                // 1. Connect to OpenAI Realtime API
                try await realtimeClient.connect(apiKey: apiKey, model: realtimeModel)

                // 2. Wire audio recorder → realtime client
                audioRecorder.onAudioChunk = { [weak self] chunk in
                    Task {
                        try? await self?.realtimeClient.sendAudio(chunk)
                    }
                }

                // 3. Start recording
                try audioRecorder.startRecording()
                recordingState = .recording
                startTimer()

            } catch {
                errorMessage = "Failed to start: \(error.localizedDescription)"
                recordingState = .idle
                await realtimeClient.disconnect()
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard recordingState == .recording else { return }

        // Stop recording
        audioRecorder.stopRecording()
        audioRecorder.onAudioChunk = nil
        stopTimer()
        recordingState = .processing

        Task {
            do {
                // Commit audio and request transcription
                try await realtimeClient.commitAndRespond()
                // Response will arrive via onResponseDone callback
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                recordingState = .idle
                await realtimeClient.disconnect()
            }
        }
    }

    private func handleTranscriptionComplete(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove the anti-hallucination marker prefix if present
        let marker = "[TRANSCRIPT_START]"
        if trimmed.hasPrefix(marker) {
            trimmed = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            errorMessage = "No speech detected"
            recordingState = .idle
            Task { await realtimeClient.disconnect() }
            return
        }

        Task {
            var finalText = trimmed

            // Optional LLM post-processing
            if enablePostProcessing,
               let apiKey = transcriptionService.openAIAPIKey {
                do {
                    finalText = try await textPostProcessor.enhance(trimmed, apiKey: apiKey)
                } catch {
                    // Fall back to raw transcription on error
                    errorMessage = "Enhancement failed, using raw transcription"
                }
            }

            lastTranscription = finalText
            textInserter.insertText(finalText)
            recordingState = .idle
            await realtimeClient.disconnect()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

// MARK: - Settings Window Controller

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings(appState: AppState) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("Settings")
        window.isReleasedWhenClosed = false
        window.title = "WhisperType Settings"
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(appState))

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
