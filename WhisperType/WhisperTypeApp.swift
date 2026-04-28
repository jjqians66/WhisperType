import SwiftUI
import Combine
import AppKit

@main
struct WhisperTypeApp: App {
    @StateObject private var appState = AppState()
    @State private var overlayController = OverlayWindowController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        terminateOtherRunningInstances()
    }

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
        // Update persistent status dot
        switch state {
        case .idle:       StatusDotController.shared.updateState(.idle)
        case .connecting: StatusDotController.shared.updateState(.connecting)
        case .recording:  StatusDotController.shared.updateState(.recording)
        case .processing: StatusDotController.shared.updateState(.processing)
        }

        switch state {
        case .connecting, .recording, .processing:
            // Dismiss startup toast if still showing
            StartupToastController.shared.hide()
            
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

    private func terminateOtherRunningInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            where app.processIdentifier != currentPID {
            app.terminate()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show the persistent status dot immediately
        StatusDotController.shared.show()
        
        // Show startup toast after a brief delay to let the UI settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            StartupToastController.shared.showIfNeeded()
        }
    }
}

// MARK: - Startup Toast Controller

/// Shows a brief floating banner on app launch so the user knows it's running,
/// even if the menu bar icon is hidden behind the MacBook notch.
@MainActor
class StartupToastController {
    static let shared = StartupToastController()
    
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var hasShown = false

    func showIfNeeded() {
        guard !hasShown else { return }
        hasShown = true

        let toastView = NSHostingView(rootView: StartupToastView())
        // Let the view size itself
        let fittingSize = toastView.fittingSize
        let width = max(fittingSize.width, 300)
        let height = max(fittingSize.height, 70)
        toastView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = toastView
        panel.alphaValue = 0

        // Position at top-center of the main screen, below the menu bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1.0
        }

        // Auto-hide after 4 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }
}

// MARK: - Startup Toast View

struct StartupToastView: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text("WhisperType is running ✓")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Dictate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("⌥D")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }

                    HStack(spacing: 4) {
                        Text("Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("⌥S")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
