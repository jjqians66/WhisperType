import AppKit
import HotKey
import Carbon

/// Manages the global keyboard shortcut for toggling dictation.
/// Default: Option + D (⌥D)
class HotKeyManager {
    private var hotKey: HotKey?
    private var settingsHotKey: HotKey?
    private var isRecordHotKeyDown = false
    private var isSettingsHotKeyDown = false

    /// Called once when the record hotkey is released.
    var onToggle: (() -> Void)?
    
    /// Called once when the settings hotkey is released.
    var onSettings: (() -> Void)?

    init() {
        setupDefaultHotKey()
    }

    /// Register the default global hotkeys
    func setupDefaultHotKey() {
        // Record HotKey: ⌥D
        hotKey = HotKey(key: .d, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.isRecordHotKeyDown = true
        }
        hotKey?.keyUpHandler = { [weak self] in
            guard let self, self.isRecordHotKeyDown else { return }
            self.isRecordHotKeyDown = false
            self.onToggle?()
        }
        
        // Settings HotKey: ⌥S
        settingsHotKey = HotKey(key: .s, modifiers: [.option])
        settingsHotKey?.keyDownHandler = { [weak self] in
            self?.isSettingsHotKeyDown = true
        }
        settingsHotKey?.keyUpHandler = { [weak self] in
            guard let self, self.isSettingsHotKeyDown else { return }
            self.isSettingsHotKeyDown = false
            self.onSettings?()
        }
    }

    /// Update the hotkey combination
    func updateHotKey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey = nil
        isRecordHotKeyDown = false
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.isRecordHotKeyDown = true
        }
        hotKey?.keyUpHandler = { [weak self] in
            guard let self, self.isRecordHotKeyDown else { return }
            self.isRecordHotKeyDown = false
            self.onToggle?()
        }
    }

    deinit {
        hotKey = nil
    }
}
