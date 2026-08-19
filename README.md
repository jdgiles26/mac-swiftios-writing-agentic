# CodeAgent macOS

A native macOS Menu Bar utility that streamlines AI-assisted coding through an
agentic (Analyze → Plan → Execute) workflow. It integrates with the system-wide
**Services** menu so you can select code in *any* app, right-click, and send it
to an AI engine of your choice — OpenAI, Ollama, LM Studio, or a fully local
GGUF model via `llama.cpp`.

## Architecture

- **MVVM**: `AgentViewModel` (state/logic) is strictly separated from
  `Services` (`AIEngine`, `AgenticPipeline`, `TextService`, `EngineFactory`)
  and `Views` (SwiftUI `SettingsView`, the menu-bar `MenuBarContent`).
- **Agentic Pipeline** (`AgenticPipeline.swift`): runs a three-step workflow
  (Analyzing → Planning → Executing) against the configured engine. It emits
  an `AsyncThrowingStream<PipelineEvent, Error>`, where each `PipelineEvent`
  is either `.stepStarted(PipelineStep)` or `.token(String)` — the menu bar
  UI uses `.stepStarted` events to show which step is actually running
  (`StepProgressView` in `CodeAgentApp.swift`), and errors from any step
  (bad API key, unreachable server, a crashed local server) propagate
  cleanly to the UI instead of being silently swallowed.
- **Multi-Engine AI Layer** (`AIEngine.swift`, `NativeGGUFEngine.swift`): an
  `AIAgentEngine` protocol with three implementations, all genuinely
  functional — none are stubs or mocked:
  - `CloudEngine` — OpenAI-compatible cloud API.
  - `LocalServerEngine` — Ollama or LM Studio, talking to their
    OpenAI-compatible local HTTP servers.
  - `NativeGGUFEngine` — launches `llama.cpp`'s `llama-server` binary as a
    child process against your local `.gguf` file, waits for it to become
    healthy, then streams from its OpenAI-compatible endpoint. Inference
    runs fully on-device (Metal-accelerated on Apple Silicon); no code ever
    leaves your machine for this provider. See
    [Native GGUF Engine](#native-gguf-engine-setup) below.

  All three share `streamChatCompletion` (`AIEngine.swift`), which streams
  real Server-Sent-Events incrementally via `URLSession.bytes(for:)` — tokens
  appear as the server produces them, not all at once at the end.
- **`EngineFactory`** (`EngineFactory.swift`): pure, unit-tested logic that
  turns raw settings values into a validated `AIAgentEngine`, throwing a
  typed `CodeAgentError` (missing API key, invalid URL, missing GGUF/binary
  path, etc.) instead of `SettingsView` silently falling back to a default
  provider when configuration is incomplete.
- **`CodeAgentError`** (`CodeAgentError.swift`): a single `LocalizedError`
  enum used across the engine/pipeline layer instead of ad-hoc `NSError`
  construction, so every failure has a consistent, readable message.
- **System Integration** (`TextService.swift`): registers CodeAgent as a
  macOS Services provider. macOS itself captures the frontmost app's current
  text selection and hands it to CodeAgent's handler — the app does not (and
  cannot) simulate a copy of another app's selection itself.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+ toolchain
- One of:
  - An OpenAI API key,
  - A running Ollama or LM Studio server, or
  - `llama.cpp` installed locally (for the Native GGUF provider — see below)

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
  - *Native GGUF/MLX* — set the `llama-server` binary path and port, then
    **Browse** to a `.gguf` file (see setup below). Missing or invalid
    fields are reported inline instead of silently falling back to another
    provider.
- Edit the **Prompt Template** if you want to change the instructions sent
  for each pipeline step. `{{step}}` and `{{code}}` are substituted with the
  current step name and the selected code.
- Click **Configure Engine**. For the native provider this also launches
  and health-checks the local server, so it may take a few seconds.

### Native GGUF Engine setup

1. Install `llama.cpp`, e.g. `brew install llama.cpp` (or build it yourself
   — either way you need the `llama-server` executable).
2. In Settings, set **llama-server Path** to the installed binary (Homebrew
   typically puts it at `/opt/homebrew/bin/llama-server` on Apple Silicon,
   the default value pre-filled in Settings).
3. Set a **Port** (defaults to `8734`, chosen to avoid colliding with
   Ollama's `11434` or LM Studio's `1234`).
4. **Browse** to your `.gguf` model file and click **Configure Engine**.

`NativeGGUFEngine` spawns `llama-server --model <path> --host 127.0.0.1
--port <port> -ngl 99` as a child process, polls its `/health` endpoint
until ready (or times out after 60s), and then reuses the same streaming
HTTP client as the Ollama/LM Studio engines against
`http://127.0.0.1:<port>/v1/chat/completions`. This was chosen over linking
llama.cpp's C API directly in-process: it depends only on stable Foundation
APIs (`Process`, `URLSession`) rather than a C ABI that shifts between
llama.cpp releases, while still running 100% locally and using llama.cpp's
own Metal acceleration on Apple Silicon.

## Usage

1. Configure a provider in Settings (above).
2. Select code in any application, right-click → **Services** →
   **CodeAgent** → **Analyze & Refactor** (macOS may nest this under a
   top-level app menu instead of a contextual right-click menu depending on
   the app).
3. Click the menu bar icon to watch live per-step progress (Analyzing →
   Planning → Executing) and the streamed output. **Cancel** stops an
   in-flight run.
4. Click **Apply to Code** to paste the result back into the frontmost app.

## Testing

```bash
swift test
```

`Tests/CodeAgentTests/AIEngineTests.swift` covers:
- `AgenticPipeline` calling the engine once per workflow step, reporting
  `.stepStarted` events in the correct order, accumulating streamed tokens,
  and rethrowing engine errors through the stream.
- `EngineFactory` validating each provider's required settings and
  constructing the right engine type, without needing network access or a
  real local server.
- `CodeAgentError`'s messages.
- `NativeGGUFEngine`'s path/binary validation (missing GGUF file, missing
  `llama-server` binary, calling `generateResponse` before a model is
  loaded) — all exercised without spawning a real process.
- `AIProvider` exposing all four provider cases via `CaseIterable`.

Actually spawning `llama-server` and streaming real generated tokens
requires a real `llama.cpp` build and a `.gguf` model, which aren't
available in CI; that path is exercised manually via the
[Native GGUF Engine setup](#native-gguf-engine-setup) above and the
in-app Settings → Configure Engine flow, which surfaces failures (timeout,
crashed process, bad binary path) as visible error text rather than a
silent no-op.

## Known Limitations

- **Services registration requires an app bundle.** As noted in Setup,
  `swift run` alone won't register the system Service; build/run through
  Xcode (or otherwise produce a properly signed `.app` with the
  `Info.plist` embedded) for the right-click integration to work.
- **HTTP engines assume an OpenAI-compatible `/v1/chat/completions`
  streaming endpoint.** Ollama, LM Studio, and `llama-server` all expose
  this by default.
- **The Native GGUF engine requires `llama.cpp` to be installed
  separately** (see setup above) — it is not vendored in this repository,
  and there is intentionally no fallback stub: if `llama-server` can't be
  found or fails to start, `CodeAgentError` reports exactly why instead of
  pretending to generate a response.
