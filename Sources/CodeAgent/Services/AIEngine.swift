import Foundation

protocol AIAgentEngine {
    var provider: AIProvider { get }
    func generateResponse(prompt: String, context: String) async throws -> AsyncThrowingStream<String, Error>
    func loadModel(path: URL?) async throws
}

enum AIProvider: String, Codable, CaseIterable {
    case openAI = "OpenAI Cloud"
    case ollama = "Ollama Local"
    case lmStudio = "LM Studio Local"
    case nativeGGUF = "Native GGUF/MLX"
}

/// Streams Server-Sent-Events chat-completion responses shaped like the
/// OpenAI-compatible `/v1/chat/completions` endpoint. Shared by every
/// HTTP-backed engine (cloud, local server, and the local llama-server
/// process behind `NativeGGUFEngine`) so each engine only needs to build its
/// own request.
func streamChatCompletion(request: URLRequest) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw CodeAgentError.requestFailed(statusCode: http.statusCode)
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String else { continue }

                    continuation.yield(content)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

func chatCompletionBody(model: String, prompt: String, context: String) throws -> Data {
    let body: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "system", "content": "You are a senior software engineer. Analyze the code, plan improvements, and stream the refactored output."],
            ["role": "user", "content": "Context:\n\(context)\n\nPrompt:\n\(prompt)"]
        ],
        "stream": true
    ]
    return try JSONSerialization.data(withJSONObject: body)
}

final class CloudEngine: AIAgentEngine {
    let provider = AIProvider.openAI
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) { self.apiKey = apiKey }

    func generateResponse(prompt: String, context: String) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            throw CodeAgentError.missingAPIKey(provider: provider)
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try chatCompletionBody(model: "gpt-4o", prompt: prompt, context: context)

        return streamChatCompletion(request: request)
    }

    func loadModel(path: URL?) async throws { /* N/A: cloud engine has no local model */ }
}

final class LocalServerEngine: AIAgentEngine {
    let provider: AIProvider
    private let baseURL: String

    init(provider: AIProvider, baseURL: String) {
        self.provider = provider
        self.baseURL = baseURL
    }

    func generateResponse(prompt: String, context: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw CodeAgentError.invalidServerURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try chatCompletionBody(
            model: provider == .ollama ? "llama3" : "local-model",
            prompt: prompt,
            context: context
        )

        return streamChatCompletion(request: request)
    }

    func loadModel(path: URL?) async throws { /* N/A: server manages its own model */ }
}
