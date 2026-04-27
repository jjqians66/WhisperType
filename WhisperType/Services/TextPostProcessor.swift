import Foundation
import os

/// Optional LLM post-processing for transcribed text.
/// Uses GPT-4o-mini for lightweight readability enhancement.
class TextPostProcessor {
    private let logger = Logger(subsystem: "com.whispertype.app", category: "TextPostProcessor")

    /// Enhance text readability using GPT-4o-mini.
    /// Cost: ~$0.001 per call.
    func enhance(_ text: String, apiKey: String) async throws -> String {
        let prompt = "\(Prompts.readabilityEnhance)\n\n\(text)"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Post-processing failed: \(errorText)")
            throw PostProcessError.apiFailed(errorText)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessError.decodingFailed
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Post-processing complete: \(text.count) → \(result.count) chars")
        return result
    }
}

enum PostProcessError: LocalizedError {
    case apiFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .apiFailed(let msg): return "Post-processing failed: \(msg)"
        case .decodingFailed: return "Failed to decode post-processing response"
        }
    }
}
