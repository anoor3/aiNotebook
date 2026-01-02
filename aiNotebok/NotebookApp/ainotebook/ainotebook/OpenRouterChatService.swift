import Foundation

// MARK: - OpenRouter Chat Service (Plain Text Only)

enum OpenRouterChatService {

    // MARK: Configuration
    struct Configuration {
        // ⚠️ Move this to Keychain or environment later
        static let apiKey: String = "suck-my-fat-one-DEREK!!!"
    }

    
    // MARK: Request Models
    struct ChatRequestMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatRequestMessage]
        let stream: Bool
    }

    // MARK: Response Models
    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    // MARK: Public API
    static func send(messages: [AIChatMessage]) async throws -> String {

        guard !Configuration.apiKey.isEmpty else {
            throw NSError(
                domain: "OpenRouterChatService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenRouter API key is missing."]
            )
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(Configuration.apiKey)", forHTTPHeaderField: "Authorization")

        // 🔥 SYSTEM MESSAGE TO KILL MARKDOWN COMPLETELY
        let systemMessage = ChatRequestMessage(
            role: "system",
            content: """
Reply in plain text only.
No markdown.
No formatting.
No symbols.
No dashes.
No long explanations.
Use short simple sentences.
Answer directly.
"""
        )

        let userMessages = messages.map {
            ChatRequestMessage(
                role: $0.role == .user ? "user" : "assistant",
                content: $0.text
            )
        }

        let payload = ChatRequest(
            model: "mistralai/devstral-2512:free",
            messages: [systemMessage] + userMessages,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {

            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenRouterChatService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: errorBody]
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)

        let reply = decoded.choices
            .compactMap { $0.message.content }
            .joined()

        return reply.isEmpty ? "No response." : reply
    }
}
