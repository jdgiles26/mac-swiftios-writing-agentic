import Foundation

enum PipelineStep: String {
    case analyzing = "Analyzing Code Structure"
    case planning = "Planning Improvements"
    case executing = "Executing Refactor"
    case complete = "Complete"
}

/// A single event out of `AgenticPipeline.execute`: either a new step
/// starting, or a token streamed from the engine for the current step.
enum PipelineEvent {
    case stepStarted(PipelineStep)
    case token(String)
}

final class AgenticPipeline {
    private let engine: AIAgentEngine
    private let promptTemplate: String

    init(engine: AIAgentEngine, promptTemplate: String) {
        self.engine = engine
        self.promptTemplate = promptTemplate
    }

    /// Runs the Analyze → Plan → Execute workflow, reporting each step
    /// boundary and streaming tokens from that step's engine call as they
    /// arrive, so callers can show real per-step progress.
    func execute(selectedCode: String) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let steps: [PipelineStep] = [.analyzing, .planning, .executing]

                    for step in steps {
                        continuation.yield(.stepStarted(step))

                        let stepPrompt = promptTemplate
                            .replacingOccurrences(of: "{{step}}", with: step.rawValue)
                            .replacingOccurrences(of: "{{code}}", with: selectedCode)

                        let stream = try await engine.generateResponse(prompt: stepPrompt, context: selectedCode)

                        for try await token in stream {
                            continuation.yield(.token(token))
                        }
                    }

                    continuation.yield(.stepStarted(.complete))
                    continuation.yield(.token("\n[Workflow Complete]"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
