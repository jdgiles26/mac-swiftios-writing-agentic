# CodeAgent macOS

A native macOS Menu Bar utility that streamlines AI-assisted coding through an
agentic (Analyze → Plan → Execute) workflow. It integrates with the system-wide
**Services** menu so you can select code in *any* app, right-click, and send it
to an AI engine of your choice — OpenAI, Ollama, LM Studio, or (as a stubbed
extension point) a native on-device GGUF/MLX model.

## Architecture

- **MVVM**: `AgentViewModel` (state/logic) is strictly separated from
  `Services` (`AIEngine`, `AgenticPipeline`, `TextService`) and `Views`
  (SwiftUI `SettingsView`, the menu-bar `MenuBarContent`).
- **Agentic Pipeline** (`AgenticPipeline.swift`): runs a three-step workflow
  (Analyzing → Planning → Executing) against the configured engine and
  streams tokens back as an `AsyncThrowingStream<String, Error>`, so errors
  from any step (bad API key, unreachable server, etc.) propagate cleanly to
  the UI instead of being silently swallowed.
- **Multi-Engine AI Layer** (`AIEngine.swift`): an `AIAgentEngine` protocol
  with three implementations —
  - `CloudEngine` — OpenAI-compatible cloud API.
  - `LocalServerEngine` — Ollama or LM Studio, talking to their
    OpenAI-compatible local HTTP servers.
  - `NativeGGUFEngine` — validates and stores a local `.gguf` model path but
    does **not** ship an inference backend (see [Known Limitations](#known-limitations)).

  Both HTTP engines stream real Server-Sent-Events incrementally (via
  `URLSession.bytes(for:)`), so tokens appear as the server produces them
  rather than all at once at the end.
- **System Integration** (`TextService.swift`): registers CodeAgent as a
  macOS Services provider. macOS itself captures the frontmost app's current
  text selection and hands it to CodeAgent's handler — the app does not (and
  cannot) simulate a copy of another app's selection itself.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+ toolchain
- An API key (OpenAI) or a running local server (Ollama / LM Studio) if you
  want to actually generate completions

## Setup

1. Clone the repository.
2. There are no external SPM dependencies to resolve — the package only uses
   Foundation, SwiftUI, and AppKit.
3. **Build and run for development:**
   ```bash
   swift build
   swift run CodeAgent
   ```
   This is sufficient for iterating on the pipeline, engines, and view
   models, and for exercising the menu bar UI. It is **not** sufficient to
   get the system Services menu entry working (see next step) because plain
   `swift build`/`swift run` produce a bare executable, not a signed `.app`
   bundle with an embedded `Info.plist`.
4. **Build as a full app (required for the "Analyze & Refactor" Services
   menu item to appear):**
   Open `Package.swift` in Xcode and run the `CodeAgent` scheme. If Xcode
   generates its own `Info.plist` instead of using
   `Sources/CodeAgent/Info.plist`, go to the target's **Build Settings** and
   either:
   - set **Generate Info.plist File** to `No` and point **Info.plist File**
     at `Sources/CodeAgent/Info.plist`, or
   - merge the `NSServices` and `LSUIElement` entries from
     `Sources/CodeAgent/Info.plist` into the generated one.

   After the first run, macOS needs to notice the new Service — if
   "Analyze & Refactor" doesn't appear in the Services menu right away, quit
   and relaunch the frontmost app you're testing in (or log out/in) so
   Launch Services re-scans registered Services.

## Configuration

- Click the sparkles icon in the menu bar → **Open Settings**.
- Choose a **Provider**:
  - *OpenAI Cloud* — paste an API key.
  - *Ollama Local* / *LM Studio Local* — set the base URL (defaults to
    `http://localhost:11434` and `http://localhost:1234`).
  - *Native GGUF/MLX* — **Browse** to a `.gguf` file. Loading the file will
    succeed, but see [Known Limitations](#known-limitations) — generation
    from this engine currently throws a clear "not implemented" error.
- Edit the **Prompt Template** if you want to change the instructions sent
  for each pipeline step. `{{step}}` and `{{code}}` are substituted with the
  current step name and the selected code.
- Click **Configure Engine** to activate your settings — this is what
  actually builds the `AIAgentEngine` and wires it into the app's shared
  `AgentViewModel`.

## Usage

1. Configure a provider in Settings (above).
2. Select code in any application, right-click → **Services** →
   **CodeAgent** → **Analyze & Refactor** (macOS may nest this under a
   top-level app menu instead of a contextual right-click menu depending on
   the app).
3. Click the menu bar icon to watch the streamed output as the pipeline
   analyzes, plans, and executes a refactor.
4. Click **Apply to Code** to paste the result back into the frontmost app.

## Testing

```bash
swift test
```

The suite in `Tests/CodeAgentTests/AIEngineTests.swift` covers:
- `AgenticPipeline` calling the engine once per workflow step and
  accumulating streamed tokens in order.
- The pipeline correctly rethrowing engine errors through the stream.
- `NativeGGUFEngine`'s path validation (`loadModel`) and its "not
  implemented" `generateResponse` behavior.
- `AIProvider` exposing all four provider cases via `CaseIterable`.

## Known Limitations

- **Native GGUF/MLX inference is not implemented.** No `llama.cpp` or
  `mlx-swift` backend is vendored in this package, and `Package.swift`
  declares no such dependency. `NativeGGUFEngine.loadModel(path:)` validates
  that the file exists, but `generateResponse` throws a descriptive error
  (`domain: "GGUF", code: -3`) rather than pretending to generate text. To
  make this engine functional, add a native library dependency (e.g. a
  `mlx-swift` package dependency, or a C target wrapping `llama.cpp`) and
  replace the `throw` in `NativeGGUFEngine.generateResponse` with a real
  call into it.
- **Services registration requires an app bundle.** As noted in Setup,
  `swift run` alone won't register the system Service; build/run through
  Xcode (or otherwise produce a properly signed `.app` with the
  `Info.plist` embedded) for the right-click integration to work.
- **HTTP engines assume an OpenAI-compatible `/v1/chat/completions`
  streaming endpoint.** Any Ollama/LM Studio setup must expose that
  interface (both do, by default, via their OpenAI-compatibility layers).
