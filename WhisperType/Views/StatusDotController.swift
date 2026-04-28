import AppKit
import SwiftUI

/// A tiny persistent floating status dot anchored to the bottom-right of the screen.
/// Always visible so the user knows at a glance whether WhisperType is running.
///
/// Colors:
/// - 🟢 Green = idle, ready
/// - 🔴 Red (pulsing) = recording
/// - 🟡 Yellow = processing/transcribing
/// - 🔵 Blue = connecting
@MainActor
class StatusDotController: ObservableObject {
    static let shared = StatusDotController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<StatusDotView>?

    @Published var state: DotState = .idle

    enum DotState {
        case idle
        case connecting
        case recording
        case processing
    }

    func show() {
        guard panel == nil else { return }

        let dotView = StatusDotView(controller: self)
        let hosting = NSHostingView(rootView: dotView)
        hosting.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 44, height: 44),
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
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        // Anchor to bottom-right corner of the screen
        positionPanel(panel)

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func updateState(_ newState: DotState) {
        state = newState
    }

    private func positionPanel(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 56  // 44 dot + 12 margin
            let y = screenFrame.minY + 12  // 12 from bottom
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - Status Dot View

struct StatusDotView: View {
    @ObservedObject var controller: StatusDotController
    @State private var isPulsing = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Pulse ring (recording only)
            if controller.state == .recording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            // Main dot
            Circle()
                .fill(dotColor.gradient)
                .frame(width: 14, height: 14)
                .shadow(color: dotColor.opacity(0.5), radius: 4)

            // Hover tooltip area
            if isHovering {
                Text(tooltipText)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -80, y: 0)
                    .transition(.opacity)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            isPulsing = true
        }
        .onChange(of: controller.state) { _, newState in
            isPulsing = (newState == .recording)
        }
    }

    private var dotColor: Color {
        switch controller.state {
        case .idle: return .green
        case .connecting: return .blue
        case .recording: return .red
        case .processing: return .yellow
        }
    }

    private var tooltipText: String {
        switch controller.state {
        case .idle: return "Ready ⌥D"
        case .connecting: return "Setting up…"
        case .recording: return "Recording…"
        case .processing: return "Transcribing…"
        }
    }
}
