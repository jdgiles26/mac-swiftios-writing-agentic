import XCTest
@testable import CodeAgent

final class AIEngineTests: XCTestCase {
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

    func testStreamingOutputAccumulates() async throws {
        mockEngine.shouldYield = ["Hello", " ", "World"]
        var output = ""

        for try await token in pipeline.execute(selectedCode: "code") {
            output += token
        }

        // The pipeline calls the engine once per step (analyzing, planning,
        // executing), so the mock's tokens are emitted three times in a row.
        XCTAssertEqual(output, "Hello WorldHello WorldHello World\n[Workflow Complete]")
    }

    func testPipelineAppendsCompletionMarker() async throws {
        mockEngine.shouldYield = ["token"]
        var tokens: [String] = []

        for try await token in pipeline.execute(selectedCode: "code") {
            tokens.append(token)
        }

        XCTAssertEqual(tokens.last, "\n[Workflow Complete]")
    }

    func testPipelinePropagatesEngineErrors() async throws {
        mockEngine.errorToThrow = NSError(domain: "Test", code: 42)

        do {
            for try await _ in pipeline.execute(selectedCode: "code") {}
            XCTFail("Expected the pipeline to rethrow the engine's error")
        } catch {
            XCTAssertEqual((error as NSError).code, 42)
        }
    }

    func testEngineThrowsOnInvalidPath() async throws {
        let engine = NativeGGUFEngine()

        do {
            try await engine.loadModel(path: URL(fileURLWithPath: "/nonexistent.gguf"))
            XCTFail("Expected loadModel to throw for a nonexistent path")
        } catch {
            XCTAssertEqual((error as NSError).code, -2)
        }
    }

    func testNativeEngineLoadsValidPath() async throws {
        let engine = NativeGGUFEngine()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await engine.loadModel(path: tempFile)
        // No error thrown means the path was accepted; generateResponse should
        // now fail with the "not implemented" error rather than "no model loaded".
        do {
            _ = try await engine.generateResponse(prompt: "p", context: "c")
            XCTFail("Expected generateResponse to throw since no native backend is linked")
        } catch {
            XCTAssertEqual((error as NSError).domain, "GGUF")
            XCTAssertEqual((error as NSError).code, -3)
        }
    }

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
