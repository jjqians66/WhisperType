import Foundation
import os

/// WebSocket client for OpenAI's Realtime API.
/// Handles streaming audio input and receiving text transcription deltas.
@MainActor
class RealtimeClient: ObservableObject {

    // MARK: - Types

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var streamingText: String = ""

    // MARK: - Callbacks

    var onTextDelta: ((String) -> Void)?
    var onResponseDone: ((String) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private let logger = Logger(subsystem: "com.whispertype.app", category: "RealtimeClient")
    private var receiveTask: Task<Void, Never>?

    // MARK: - Connect

    /// Open a WebSocket to OpenAI Realtime API and configure the session.
    func connect(apiKey: String, model: String = "gpt-4o-mini-realtime-preview") async throws {
        guard connectionState != .connecting, connectionState != .connected else { return }
        connectionState = .connecting
        streamingText = ""

        let urlString = "wss://api.openai.com/v1/realtime?model=\(model)"
        guard let url = URL(string: urlString) else {
            throw RealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Wait for session.created
        let firstMessage = try await receiveOneMessage()
        guard let type = firstMessage["type"] as? String, type == "session.created" else {
            throw RealtimeError.unexpectedMessage("Expected session.created, got: \(firstMessage)")
        }
        logger.info("Session created")

        // Configure session: manual commit, text-only output, paraphrase instructions
        try await configureSession()

        connectionState = .connected

        // Start background receive loop
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - Session Configuration

    private func configureSession() async throws {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "instructions": Prompts.paraphrase,
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-transcribe"
                ],
                "turn_detection": NSNull()
            ] as [String: Any]
        ]
        try await sendJSON(config)
        logger.info("Session configured: text-only output, manual commit, paraphrase instructions")
    }

    // MARK: - Audio Streaming

    /// Send a chunk of PCM16 24kHz audio data to OpenAI.
    func sendAudio(_ pcmData: Data) async throws {
        guard connectionState == .connected else { return }
        let base64 = pcmData.base64EncodedString()
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        try await sendJSON(event)
    }

    // MARK: - Commit & Respond

    /// Commit the audio buffer and trigger a response.
    func commitAndRespond() async throws {
        guard connectionState == .connected else { return }

        // Commit audio buffer
        try await sendJSON(["type": "input_audio_buffer.commit"])
        logger.info("Audio committed")

        // Trigger response
        let responseEvent: [String: Any] = [
            "type": "response.create",
            "response": [
                "modalities": ["text"],
                "instructions": Prompts.paraphrase
            ] as [String: Any]
        ]
        try await sendJSON(responseEvent)
        logger.info("Response requested")
    }

    // MARK: - Disconnect

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        logger.info("Disconnected")
    }

    // MARK: - Private: Send

    private func sendJSON(_ dict: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeError.encodingError
        }
        try await webSocketTask?.send(.string(text))
    }

    // MARK: - Private: Receive

    private func receiveOneMessage() async throws -> [String: Any] {
        guard let task = webSocketTask else { throw RealtimeError.notConnected }
        let message = try await task.receive()
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RealtimeError.decodingError
            }
            return json
        case .data(let data):
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RealtimeError.decodingError
            }
            return json
        @unknown default:
            throw RealtimeError.unexpectedMessage("Unknown message format")
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    guard let data = text.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    await handleEvent(json)
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await handleEvent(json)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("Receive error: \(error.localizedDescription)")
                    connectionState = .error(error.localizedDescription)
                    onError?(error.localizedDescription)
                }
                break
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ json: [String: Any]) async {
        guard let type = json["type"] as? String else { return }

        switch type {
        case "response.text.delta", "response.output_text.delta":
            if let delta = json["delta"] as? String {
                streamingText += delta
                onTextDelta?(delta)
            }

        case "response.done":
            let finalText = streamingText
            logger.info("Response done, text length: \(finalText.count)")
            onResponseDone?(finalText)

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            logger.error("OpenAI error: \(errorMsg)")
            connectionState = .error(errorMsg)
            onError?(errorMsg)

        case "session.updated", "input_audio_buffer.committed",
             "input_audio_buffer.cleared", "input_audio_buffer.speech_started",
             "input_audio_buffer.speech_stopped", "rate_limits.updated",
             "response.created", "response.output_item.added",
             "response.output_item.done", "response.content_part.added",
             "response.content_part.done", "response.text.done",
             "conversation.item.created", "conversation.item.added",
             "conversation.item.input_audio_transcription.completed":
            logger.debug("Event: \(type)")

        default:
            logger.debug("Unhandled event: \(type)")
        }
    }
}

// MARK: - Errors

enum RealtimeError: LocalizedError {
    case invalidURL
    case notConnected
    case encodingError
    case decodingError
    case unexpectedMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .notConnected: return "Not connected to OpenAI"
        case .encodingError: return "Failed to encode message"
        case .decodingError: return "Failed to decode message"
        case .unexpectedMessage(let msg): return "Unexpected: \(msg)"
        }
    }
}
