import Foundation
import KeychainAccess

/// Manages API keys and provides OpenAI Whisper REST API transcription.
class TranscriptionService {
    private let keychain = Keychain(service: "com.whispertype.app")
    private let session = URLSession.shared

    // MARK: - API Key Management

    var openAIAPIKey: String? {
        get { try? keychain.get("openai_api_key") }
        set {
            if let newValue {
                try? keychain.set(newValue, key: "openai_api_key")
            } else {
                try? keychain.remove("openai_api_key")
            }
        }
    }

    // MARK: - Whisper REST API (fallback)

    /// Batch transcribe using OpenAI Whisper REST API.
    /// Only used when backend is set to `.whisperREST`.
    func transcribeWithWhisperAPI(audioData: Data, language: String?) async throws -> String {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // File field
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav",
                            mimeType: "audio/wav", data: audioData)

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")

        // Language hint (optional)
        if let language, !language.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(httpResponse.statusCode, errorText)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.decodingError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case networkError(String)
    case apiError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Please set your API key in Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .decodingError:
            return "Failed to decode transcription response"
        }
    }
}

// MARK: - Data Multipart Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
