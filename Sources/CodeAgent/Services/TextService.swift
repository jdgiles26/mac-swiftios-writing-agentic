import AppKit

@MainActor
final class TextServiceManager {
    static let shared = TextServiceManager()
    private let viewModel = AgentViewModel()
    
    private init() {}
    
    func register() {
        NSApplication.shared.servicesProvider = self
    }
}

extension TextServiceManager: NSServicesProvider {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title == "Analyze & Refactor"
    }
    
    func doCommand(by selector: Selector) {
        guard let menu = NSApplication.shared.mainMenu?.item(at: 0),
              let serviceItem = menu.submenu?.item(withTitle: "Analyze & Refactor") else { return }
        
        guard serviceItem.menu?.selectedItem == serviceItem else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("", forType: .string)
        
        // Request selected text from the frontmost app
        NSWorkspace.shared.frontmostApplication?.activate()
        NSApplication.shared.sendAction(#selector(NSApplication.selectMenuItem(_:)), to: nil, from: nil)
        
        // Fallback: capture from current pasteboard if available
        if let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty {
            viewModel.processSelectedText(selectedText)
        } else {
            // Direct capture via NSWorkspace services
            if let service = NSWorkspace.shared.service(forName: "CodeAgent") {
                viewModel.processSelectedText("")
            }
        }
    }
}

// Helper to actually capture selection across apps
extension TextServiceManager {
    func captureSelectedText() async -> String {
        await withCheckedContinuation { continuation in
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString("", forType: .string)
            
            // Use NSWorkspace to request selection from frontmost app
            NSWorkspace.shared.frontmostApplication?.activate()
            
            // Poll pasteboard briefly for selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let text = pasteboard.string(forType: .string) ?? ""
                continuation.resume(returning: text)
            }
        }
    }
}