import AppKit
import SwiftUI

/// Manages a floating NSPanel overlay window that shows during recording.
/// Uses NSPanel with .nonactivatingPanel style so it never steals focus.
@MainActor
class OverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    /// Show the overlay with the given SwiftUI content.
    func show<Content: View>(content: Content) {
        if panel != nil {
            // Already showing, just update content
            hostingView?.rootView = AnyView(content)
            return
        }

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 160)
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // Position at bottom-center of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Update the overlay content without re-creating the window.
    func update<Content: View>(content: Content) {
        hostingView?.rootView = AnyView(content)
    }

    /// Hide and destroy the overlay window.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
