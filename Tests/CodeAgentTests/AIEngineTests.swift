import XCTest
import Foundation
@testable import CodeAgent

final class AgenticPipelineTests: XCTestCase {
    var mockEngine: MockAIAgentEngine!
    var pipeline: AgenticPipeline!

    override func setUp() {
        super.setUp()
        mockEngine = MockAIAgentEngine()
        pipeline = AgenticPipeline(engine: mockEngine, promptTemplate: "Test: {{step}}")
    }

    func testPipelineCallsEngineForEachStep() async throws {
        mockEngine.shouldYield = ["step1", "step2", "step3"]

        for try await _ in pipeline.execute(selectedCode: "func test() {}") {}

        // Verify engine was called 3 times (analyzing, planning, executing)
        XCTAssertEqual(mockEngine.callCount, 3)
    }

    func testPipelineReportsStepsInOrder() async throws {
        mockEngine.shouldYield = ["token"]
        var startedSteps: [PipelineStep] = []

        for try await event in pipeline.execute(selectedCode: "code") {
            if case .stepStarted(let step) = event {
                startedSteps.append(step)
            }
        }

        XCTAssertEqual(startedSteps, [.analyzing, .planning, .executing, .complete])
    }

    func testStreamingOutputAccumulates() async throws {
        mockEngine.shouldYield = ["Hello", " ", "World"]
        var output = ""

        for try await event in pipeline.execute(selectedCode: "code") {
            if case .token(let token) = event {
                output += token
            }
        }

        // The pipeline calls the engine once per step (analyzing, planning,
        // executing), so the mock's tokens are emitted three times in a row.
        XCTAssertEqual(output, "Hello WorldHello WorldHello World\n[Workflow Complete]")
    }

    func testPipelineAppendsCompletionMarker() async throws {
        mockEngine.shouldYield = ["token"]
        var tokens: [String] = []

        for try await event in pipeline.execute(selectedCode: "code") {
            if case .token(let token) = event {
                tokens.append(token)
            }
        }

        XCTAssertEqual(tokens.last, "\n[Workflow Complete]")
    }

    func testPipelinePropagatesEngineErrors() async throws {
        mockEngine.errorToThrow = CodeAgentError.missingAPIKey(provider: .openAI)

        do {
            for try await _ in pipeline.execute(selectedCode: "code") {}
            XCTFail("Expected the pipeline to rethrow the engine's error")
        } catch let error as CodeAgentError {
            XCTAssertEqual(error, .missingAPIKey(provider: .openAI))
        }
    }
}

final class NativeGGUFEngineTests: XCTestCase {
    func testLoadModelThrowsForMissingGGUFFile() async {
        let engine = NativeGGUFEngine(serverBinaryPath: "/usr/bin/true")

        do {
            try await engine.loadModel(path: URL(fileURLWithPath: "/nonexistent.gguf"))
            XCTFail("Expected loadModel to throw for a nonexistent GGUF path")
        } catch let error as CodeAgentError {
            guard case .invalidGGUFPath = error else {
                return XCTFail("Expected .invalidGGUFPath, got \(error)")
            }
        } catch {
            XCTFail("Expected CodeAgentError, got \(error)")
        }
    }

    func testLoadModelThrowsForMissingServerBinary() async throws {
        let engine = NativeGGUFEngine(serverBinaryPath: "/nonexistent/llama-server")
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try await engine.loadModel(path: tempFile)
            XCTFail("Expected loadModel to throw when the llama-server binary doesn't exist")
        } catch let error as CodeAgentError {
            guard case .missingLlamaServerBinary = error else {
                return XCTFail("Expected .missingLlamaServerBinary, got \(error)")
            }
        } catch {
            XCTFail("Expected CodeAgentError, got \(error)")
        }
    }

    func testGenerateResponseThrowsBeforeModelIsLoaded() async {
        let engine = NativeGGUFEngine(serverBinaryPath: "/usr/bin/true")

        do {
            _ = try await engine.generateResponse(prompt: "p", context: "c")
            XCTFail("Expected generateResponse to throw when no model/server is running")
        } catch let error as CodeAgentError {
            XCTAssertEqual(error, .noModelLoaded)
        } catch {
            XCTFail("Expected CodeAgentError, got \(error)")
        }
    }

    // Note: actually spawning llama-server and streaming real tokens requires
    // a real llama.cpp build and a GGUF model, which aren't available in CI.
    // That path is exercised manually per the README's "Native GGUF Engine"
    // setup instructions.
}

