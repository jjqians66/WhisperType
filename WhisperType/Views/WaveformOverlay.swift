import SwiftUI

/// ChatGPT-inspired floating recording overlay with animated waveform.
struct WaveformOverlay: View {
    @EnvironmentObject var appState: AppState

    @State private var ringRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: 12) {
            // Top: animated indicator
            ZStack {
                // Outer gradient ring (recording)
                if appState.recordingState == .recording {
                    gradientRing
                }

                // Center icon
                centerIcon
            }
            .frame(width: 80, height: 80)

            // Waveform bars (recording)
            if appState.recordingState == .recording {
                waveformBars
            }

            // Timer (recording)
            if appState.recordingState == .recording {
                timerLabel
            }

            // Streaming text (processing)
            if appState.recordingState == .processing {
                streamingTextView
            }

            // Connecting indicator
            if appState.recordingState == .connecting {
                connectingDots
            }

            // Status label
            statusLabel
        }
        .padding(24)
        .frame(minWidth: 200, maxWidth: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { startAnimations() }
    }

    // MARK: - Gradient Ring

    private var gradientRing: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [.blue, .purple, .pink, .blue],
                    center: .center,
                    startAngle: .degrees(ringRotation),
                    endAngle: .degrees(ringRotation + 360)
                ),
                lineWidth: 3
            )
            .frame(width: 76, height: 76)
            .blur(radius: 1)
            .scaleEffect(pulseScale)
    }

    // MARK: - Center Icon

    private var centerIcon: some View {
        Group {
            switch appState.recordingState {
            case .connecting:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                    .scaleEffect(pulseScale)

            case .processing:
                ProgressView()
                    .controlSize(.regular)

            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                    .opacity(showCheckmark ? 1 : 0)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
            }
        }
        .animation(.spring(duration: 0.4), value: appState.recordingState)
    }

    // MARK: - Waveform Bars

    private var waveformBars: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barGradient)
                    .frame(width: 5, height: barHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.08),
                        value: appState.frequencyBands
                    )
            }
        }
        .frame(height: 36)
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = index < appState.frequencyBands.count
            ? CGFloat(appState.frequencyBands[index])
            : 0.1
        return max(4, level * 36)
    }

    // MARK: - Timer

    private var timerLabel: some View {
        Text(formatDuration(appState.recordingDuration))
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Streaming Text

    private var streamingTextView: some View {
        ScrollView {
            Text(appState.streamingText.isEmpty ? "Processing…" : appState.streamingText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(5)
        }
        .frame(maxHeight: 80)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Connecting Dots

    private var connectingDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: pulseScale
                    )
            }
        }
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        Text(statusText)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var statusText: String {
        switch appState.recordingState {
        case .idle: return ""
        case .connecting: return "Connecting…"
        case .recording: return "Press ⌥D to stop"
        case .processing: return "Transcribing…"
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Ring rotation
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
        // Pulse
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
        }
    }
}
