# WhisperType

WhisperType is a blazing fast, native macOS bilingual dictation utility powered by the OpenAI Realtime API and Whisper API. It provides a ChatGPT-style global floating overlay for seamless voice-to-text input across all your macOS applications.

## Features

- **Global Hotkey Activation**: Press `⌥D` (Option + D) from anywhere in macOS to start dictating.
- **Two Transcription Engines**:
  - **Realtime API (Streaming)**: Powered by `gpt-4o-mini-realtime-preview`. Watch words appear word-by-word on a beautiful floating waveform window as you speak. Extremely low latency.
  - **Whisper REST API (Batch)**: Powered by `whisper-1`. The classic, highly accurate, strict verbatim transcription model.
- **Native macOS UI**: Built entirely with SwiftUI and AppKit. Uses a pure background architecture (`LSUIElement`) to prevent stealing keyboard focus from your active apps.
- **Bilingual & Code-Mixing Friendly**: Intelligently handles mixed Chinese/English speech and preserves technical jargon (e.g., Xcode, LLM, SwiftUI) without unwanted translations.
- **Auto-Paste**: Automatically types the transcribed text directly into your active text field using native macOS Accessibility (`CGEvent`) simulation.

## Installation & Setup

1. **Clone the repository** and open the project directory.
2. **Generate the Xcode Project**:
   We use `xcodegen` to manage the `.xcodeproj`.
   ```bash
   brew install xcodegen
   xcodegen generate
   ```
3. **Open in Xcode**:
   ```bash
   open WhisperType.xcodeproj
   ```
4. **Build and Run** (`⌘R`).

### Permissions Required
On first launch, WhisperType will request **Accessibility** permissions. This is strictly required to simulate the `Cmd+V` keystroke that automatically inserts your text into the active window.
1. Click "Open System Settings" when prompted.
2. Toggle the switch next to "WhisperType" to ON.

## Usage

1. **Enter your API Key**:
   - Press `Option + S` (⌥S) or click the microphone icon in the macOS menu bar to open Settings.
   - Enter your OpenAI API Key. It is stored securely in your macOS Keychain.
2. **Start Dictating**:
   - Click any text field in any app (Notes, Chrome, WeChat, etc.).
   - Press **`Option + D`** to start speaking. A floating waveform window will appear.
   - Press **`Option + D`** again to finish.
   - The text will be magically typed into your active window!

## Architecture Highlights

- **Anti-Hallucination Prompts**: When using the Realtime API, GPT-4o naturally acts as an assistant. We use strict `[TRANSCRIPT_START]` marker prefixes and rigorous system prompts to force it into a "verbatim dictation only" mode.
- **LSUIElement Background Mode**: To simulate pasting into *other* apps, WhisperType runs without a Dock icon or main window, ensuring it never steals the key window focus.
- **Direct AppKit Key Events**: Bypasses unreliable AppleScript and uses raw `CGEvent` to post keyboard inputs synchronously.

## Requirements
- macOS 14.0 or later.
- An active OpenAI API key with access to the Realtime API and Whisper API.

## License
MIT License
