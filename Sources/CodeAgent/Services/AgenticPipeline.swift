import Foundation

@MainActor
enum PipelineStep: String {
    case analyzing = "Analyzing Code Structure"
    case planning = "Planning Improvements"
    executing = "Executing Refactor"
    case complete = "Complete"
}

final class AgenticPipeline {
    private let engine: AIAgentEngine
    private let promptTemplate: String
    
    init(engine: AIAgentEngine, promptTemplate: String) {
        self.engine = engine
        self.promptTemplate = promptTemplate
    }
    
    func execute(selectedCode: String) async throws -> AsyncStream<String> {
        let steps: [PipelineStep] = [.analyzing, .planning, .executing]
        
        for step in steps {
            let stepPrompt = promptTemplate
                .replacingOccurrences(of: "{{step}}", with: step.rawValue)
                .replacingOccurrences(of: "{{code}}", with: selectedCode)
            
            let stream = try await engine.generateResponse(prompt: stepPrompt, context: selectedCode)
            
            for await token in stream {
                yield token
            }
        }
        
        yield "\n[Workflow Complete]"
    }
}