import SwiftUI
import Combine
import AVFoundation
import AppKit

/// Central app state observable by all views.
/// Manages the recording -> transcription -> text insertion flow.
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
    @Published var accessibilityGranted: Bool = false

    // MARK: - Settings

    @AppStorage("language") var language: String = "auto"
    @AppStorage("showOverlay") var showOverlay: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("enablePostProcessing") var enablePostProcessing: Bool = false

    // MARK: - Services

    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let textInserter = TextInserter()
    let hotKeyManager = HotKeyManager()
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
    private var transcriptionTask: Task<Void, Never>?
    private var targetProcessID: pid_t?
    private var lastToggleAt: Date = .distantPast
    private let minimumToggleInterval: TimeInterval = 0.45

    init() {
        // Check accessibility WITHOUT showing the prompt on every launch.
        // Only prompt when the user actually tries to use a feature that needs it.
        accessibilityGranted = AXIsProcessTrusted()
        
        setupHotKey()
        setupAudioLevelMonitoring()
    }
    
    /// Only called when the user explicitly needs accessibility (e.g. first paste attempt)
    /// or from the Settings UI.
    func requestAccessibilityPermission() {
        let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptOption: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityGranted = trusted
    }
    
    /// Re-check accessibility status without prompting
    func recheckAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
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

    // MARK: - Actions

    func toggleRecording() {
        let now = Date()
        guard now.timeIntervalSince(lastToggleAt) >= minimumToggleInterval else {
            print("WhisperType: Ignoring repeated hotkey")
            return
        }
        lastToggleAt = now

        switch recordingState {
        case .idle:
            startWhisperRecording()
        case .recording:
            stopWhisperRecording()
        case .connecting:
            cancelCurrentOperation(reason: "Cancelled")
        case .processing:
            cancelCurrentOperation(reason: "Cancelled transcription")
        }
    }

    // MARK: - Whisper REST Flow

    private func startWhisperRecording() {
        print("WhisperType: startWhisperRecording()")
        guard let apiKey = transcriptionService.openAIAPIKey, !apiKey.isEmpty else {
            errorMessage = "No OpenAI API key. Press ⌥S to open Settings."
            print("WhisperType: No API key")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            recordingState = .connecting
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startWhisperRecording()
                    } else {
                        self.errorMessage = "Microphone access is required for dictation."
                        self.recordingState = .idle
                    }
                }
            }
            return
        case .denied, .restricted:
            errorMessage = "Microphone access is required. Enable it in System Settings."
            return
        @unknown default:
            errorMessage = "Unable to determine microphone permission."
            return
        }

        errorMessage = nil
        targetProcessID = captureTargetProcessID()
        recordingState = .recording
        
        do {
            try audioRecorder.startRecording()
            startTimer()
            print("WhisperType: Recording started successfully")
        } catch {
            errorMessage = "Failed to start mic: \(error.localizedDescription)"
            print("WhisperType: Mic start failed: \(error)")
            recordingState = .idle
        }
    }

    private func stopWhisperRecording() {
        print("WhisperType: stopWhisperRecording()")
        guard recordingState == .recording else { return }
        
        audioRecorder.stopRecording()
        stopTimer()
        recordingState = .processing
        streamingText = "Transcribing..."
        
        guard let pcmData = try? audioRecorder.getAudioData() else {
            errorMessage = "Failed to process audio"
            print("WhisperType: Failed to get audio data from recorder")
            recordingState = .idle
            return
        }
        
        print("WhisperType: Got \(pcmData.count) bytes of audio data")
        
        // Convert to WAV for Whisper API
        let wavData = createWAVHeader(data: pcmData, sampleRate: 24000, channels: 1) + pcmData
        let targetPID = targetProcessID
        print("WhisperType: WAV data size: \(wavData.count) bytes")
        
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self, wavData, targetPID] in
            guard let self else { return }
            do {
                let languageToPass = await MainActor.run { (self.language == "auto") ? nil : self.language }
                print("WhisperType: Calling Whisper API with language: \(languageToPass ?? "auto")")
                let text = try await self.transcriptionService.transcribeWithWhisperAPI(audioData: wavData, language: languageToPass)
                guard !Task.isCancelled else { return }
                
                print("WhisperType: Whisper API returned \(text.count) characters: \(text)")
                await self.handleTranscriptionComplete(text, targetProcessID: targetPID)
            } catch {
                guard !Task.isCancelled else { return }
                print("WhisperType: Whisper API error: \(error)")
                await MainActor.run {
                    self.errorMessage = "Whisper API failed: \(error.localizedDescription)"
                    self.recordingState = .idle
                    self.streamingText = ""
                    self.transcriptionTask = nil
                    self.targetProcessID = nil
                }
            }
        }
    }
    
    private func createWAVHeader(data: Data, sampleRate: Int, channels: Int) -> Data {
        let byteRate = sampleRate * channels * 2
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + data.count).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels).littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var sampleRate32 = UInt32(sampleRate).littleEndian
        header.append(Data(bytes: &sampleRate32, count: 4))
        var byteRate32 = UInt32(byteRate).littleEndian
        header.append(Data(bytes: &byteRate32, count: 4))
        var blockAlign = UInt16(channels * 2).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        header.append(Data(bytes: &bitsPerSample, count: 2))
        header.append(contentsOf: "data".utf8)
        var subchunk2Size = UInt32(data.count).littleEndian
        header.append(Data(bytes: &subchunk2Size, count: 4))
        return header
    }

    private func handleTranscriptionComplete(_ text: String, targetProcessID: pid_t?) async {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove the anti-hallucination marker prefix if present
        let marker = "[TRANSCRIPT_START]"
        if trimmed.hasPrefix(marker) {
            trimmed = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            errorMessage = "No speech detected"
            recordingState = .idle
            streamingText = ""
            transcriptionTask = nil
            self.targetProcessID = nil
            return
        }

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

        guard !Task.isCancelled else { return }

        lastTranscription = finalText
        streamingText = finalText
        
        // Re-check accessibility right before paste attempt
        recheckAccessibility()
        
        if accessibilityGranted {
            let pasteRequested = textInserter.insertText(finalText, targetProcessID: targetProcessID)
            if !pasteRequested {
                // This shouldn't happen if AXIsProcessTrusted() was true, but handle gracefully
                errorMessage = "Text copied to clipboard. Press ⌘V to paste."
            }
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(finalText, forType: .string)
            errorMessage = "Text copied to clipboard. Grant Accessibility in System Settings for auto-paste."
        }
        
        recordingState = .idle
        transcriptionTask = nil
        self.targetProcessID = nil
    }

    // MARK: - Timer & Limits

    private func startTimer() {
        recordingDuration = 0
        updateStreamingTextForTimer()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recordingDuration += 1.0
                self.updateStreamingTextForTimer()
                
                // Hard limit at 5 minutes (300 seconds)
                if self.recordingDuration >= 300 {
                    self.stopWhisperRecording()
                }
            }
        }
    }
    
    private func updateStreamingTextForTimer() {
        let remaining = 300 - Int(recordingDuration)
        let mins = Int(recordingDuration) / 60
        let secs = Int(recordingDuration) % 60
        let timeStr = String(format: "%d:%02d", mins, secs)
        
        if remaining <= 30 {
            streamingText = "⚠️ \(timeStr) / 5:00 (Auto-stopping in \(remaining)s)"
        } else {
            streamingText = "Recording... \(timeStr) / 5:00"
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func cancelCurrentOperation(reason: String) {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        audioRecorder.stopRecording()
        stopTimer()
        targetProcessID = nil
        errorMessage = reason
        streamingText = ""
        recordingState = .idle
    }

    private func captureTargetProcessID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard app.processIdentifier != currentPID else { return nil }
        print("WhisperType: Target app = \(app.localizedName ?? "unknown") pid=\(app.processIdentifier)")
        return app.processIdentifier
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