final class EngineFactoryTests: XCTestCase {
    private func settings(
        apiKey: String = "",
        ollamaURL: String = "",
        lmStudioURL: String = "",
        ggufPath: String = "",
        llamaServerPath: String = "",
        llamaServerPort: Int = 8734
    ) -> EngineSettings {
        EngineSettings(
            apiKey: apiKey,
            ollamaURL: ollamaURL,
            lmStudioURL: lmStudioURL,
            ggufPath: ggufPath,
            llamaServerPath: llamaServerPath,
            llamaServerPort: llamaServerPort
        )
    }

    func testOpenAIRequiresAPIKey() {
        XCTAssertThrowsError(try EngineFactory.makeEngine(for: .openAI, settings: settings())) { error in
            XCTAssertEqual(error as? CodeAgentError, .missingAPIKey(provider: .openAI))
        }
    }

    func testOpenAISucceedsWithAPIKey() throws {
        let engine = try EngineFactory.makeEngine(for: .openAI, settings: settings(apiKey: "sk-test"))
        XCTAssertEqual(engine.provider, .openAI)
        XCTAssertTrue(engine is CloudEngine)
    }

    func testOllamaRequiresValidURL() {
        XCTAssertThrowsError(try EngineFactory.makeEngine(for: .ollama, settings: settings(ollamaURL: "not a url"))) { error in
            XCTAssertEqual(error as? CodeAgentError, .invalidServerURL("not a url"))
        }
    }

    func testOllamaSucceedsWithValidURL() throws {
        let engine = try EngineFactory.makeEngine(for: .ollama, settings: settings(ollamaURL: "http://localhost:11434"))
        XCTAssertEqual(engine.provider, .ollama)
        XCTAssertTrue(engine is LocalServerEngine)
    }

    func testLMStudioSucceedsWithValidURL() throws {
        let engine = try EngineFactory.makeEngine(for: .lmStudio, settings: settings(lmStudioURL: "http://localhost:1234"))
        XCTAssertEqual(engine.provider, .lmStudio)
    }

    func testNativeGGUFRequiresModelPath() {
        XCTAssertThrowsError(try EngineFactory.makeEngine(for: .nativeGGUF, settings: settings(llamaServerPath: "/usr/bin/true"))) { error in
            XCTAssertEqual(error as? CodeAgentError, .invalidGGUFPath(""))
        }
    }

    func testNativeGGUFRequiresServerBinary() {
        XCTAssertThrowsError(try EngineFactory.makeEngine(for: .nativeGGUF, settings: settings(ggufPath: "/models/model.gguf"))) { error in
            XCTAssertEqual(error as? CodeAgentError, .missingLlamaServerBinary(""))
        }
    }

    func testNativeGGUFSucceedsWithBothPaths() throws {
        let engine = try EngineFactory.makeEngine(
            for: .nativeGGUF,
            settings: settings(ggufPath: "/models/model.gguf", llamaServerPath: "/usr/bin/true")
        )
        XCTAssertEqual(engine.provider, .nativeGGUF)
        XCTAssertTrue(engine is NativeGGUFEngine)
    }
}

final class CodeAgentErrorTests: XCTestCase {
    func testErrorDescriptionsAreNonEmpty() {
        let allErrors: [CodeAgentError] = [
            .missingAPIKey(provider: .openAI),
            .invalidServerURL("bad-url"),
            .requestFailed(statusCode: 500),
            .invalidGGUFPath("/tmp/missing.gguf"),
            .missingLlamaServerBinary("/tmp/missing-binary"),
            .llamaServerTimedOut,
            .llamaServerExited(terminationStatus: 1),
            .noModelLoaded,
            .noEngineConfigured
        ]

        for error in allErrors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}

final class AIProviderTests: XCTestCase {
    func testAIProviderExposesAllCases() {
        XCTAssertEqual(AIProvider.allCases.count, 4)
        XCTAssertTrue(AIProvider.allCases.contains(.openAI))
        XCTAssertTrue(AIProvider.allCases.contains(.nativeGGUF))
    }
}

// MARK: - Mocks

final class MockAIAgentEngine: AIAgentEngine {
    let provider = AIProvider.openAI
    var callCount = 0
    var shouldYield: [String] = []
    var errorToThrow: Error?

    func generateResponse(prompt: String, context: String) async throws -> AsyncThrowingStream<String, Error> {
        callCount += 1
        if let errorToThrow {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: errorToThrow)
            }
        }
        let tokens = shouldYield
        return AsyncThrowingStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func loadModel(path: URL?) async throws {}
}
