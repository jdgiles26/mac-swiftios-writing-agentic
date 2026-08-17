import Foundation

/// Runs GGUF models fully on-device by launching `llama.cpp`'s `llama-server`
/// binary as a child process and talking to its OpenAI-compatible HTTP API —
/// the same real streaming client used by `CloudEngine`/`LocalServerEngine`.
///
/// This is a genuine local inference backend, not a stub: it requires the
/// user to have `llama.cpp` built (or installed via Homebrew as
/// `llama.cpp`), which provides the `llama-server` executable. See the
/// README's "Native GGUF Engine" section for setup.
///
/// A subprocess boundary was chosen over linking llama.cpp's C API directly
/// so this engine only depends on stable, well-documented Foundation APIs
/// (`Process`, `URLSession`) rather than a C ABI that shifts between
/// llama.cpp releases. Inference still runs 100% locally and is
/// hardware-accelerated via llama.cpp's own Metal backend on Apple Silicon.
final class NativeGGUFEngine: AIAgentEngine {
    let provider = AIProvider.nativeGGUF

    private let serverBinaryPath: String
    private let host = "127.0.0.1"
    private let port: Int
    private let gpuLayers: Int

    private var serverProcess: Process?
    private var modelPath: URL?

    init(serverBinaryPath: String, port: Int = 8734, gpuLayers: Int = 99) {
        self.serverBinaryPath = serverBinaryPath
        self.port = port
        self.gpuLayers = gpuLayers
    }

    deinit {
        serverProcess?.terminate()
    }

    func loadModel(path: URL?) async throws {
        guard let path, FileManager.default.fileExists(atPath: path.path) else {
            throw CodeAgentError.invalidGGUFPath(path?.path ?? "<none>")
        }
        guard FileManager.default.isExecutableFile(atPath: serverBinaryPath) else {
            throw CodeAgentError.missingLlamaServerBinary(serverBinaryPath)
        }

        stopServer()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverBinaryPath)
        process.arguments = [
            "--model", path.path,
            "--host", host,
            "--port", String(port),
            "-ngl", String(gpuLayers)
        ]
        // Discard the child's console output; failures surface through the
        // health check / HTTP layer instead of log scraping.
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        serverProcess = process
        modelPath = path

        do {
            try await waitUntilHealthy(process: process, timeout: 60)
        } catch {
            stopServer()
            throw error
        }
    }

    func generateResponse(prompt: String, context: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let serverProcess, serverProcess.isRunning else {
            throw CodeAgentError.noModelLoaded
        }

        guard let url = URL(string: "http://\(host):\(port)/v1/chat/completions") else {
            throw CodeAgentError.invalidServerURL("http://\(host):\(port)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try chatCompletionBody(model: "local-gguf", prompt: prompt, context: context)

        return streamChatCompletion(request: request)
    }

    private func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
    }

    private func waitUntilHealthy(process: Process, timeout: TimeInterval) async throws {
        guard let healthURL = URL(string: "http://\(host):\(port)/health") else {
            throw CodeAgentError.invalidServerURL("http://\(host):\(port)")
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !process.isRunning {
                throw CodeAgentError.llamaServerExited(terminationStatus: process.terminationStatus)
            }

            if let (_, response) = try? await URLSession.shared.data(from: healthURL),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return
            }

            try await Task.sleep(nanoseconds: 300_000_000)
        }

        throw CodeAgentError.llamaServerTimedOut
    }
}
