import Foundation

/// The raw values a user can set in `SettingsView`, decoupled from
/// `@AppStorage`/SwiftUI so engine construction can be unit tested without a
/// view.
struct EngineSettings {
    var apiKey: String
    var ollamaURL: String
    var lmStudioURL: String
    var ggufPath: String
    var llamaServerPath: String
    var llamaServerPort: Int
}

/// Builds an `AIAgentEngine` for a chosen provider from raw settings,
/// validating required fields instead of silently falling back to a
/// different provider when configuration is incomplete.
enum EngineFactory {
    static func makeEngine(for provider: AIProvider, settings: EngineSettings) throws -> AIAgentEngine {
        switch provider {
        case .openAI:
            guard !settings.apiKey.isEmpty else {
                throw CodeAgentError.missingAPIKey(provider: .openAI)
            }
            return CloudEngine(apiKey: settings.apiKey)

        case .ollama:
            try validate(url: settings.ollamaURL)
            return LocalServerEngine(provider: .ollama, baseURL: settings.ollamaURL)

        case .lmStudio:
            try validate(url: settings.lmStudioURL)
            return LocalServerEngine(provider: .lmStudio, baseURL: settings.lmStudioURL)

        case .nativeGGUF:
            guard !settings.ggufPath.isEmpty else {
                throw CodeAgentError.invalidGGUFPath(settings.ggufPath)
            }
            guard !settings.llamaServerPath.isEmpty else {
                throw CodeAgentError.missingLlamaServerBinary(settings.llamaServerPath)
            }
            return NativeGGUFEngine(serverBinaryPath: settings.llamaServerPath, port: settings.llamaServerPort)
        }
    }

    private static func validate(url: String) throws {
        guard !url.isEmpty, let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
            throw CodeAgentError.invalidServerURL(url)
        }
    }
}
