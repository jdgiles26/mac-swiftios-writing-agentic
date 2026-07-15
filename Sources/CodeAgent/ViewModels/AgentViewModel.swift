import Foundation
import SwiftUI

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var status = "Ready"
    @Published var streamingOutput = ""
    @Published var currentStep: PipelineStep = .analyzing
    
    private var pipeline: AgenticPipeline?
    private var cancellable: Task<Void, Never>?
    
    func configure(engine: AIAgentEngine, promptTemplate: String) {
        pipeline = AgenticPipeline(engine: engine, promptTemplate: promptTemplate)
    }
    
    func processSelectedText(_ text: String) {
        guard !text.isEmpty, let pipeline = pipeline else {
            status = "No text selected or engine configured."
            return
        }
        
        streamingOutput = ""
        status = "Starting Agentic Workflow..."
        
        cancellable = Task {
            do {
                for await token in try await pipeline.execute(selectedCode: text) {
                    currentStep = .complete
                    streamingOutput += token
                    status = "Processing: \(token)"
                }
                status = "Workflow Complete"
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func applyResult() {
        guard !streamingOutput.isEmpty else { return }
        
        // Replace selected text in frontmost app
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(streamingOutput, forType: .string)
        
        NSWorkspace.shared.frontmostApplication?.activate()
        NSApp.sendAction(#selector(NSApplication.paste(_:)), to: nil, from: nil)
        
        status = "Applied to editor"
    }
    
    deinit {
        cancellable?.cancel()
    }
}