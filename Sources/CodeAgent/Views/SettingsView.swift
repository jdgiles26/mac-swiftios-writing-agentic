import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: AgentViewModel
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("provider") private var providerString = AIProvider.openAI.rawValue
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("lmStudioURL") private var lmStudioURL = "http://localhost:1234"
    @AppStorage("ggufPath") private var ggufPath = ""
    @AppStorage("llamaServerPath") private var llamaServerPath = "/opt/homebrew/bin/llama-server"
    @AppStorage("llamaServerPort") private var llamaServerPort = 8734
    @AppStorage("promptTemplate") private var promptTemplate = "Analyze: {{step}}\nCode:\n{{code}}\nOutput:"

    @State private var validationError: String?
    @State private var isConfiguring = false

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
                        Button("Browse") { browseForGGUFModel() }
                    }
                    TextField("llama-server Path", text: $llamaServerPath)
                    Stepper("Port: \(llamaServerPort)", value: $llamaServerPort, in: 1024...65535)
                    Text("Requires llama.cpp's llama-server binary (e.g. `brew install llama.cpp`). CodeAgent launches it locally and never sends your code off-device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Prompt Template") {
                TextEditor(text: $promptTemplate)
                    .frame(height: 100)
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Actions") {
                Button(isConfiguring ? "Configuring…" : "Configure Engine") {
                    configureEngine()
                }
                .disabled(isConfiguring)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private func browseForGGUFModel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let ggufType = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [ggufType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            ggufPath = url.path
        }
    }

    private func configureEngine() {
        validationError = nil

        guard let provider = AIProvider(rawValue: providerString) else {
            validationError = "Unknown provider selection."
            return
        }

        let settings = EngineSettings(
            apiKey: apiKey,
            ollamaURL: ollamaURL,
            lmStudioURL: lmStudioURL,
            ggufPath: ggufPath,
            llamaServerPath: llamaServerPath,
            llamaServerPort: llamaServerPort
        )

        let engine: AIAgentEngine
        do {
            engine = try EngineFactory.makeEngine(for: provider, settings: settings)
        } catch {
            validationError = error.localizedDescription
            return
        }

        if provider == .nativeGGUF, let nativeEngine = engine as? NativeGGUFEngine {
            isConfiguring = true
            let path = URL(fileURLWithPath: ggufPath)
            Task {
                defer { isConfiguring = false }
                do {
                    try await nativeEngine.loadModel(path: path)
                    viewModel.configure(engine: engine, promptTemplate: promptTemplate)
                    viewModel.status = "GGUF model loaded and ready."
                } catch {
                    validationError = error.localizedDescription
                }
            }
        } else {
            viewModel.configure(engine: engine, promptTemplate: promptTemplate)
            viewModel.status = "Engine configured."
        }
    }
}
