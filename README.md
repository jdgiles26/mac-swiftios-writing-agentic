# CodeAgent macOS

A native macOS Menu Bar utility designed to streamline AI-assisted coding via an agentic workflow. It integrates system-wide text services, supports multi-engine AI inference (Cloud, Local Server, Native GGUF/MLX), and enforces a strict MVVM architecture with comprehensive TDD scaffolding.

## Architecture
- **MVVM**: Strict separation between `ViewModel` (state/logic), `Services` (AI/Text/Pipeline), and `Views` (SwiftUI).
- **Agentic Pipeline**: Multi-step workflow (Analyze → Plan → Execute) with streaming token output.
- **Multi-Engine AI Layer**: Abstract `AIAgentEngine` protocol supporting OpenAI, Ollama, LM Studio, and native `llama.cpp`/`mlx-swift` inference.
- **System Integration**: `NSServicesProvider` for global right-click context menu capture across any IDE/editor.

## Setup
1. Clone the repository.
2. Install dependencies (if any external frameworks are added later via SPM).
3. Build: `swift build` or open `Package.swift` in Xcode.
4. Run: `swift run CodeAgent`

## Configuration
- Open Settings via the Menu Bar icon.
- Configure API keys, toggle providers, set GGUF model paths, and define prompt templates.
- The app registers a global text service automatically on launch. Right-click any selected text → `CodeAgent` → `Analyze & Refactor`.

## Testing
Run TDD suite: `swift test`
Covers `AIAgentEngine` protocol contracts, `AgenticPipeline` state transitions, and streaming simulation.

## Hardware Optimization
Native Apple Silicon inference leverages `mlx-swift` via conditional compilation. Ensure `MLX` is linked in your build configuration for optimal GGUF throughput.