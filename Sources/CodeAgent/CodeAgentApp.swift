import SwiftUI
import AppKit

@main
struct CodeAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AgentViewModel.shared
    
    var body: some Scene {
        MenuBarExtra("CodeAgent", systemImage: "sparkles") {
            MenuBarContent(viewModel: viewModel)
        }
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TextServiceManager.shared.register()
    }
}

struct MenuBarContent: View {
    @ObservedObject var viewModel: AgentViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isRunning {
                StepProgressView(currentStep: viewModel.currentStep)
            }

            Text(viewModel.status)
                .font(.caption)
                .foregroundColor(.secondary)

            if !viewModel.streamingOutput.isEmpty {
                ScrollView {
                    Text(viewModel.streamingOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }

            if viewModel.isRunning {
                Button("Cancel", role: .destructive) {
                    viewModel.cancel()
                }
            } else {
                Button("Apply to Code") {
                    viewModel.applyResult()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.streamingOutput.isEmpty)
            }

            Button("Open Settings") {
                openSettings()
            }
        }
        .padding()
        .frame(width: 300)
    }
}

/// Shows the Analyze → Plan → Execute workflow with the currently active
/// step highlighted, reflecting the real `PipelineEvent.stepStarted` events
/// emitted by `AgenticPipeline` rather than a generic spinner.
struct StepProgressView: View {
    let currentStep: PipelineStep

    private let steps: [PipelineStep] = [.analyzing, .planning, .executing]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(color(for: step))
                    .frame(width: 8, height: 8)
                if step != steps.last {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for step: PipelineStep) -> Color {
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step) else {
            return .secondary
        }
        if stepIndex < currentIndex { return .green }
        if stepIndex == currentIndex { return .accentColor }
        return Color.secondary.opacity(0.3)
    }
}