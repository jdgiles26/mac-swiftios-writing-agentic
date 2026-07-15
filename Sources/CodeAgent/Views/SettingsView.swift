import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AgentViewModel
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("provider") private var providerString = AIProvider.openAI.rawValue
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("lmStudioURL") private var lmStudioURL = "http://localhost:1234"
    @AppStorage("ggufPath") private var ggufPath = ""
    @AppStorage("promptTemplate") private var promptTemplate = "Analyze: {{step}}\nCode:\n{{code}}\nOutput:"
    
    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $providerString) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                
                if providerString == AIProvider.openAI.rawValue {
                    TextField("OpenAI API Key", text: $apiKey)
                        .textContentType(.password)
                } else if providerString == AIProvider.ollama.rawValue {
                    TextField("Ollama URL", text: $ollamaURL)
                } else if providerString == AIProvider.lmStudio.rawValue {
                    TextField("LM Studio URL", text: $lmStudioURL)
                } else if providerString == AIProvider.nativeGGUF.rawValue {
                    HStack {
                        TextField("GGUF Model Path", text: $ggufPath)
                        Button("Browse") { /* Open panel logic */ }
                    }
                }
            }
            
            Section("Prompt Template") {
                TextEditor(text: $promptTemplate)
                    .frame(height: 100)
            }
            
            Section("Actions") {
                Button("Configure Engine") {
                    configureEngine()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
    
    private func configureEngine() {
        let engine: AIAgentEngine
        switch providerString {
        case AIProvider.openAI.rawValue:
            engine = CloudEngine(apiKey: apiKey)
        case AIProvider.ollama.rawValue:
            engine = LocalServerEngine(provider: .ollama, baseURL: ollamaURL)
        case AIProvider.lmStudio.rawValue:
            engine = LocalServerEngine(provider: .lmStudio, baseURL: lmStudioURL)
        case AIProvider.nativeGGUF.rawValue:
            engine = NativeGGUFEngine()
            if let path = URL(string: ggufPath) {
                Task { try await engine.loadModel(path) }
            }
        default:
            engine = CloudEngine(apiKey: apiKey)
        }
        viewModel.configure(engine: engine, promptTemplate: promptTemplate)
    }
}