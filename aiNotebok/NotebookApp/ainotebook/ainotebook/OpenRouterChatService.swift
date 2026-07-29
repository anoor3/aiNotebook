import Foundation

// MARK: - OpenAI Chat Service (Plain Text)

enum OpenAIChatService {
    // MARK: Configuration
    struct Configuration {
        static let model: String = "gpt-4o-mini"
        private static let userDefaultsKey = "com.ainotebook.openai-api-key"

        /// Read the key from multiple sources (env, Info.plist, bundled file, UserDefaults).
        /// When found from any source, persists it to UserDefaults so it survives app restarts
        /// outside Xcode.
        static var apiKey: String? {
            // Back-compat: older builds used OPENROUTER_API_KEY.
            let env = ProcessInfo.processInfo.environment
            let envKey = env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let envKey, isValidKey(envKey) {
                persistKey(envKey)
                return envKey
            }

            let legacyEnvKey = env["OPENROUTER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let legacyEnvKey, isValidKey(legacyEnvKey) {
                persistKey(legacyEnvKey)
                return legacyEnvKey
            }

            let plistKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String
            let trimmedPlistKey = plistKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedPlistKey, isValidKey(trimmedPlistKey) {
                persistKey(trimmedPlistKey)
                return trimmedPlistKey
            }

            let legacyPlistKey = Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String
            let trimmedLegacyPlistKey = legacyPlistKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedLegacyPlistKey, isValidKey(trimmedLegacyPlistKey) {
                persistKey(trimmedLegacyPlistKey)
                return trimmedLegacyPlistKey
            }

            let bundledKey = bundledEnvValue(named: "OPENAI_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let bundledKey, isValidKey(bundledKey) {
                persistKey(bundledKey)
                return bundledKey
            }

            let legacyBundledKey = bundledEnvValue(named: "OPENROUTER_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let legacyBundledKey, isValidKey(legacyBundledKey) {
                persistKey(legacyBundledKey)
                return legacyBundledKey
            }

            // Fallback: read from UserDefaults (persisted from a previous session)
            let savedKey = UserDefaults.standard.string(forKey: userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let savedKey, isValidKey(savedKey) { return savedKey }

            return nil
        }

        /// Check if a key looks like a real API key (not a placeholder).
        private static func isValidKey(_ key: String) -> Bool {
            guard !key.isEmpty else { return false }
            let lower = key.lowercased()
            if lower.contains("your_key") || lower.contains("your_api") || lower == "placeholder" { return false }
            // OpenAI keys start with sk-
            return key.hasPrefix("sk-")
        }

        /// Persist the key to UserDefaults so standalone launches (outside Xcode) can read it.
        private static func persistKey(_ key: String) {
            UserDefaults.standard.set(key, forKey: userDefaultsKey)
        }

        /// Optionally load a key from a bundled env file.
        ///
        /// If you create `openai.env` locally (for example in `env/openai.env`) and add it
        /// to the Xcode target's "Copy Bundle Resources", it will be available here without
        /// hardcoding secrets into source.
        private static func bundledEnvValue(named key: String) -> String? {
            guard let url = Bundle.main.url(forResource: "openai", withExtension: "env"),
                  let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }

            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let equalsIndex = line.firstIndex(of: "=") else { continue }

                let name = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name != key { continue }

                let valueStart = line.index(after: equalsIndex)
                return String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return nil
        }
    }

    // MARK: Request Models
    struct ChatRequestMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatRequestMessage]
        let stream: Bool?
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

        guard let apiKey = Configuration.apiKey else {
            throw NSError(
                domain: "OpenAIChatService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is missing. Set OPENAI_API_KEY (or legacy OPENROUTER_API_KEY) in your Xcode Scheme (Run > Arguments > Environment), or create env/.env at the repo root (it will be copied into the app bundle as openai.env during build)."]
            )
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemMessage = ChatRequestMessage(
            role: "system",
            content: "Reply in plain text. Avoid markdown formatting unless the user explicitly asks for it."
        )

        let userMessages = messages.map {
            ChatRequestMessage(
                role: $0.role == .user ? "user" : "assistant",
                content: $0.text
            )
        }

        let payload = ChatRequest(
            model: Configuration.model,
            messages: [systemMessage] + userMessages,
            stream: nil
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {

            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenAIChatService",
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

// Backwards compatibility: older code referenced this name.
typealias OpenRouterChatService = OpenAIChatService
