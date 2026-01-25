# Repository Guidelines

## Project Structure & Module Organization
- `Sources/` — Swift executable target (`CloudYield`).
  - `App/` — entry point (`CloudYieldApp`, `AppDelegate`).
  - `Core/` — Process Tap monitoring (`MediaMonitor`), state engine (`StateManager`), NetEase control (`MusicController`), timers.
  - `UI/` — menu bar UI (`MenuBarController`).
  - `Utilities/` — logging, permissions, launch-at-login.
- Scripts:
  - `run.sh` — build (debug) and run from `.build/debug/CloudYield`.
  - `create_app.sh` — package `CloudYield.app` from `.build/release/` and code-sign it.
  - `install.sh` — copy `CloudYield.app` to `/Applications/`.
  - `scripts/process_tap_smoke_test.sh` — local smoke test for Process Tap.

## Build, Test, and Development Commands
- Requires macOS 14.2+ and Swift 5.9 (see `Package.swift`).
- `swift build` — debug build.
- `./run.sh` — quick local run (debug).
- `swift build -c release` — release build.
- `./create_app.sh && open CloudYield.app` — build a `.app` (recommended when validating macOS permissions).
- `./install.sh` — install to `/Applications/`.
- `swift test` — run tests (none by default).

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines; 4-space indentation.
- Types use `UpperCamelCase`; functions/variables use `lowerCamelCase`.
- Keep file names aligned with their primary type (e.g., `OtherAudioMonitor.swift`).
- Keep UI updates on `MainActor`/UI layer; keep state transitions deterministic in `StateTransitionEngine`.

## Testing Guidelines
- This repo currently has no `Tests/` target. If you add non-UI logic (especially state transitions), add `XCTest` under `Tests/CloudYieldTests/` and run `swift test`.

## Commit & Pull Request Guidelines
- Use Conventional Commits (seen in history): `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`.
- PRs: include a short summary, motivation (issue link if any), and “How to test” commands; include screenshots for menu/UI changes.
- Don’t commit build artifacts (`.build/`, `*.app/`, `*.zip`) unless doing a release.

## Security & Configuration Tips
- The app needs Accessibility + Apple Events permissions to control NetEase Cloud Music.
- The app needs Audio Capture permission to detect other apps’ audio via Process Tap (`NSAudioCaptureUsageDescription`).
- Logs live at `~/Library/Logs/CloudYield/`.
