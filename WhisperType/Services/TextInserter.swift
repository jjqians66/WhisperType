import AppKit
import CoreGraphics

/// Inserts transcribed text into the active application by
/// setting the pasteboard and simulating ⌘V.
class TextInserter {

    /// Insert text into the currently focused text field
    func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Simulate ⌘V paste
            self.simulatePaste()
        }
    }

    // MARK: - Private

    private func simulatePaste() {
        // Create ⌘V key down event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = V key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
