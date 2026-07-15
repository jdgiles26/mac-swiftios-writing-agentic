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
        var callCount = 0
        mockEngine.shouldYield = ["step1", "step2", "step3"]
        
        _ = try await pipeline.execute(selectedCode: "func test() {}")
        
        // Verify engine was called 3 times (analyzing, planning, executing)
        XCTAssertEqual(mockEngine.callCount, 3)
    }
    
    func testEngineThrowsOnInvalidPath() async throws {
        let engine = NativeGGUFEngine()
        await XCTAssertThrowsError(try await engine.loadModel(URL(fileURLWithPath: "/nonexistent.gguf"))) { error in
            XCTAssertEqual(error._code, -2)
        }
    }
    
    func testStreamingOutputAccumulates() async throws {
        mockEngine.shouldYield = ["Hello", " ", "World"]
        var output = ""
        
        for await token in try await pipeline.execute(selectedCode: "code") {
            output += token
        }
        
        XCTAssertEqual(output, "Hello World")
    }
}

// MARK: - Mocks
final class MockAIAgentEngine: AIAgentEngine {
    let provider = AIProvider.openAI
    var callCount = 0
    var shouldYield: [String] = []
    
    func generateResponse(prompt: String, context: String) async throws -> AsyncStream<String> {
        callCount += 1
        return AsyncStream { continuation in
            for token in shouldYield {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
    
    func loadModel(path: URL?) async throws {}
}