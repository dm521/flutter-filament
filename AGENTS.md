# Repository Guidelines

## Project Structure & Module Organization
- App code: `lib/` (entry: `lib/main.dart`; experiments: `lib/main_test.dart`).
- Assets: `assets/` (models, environments, textures; declared in `pubspec.yaml`).
- Platform folders: `android/`, `ios/`.
- Tests: `test/` (Dart/Flutter tests, e.g., `widget_test.dart`).
- Docs & tools: `docs/`, `scripts/` (asset conversion helpers), `lights/` (lighting presets JSON).

## Build, Test, and Development Commands
- Install deps: `flutter pub get`.
- Analyze code: `flutter analyze`.
- Format code: `dart format .` (CI expects formatted code).
- Run app: `flutter run -d ios` or `flutter run -d android`.
- Run tests: `flutter test`.
- Build release: `flutter build apk` (Android), `flutter build ios` (Xcode signing required).

## Coding Style & Naming Conventions
- Language: Dart (Flutter). Use 2-space indentation; no tabs.
- Naming: `UpperCamelCase` for classes, `lowerCamelCase` for methods/fields, `snake_case` for file names.
- Lints: configured via `analysis_options.yaml` (uses `flutter_lints`). Fix all analyzer warnings.
- Imports: prefer relative imports within `lib/`.

## Testing Guidelines
- Framework: `flutter_test`.
- Location: place tests under `test/` with `_test.dart` suffix.
- Patterns: small, focused widget/unit tests; avoid device-only assumptions.
- Run locally with `flutter test`; ensure tests pass before opening a PR.

## Commit & Pull Request Guidelines
- Commits: prefer Conventional Commits (e.g., `feat: add orbit control`, `fix: null asset guard`, `docs: lighting notes`).
- PRs must include:
  - Clear description and rationale; link issues if applicable.
  - Screenshots/video for UI/3D changes (before/after if possible).
  - Steps to test (commands, device/OS).
  - Confirmation that `flutter analyze`, `dart format .`, and `flutter test` pass.

## Security & Configuration Tips
- Large binaries: keep in `assets/` and declare in `pubspec.yaml`.
- Do not commit build artifacts (`build/`, `.dart_tool/`).
- Thermion/Filament: ensure test devices have GPU support; when updating lighting, keep presets in `lights/` and load via paths like `lights/PointLight.json`.

## Architecture Overview
- Flutter app embedding Thermion viewer. Core flows: initialize `ThermionViewer`, load GLB assets from `assets/models/`, apply lighting from `lights/`, render in main scene from `lib/main.dart`.
