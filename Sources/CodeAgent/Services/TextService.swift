import AppKit

/// Registers CodeAgent as a macOS Services provider so "Analyze & Refactor"
/// appears in the system-wide right-click Services menu of any app.
///
/// The Services dispatch mechanism (declared in Info.plist's `NSServices`)
/// hands the provider a pasteboard that already contains the frontmost
/// app's current selection — CodeAgent does not need to (and cannot)
/// simulate a copy itself.
@MainActor
final class TextServiceManager {
    static let shared = TextServiceManager()
    private let viewModel = AgentViewModel.shared

    private init() {}

    func register() {
        NSApplication.shared.servicesProvider = self
    }

    /// Invoked by AppKit for the "Analyze & Refactor" Services menu item.
    /// Selector name must match the `NSMessage` entry in Info.plist.
    @objc func analyzeAndRefactor(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty else {
            error.pointee = "CodeAgent: No text was selected." as NSString
            return
        }

        viewModel.processSelectedText(selectedText)
    }
}
