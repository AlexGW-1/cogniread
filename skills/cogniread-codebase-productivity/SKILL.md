---
name: cogniread-codebase-productivity
description: Guidance for working on the CogniRead Flutter app (Clean Architecture library/reader/sync features, Hive storage, offline-first scope). Use when coding, testing, or debugging in this repo, including sync adapters and library/reader flows.
---

# CogniRead codebase helper

## Stack and layout
- Flutter app (Material 3); entry at `lib/main.dart` -> `lib/src/app.dart`.
- `lib/src/core`: minimal `Result`, logger `Log`, exceptions, `StorageService` + Hive bootstrap.
- `lib/src/features`: `library` (Hive store, controllers, preferences), `reader` (EPUB parsing, caching), `sync` (file sync adapters for Google Drive, Dropbox, OneDrive, Yandex Disk, WebDAV + event log).
- UI copy is Russian; keep wording consistent when adding user-facing strings.

## Setup and run
- Install deps with `flutter pub get`; lint with `flutter analyze`; format with `dart format .` (or `flutter format`).
- Run app: `flutter run -d macos` (other targets similar). If platform folders are missing, run `scripts/bootstrap_platforms.sh`. Env check: `scripts/check_env.sh`.
- Prefer `StorageService` helpers for file IO instead of direct `File` access when working with app storage.

## Development patterns
- Use the lightweight `Result` (`core/types/result.dart`) for domain/reporting flows instead of throwing across layers; surface user-facing text in Russian.
- Prefer `Log.d` over `print`; honor lint rules (single quotes, explicit return types, avoid print) and strict inference settings in `analysis_options.yaml`.
- Reuse `LibraryStore` for persistence and call `init()` before use; respect existing debounce/caching logic (e.g., position events, reader chapter cache).
- File sync: implement `SyncAdapter`/`SyncFileRef`; wrap API errors in `SyncAdapterException` with informative code/message. Keep adapters offline-friendly (no global state, injectable token providers).
- The repo is intentionally light on external deps; add new packages only when necessary.

## Testing
- Default suite: `flutter test` from repo root. Targeted runs: `flutter test test/sync`, etc., for focused debugging.
- Widget tests rely on stable keys/layout; update tests if you rename keys or restructure critical widgets.
- Test fixtures (`.epub`) live in `test/`; keep paths stable when adding/removing cases.

## References
- Quick context: `README.md`, `STATE.md`.
- Scope and plans: `docs/spec_mvp.md`, `docs/plan_mvp0.md`, `docs/plan_mvp1.md`.
