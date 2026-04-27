import SwiftUI
import Combine

@main
struct WhisperTypeApp: App {
    @StateObject private var appState = AppState()
    @State private var overlayController = OverlayWindowController()
    @State private var cancellable: AnyCancellable?

    var body: some Scene {

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("WhisperType")
            } icon: {
                Image(systemName: appState.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.recordingState) { _, newState in
            handleStateChange(newState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private func handleStateChange(_ state: AppState.RecordingState) {  
        switch state {
        case .connecting, .recording, .processing:
            let content = WaveformOverlay()
                .environmentObject(appState)
            overlayController.show(content: content)

        case .idle:
            // Brief delay before hiding to show checkmark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                overlayController.hide()
            }
        }

        // Keep overlay content in sync during state changes
        let content = WaveformOverlay()
            .environmentObject(appState)
        overlayController.update(content: content)
    }
}
