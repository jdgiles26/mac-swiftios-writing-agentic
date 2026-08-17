import Foundation
import SwiftUI
import AppKit

@MainActor
final class AgentViewModel: ObservableObject {
    /// Shared instance so the menu-bar UI and the system Services handler
    /// (which cannot receive a SwiftUI-injected instance) observe the same state.
    static let shared = AgentViewModel()

    @Published var status = "Ready"
    @Published var streamingOutput = ""
    @Published var currentStep: PipelineStep = .analyzing
    @Published private(set) var isRunning = false

    private var pipeline: AgenticPipeline?
    private var cancellable: Task<Void, Never>?

    func configure(engine: AIAgentEngine, promptTemplate: String) {
        pipeline = AgenticPipeline(engine: engine, promptTemplate: promptTemplate)
    }

    func processSelectedText(_ text: String) {
        guard !text.isEmpty, let pipeline else {
            status = CodeAgentError.noEngineConfigured.localizedDescription
            return
        }

        streamingOutput = ""
        currentStep = .analyzing
        status = "Starting Agentic Workflow..."
        isRunning = true

        cancellable = Task {
            do {
                for try await event in pipeline.execute(selectedCode: text) {
                    switch event {
                    case .stepStarted(let step):
                        currentStep = step
                        status = step.rawValue
                    case .token(let token):
                        streamingOutput += token
                    }
                }
                // Cancellation may end the loop normally rather than
                // throwing, so don't overwrite the "Cancelled" status
                // that cancel() already set synchronously.
                if !Task.isCancelled {
                    status = "Workflow Complete"
                }
            } catch {
                if !Task.isCancelled {
                    status = "Error: \(error.localizedDescription)"
                }
            }
            isRunning = false
        }
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isRunning = false
        status = "Cancelled"
    }

    func applyResult() {
        guard !streamingOutput.isEmpty else { return }

        // Replace selected text in frontmost app
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(streamingOutput, forType: .string)

        NSWorkspace.shared.frontmostApplication?.activate()
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)

        status = "Applied to editor"
    }

    deinit {
        cancellable?.cancel()
    }
}
