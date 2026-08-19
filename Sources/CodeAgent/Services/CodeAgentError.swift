import Foundation

/// Typed, user-facing errors for the engine/pipeline layer, replacing ad-hoc
/// `NSError(domain:code:userInfo:)` construction scattered across the
/// codebase with a single place to read and extend error messages.
enum CodeAgentError: LocalizedError, Equatable {
    case missingAPIKey(provider: AIProvider)
    case invalidServerURL(String)
    case requestFailed(statusCode: Int)
    case invalidGGUFPath(String)
    case missingLlamaServerBinary(String)
    case llamaServerTimedOut
    case llamaServerExited(terminationStatus: Int32)
    case noModelLoaded
    case noEngineConfigured

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider.rawValue)."
        case .invalidServerURL(let url):
            return "Invalid server URL: \(url)"
        case .requestFailed(let statusCode):
            return "Request failed with status \(statusCode)."
        case .invalidGGUFPath(let path):
            return "No GGUF model file found at \(path)."
        case .missingLlamaServerBinary(let path):
            return "No llama-server executable found at \(path). Install llama.cpp and set its path in Settings."
        case .llamaServerTimedOut:
            return "Timed out waiting for the local GGUF server to become ready."
        case .llamaServerExited(let status):
            return "The local GGUF server process exited unexpectedly (status \(status))."
        case .noModelLoaded:
            return "No GGUF model is loaded."
        case .noEngineConfigured:
            return "No text selected or engine configured."
        }
    }
}
