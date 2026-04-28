import AppKit
import ApplicationServices
import CoreGraphics

/// Inserts transcribed text into the active application by
/// setting the pasteboard and simulating ⌘V.
class TextInserter {

    /// Insert text into the captured target app, or the current app if no target was captured.
    /// Returns true if paste was attempted, false if accessibility is not granted.
    @discardableResult
    func insertText(_ text: String, targetProcessID: pid_t?) -> Bool {
        let pasteboard = NSPasteboard.general

        // Always set the clipboard first — even if paste simulation fails,
        // the user can manually ⌘V.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("WhisperType TextInserter: Set clipboard with \(text.count) chars")

        guard AXIsProcessTrusted() else {
            print("WhisperType TextInserter: Not trusted for accessibility")
            return false
        }

        // Small delay to ensure pasteboard is ready, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.simulatePaste(targetProcessID: targetProcessID)
        }

        return true
    }

    // MARK: - Private

    private func simulatePaste(targetProcessID: pid_t?) {
        // Determine which process to send the paste to
        let pid: pid_t
        if let targetPID = targetProcessID {
            // Verify target process is still running
            if NSRunningApplication(processIdentifier: targetPID) != nil {
                pid = targetPID
                print("WhisperType TextInserter: Pasting to target pid=\(pid)")
            } else if let frontApp = NSWorkspace.shared.frontmostApplication {
                pid = frontApp.processIdentifier
                print("WhisperType TextInserter: Target gone, pasting to frontmost pid=\(pid)")
            } else {
                print("WhisperType TextInserter: No target app found")
                return
            }
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            pid = frontApp.processIdentifier
            print("WhisperType TextInserter: No target saved, pasting to frontmost pid=\(pid)")
        } else {
            print("WhisperType TextInserter: No app to paste to")
            return
        }
        
        // Don't paste to ourselves
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard pid != myPID else {
            print("WhisperType TextInserter: Refusing to paste to self")
            return
        }
        
        // Create ⌘V key down event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = V key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("WhisperType TextInserter: Failed to create CGEvent")
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post directly to the app that had focus when recording started.
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        print("WhisperType TextInserter: Sent ⌘V to pid=\(pid)")
    }
}
