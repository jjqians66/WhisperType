import SwiftUI

/// Floating recording indicator HUD near the menu bar.
/// Temporary — will be replaced by WaveformOverlay in Phase 2.
struct RecordingOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.recordingState != .idle && appState.showOverlay {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.recordingState == .recording ? .red : .orange)
                    .frame(width: 10, height: 10)
                    .shadow(color: appState.recordingState == .recording ? .red.opacity(0.5) : .clear,
                            radius: 4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                              value: appState.recordingState)

                Text(overlayText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)

                if appState.recordingState == .recording {
                    AudioLevelView(level: appState.audioLevel)
                        .frame(width: 30, height: 12)
                }

                if appState.recordingState == .processing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: appState.recordingState)
        }
    }

    private var overlayText: String {
        switch appState.recordingState {
        case .idle: return ""
        case .connecting: return "Connecting…"
        case .recording: return "Recording…"
        case .processing: return "Transcribing…"
        }
    }
}
