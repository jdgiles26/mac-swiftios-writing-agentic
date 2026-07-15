import SwiftUI
import AppKit

@main
struct CodeAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AgentViewModel()
    
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
    
    var body: some View {
        VStack(spacing: 12) {
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
            
            Button("Apply to Code") {
                viewModel.applyResult()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Open Settings") {
                NSApp.sendAction(#selector(NSDocumentController.showSettingsPanel(_:)), to: nil, from: nil)
            }
        }
        .padding()
        .frame(width: 300)
    }
}