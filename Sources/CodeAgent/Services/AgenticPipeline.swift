import Foundation

enum PipelineStep: String {
    case analyzing = "Analyzing Code Structure"
    case planning = "Planning Improvements"
    case executing = "Executing Refactor"
    case complete = "Complete"
}

final class AgenticPipeline {
    private let engine: AIAgentEngine
    private let promptTemplate: String

    init(engine: AIAgentEngine, promptTemplate: String) {
        self.engine = engine
        self.promptTemplate = promptTemplate
    }

    /// Runs the Analyze → Plan → Execute workflow, streaming tokens from each
    /// step's engine call as they arrive.
    func execute(selectedCode: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let steps: [PipelineStep] = [.analyzing, .planning, .executing]

                    for step in steps {
                        let stepPrompt = promptTemplate
                            .replacingOccurrences(of: "{{step}}", with: step.rawValue)
                            .replacingOccurrences(of: "{{code}}", with: selectedCode)

                        let stream = try await engine.generateResponse(prompt: stepPrompt, context: selectedCode)

                        for try await token in stream {
                            continuation.yield(token)
                        }
                    }

                    continuation.yield("\n[Workflow Complete]")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
