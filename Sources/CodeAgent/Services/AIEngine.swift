import Foundation

#if os(macOS)
import Accelerate
#endif

@MainActor
protocol AIAgentEngine {
    var provider: AIProvider { get }
    func generateResponse(prompt: String, context: String) async throws -> AsyncStream<String>
    func loadModel(path: URL?) async throws
}

enum AIProvider: String, Codable {
    case openAI = "OpenAI Cloud"
    case ollama = "Ollama Local"
    case lmStudio = "LM Studio Local"
    case nativeGGUF = "Native GGUF/MLX"
}

final class CloudEngine: AIAgentEngine {
    let provider = AIProvider.openAI
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) { self.apiKey = apiKey }
    
    func generateResponse(prompt: String, context: String) async throws -> AsyncStream<String> {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a senior software engineer. Analyze the code, plan improvements, and stream the refactored output."],
                ["role": "user", "content": "Context:\n\(context)\n\nPrompt:\n\(prompt)"]
            ],
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return AsyncStream { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    continuation.finish(throwing: error ?? NSError(domain: "Network", code: -1))
                    return
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                for line in String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? [] {
                    guard line.hasPrefix("data: "), !line.contains("[DONE]") else { continue }
                    let jsonStr = String(line.dropFirst(5))
                    guard let json = try? JSONSerialization.jsonObject(with: jsonStr.data(using: .utf8)!) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let delta = first["delta"] as? [String: Any],
                          let content = delta["content"] as? String else { continue }
                    continuation.yield(content)
                }
                continuation.finish()
            }
            task.resume()
        }
    }
    
    func loadModel(path: URL?) async throws { /* N/A */ }
}

final class LocalServerEngine: AIAgentEngine {
    let provider: AIProvider
    private let baseURL: String
    
    init(provider: AIProvider, baseURL: String) {
        self.provider = provider
        self.baseURL = baseURL
    }
    
    func generateResponse(prompt: String, context: String) async throws -> AsyncStream<String> {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": provider == .ollama ? "llama3" : "local-model",
            "messages": [
                ["role": "system", "content": "You are a senior software engineer. Analyze the code, plan improvements, and stream the refactored output."],
                ["role": "user", "content": "Context:\n\(context)\n\nPrompt:\n\(prompt)"]
            ],
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return AsyncStream { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data else { continuation.finish(); return }
                for line in String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? [] {
                    guard line.hasPrefix("data: "), !line.contains("[DONE]") else { continue }
                    let jsonStr = String(line.dropFirst(5))
                    guard let json = try? JSONSerialization.jsonObject(with: jsonStr.data(using: .utf8)!) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let delta = first["delta"] as? [String: Any],
                          let content = delta["content"] as? String else { continue }
                    continuation.yield(content)
                }
                continuation.finish()
            }
            task.resume()
        }
    }
    
    func loadModel(path: URL?) async throws { /* N/A */ }
}

final class NativeGGUFEngine: AIAgentEngine {
    let provider = AIProvider.nativeGGUF
    private var modelPath: URL?
    
    func generateResponse(prompt: String, context: String) async throws -> AsyncStream<String> {
        guard let path = modelPath else { throw NSError(domain: "GGUF", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model loaded"]) }
        
        // FFI Bridge to llama.cpp / mlx-swift
        return AsyncStream { continuation in
            let input = "\(context)\n\(prompt)"
            let cString = (input as NSString).utf8String
            let resultPtr = UnsafeMutablePointer<Int8>.allocate(capacity: 1024)
            
            // Bridge call to native inference engine
            #if os(macOS)
            let tokenCount = llama_bridge_generate(cString, resultPtr, 1024)
            #else
            let tokenCount = 0
            #endif
            
            if tokenCount > 0 {
                let output = String(cString: resultPtr)
                for token in output.components(separatedBy: " ") {
                    continuation.yield(token)
                }
            }
            resultPtr.deallocate()
            continuation.finish()
        }
    }
    
    func loadModel(path: URL?) async throws {
        guard let path = path, FileManager.default.fileExists(atPath: path.path) else {
            throw NSError(domain: "GGUF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid GGUF path"])
        }
        self.modelPath = path
    }
}

// FFI Declaration
@_silgen_name("llama_bridge_generate")
func llama_bridge_generate(_ input: UnsafePointer<Int8>, _ output: UnsafeMutablePointer<Int8>, _ capacity: Int32) -> Int32