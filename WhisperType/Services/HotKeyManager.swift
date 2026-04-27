import AppKit
import HotKey
import Carbon

/// Manages the global keyboard shortcut for toggling dictation.
/// Default: Option + D (⌥D)
class HotKeyManager {
    private var hotKey: HotKey?
    private var settingsHotKey: HotKey?

    /// Called when the record hotkey is pressed
    var onToggle: (() -> Void)?
    
    /// Called when the settings hotkey is pressed
    var onSettings: (() -> Void)?

    init() {
        setupDefaultHotKey()
    }

    /// Register the default global hotkeys
    func setupDefaultHotKey() {
        // Record HotKey: ⌥D
        hotKey = HotKey(key: .d, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }
        
        // Settings HotKey: ⌥S
        settingsHotKey = HotKey(key: .s, modifiers: [.option])
        settingsHotKey?.keyDownHandler = { [weak self] in
            self?.onSettings?()
        }
    }

    /// Update the hotkey combination
    func updateHotKey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey = nil
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }
    }

    deinit {
        hotKey = nil
    }
}
