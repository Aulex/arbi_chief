# CLAUDE.md - Project Guide for Claude Code

## Project Overview

**arbi_chief** is a Flutter cross-platform tournament management application (chess arbiter tool) with Ukrainian localization. It manages tournaments, players, teams, crosstables, game results, and PDF report generation.

## Tech Stack

- **Language**: Dart 3.7.0+
- **Framework**: Flutter (Android, iOS, Windows, Linux, macOS, Web)
- **State Management**: Riverpod 3.2.1 (AsyncNotifier pattern)
- **Database**: SQLite via sqflite / sqflite_common_ffi
- **PDF**: pdf 3.11.1 + printing 3.13.3
- **Architecture**: MVVM (Models → Services → ViewModels → Views)

## Project Structure

```
lib/
├── main.dart                # Entry point
├── models/                  # Data classes (player, team, tournament, game)
├── services/                # Database & business logic layer
├── viewmodels/              # Riverpod providers & state management
└── views/                   # UI screens (ConsumerWidget)
```

## Common Commands

```bash
# Run the app
flutter run

# Run on specific platform
flutter run -d windows
flutter run -d linux
flutter run -d chrome

# Analyze code
flutter analyze

# Run tests
flutter test

# Get dependencies
flutter pub get

# Build release
flutter build apk
flutter build windows
flutter build linux
```

## Code Conventions

- **Architecture**: Follow MVVM pattern — models in `models/`, database operations in `services/`, state in `viewmodels/`, UI in `views/`
- **State Management**: Use Riverpod AsyncNotifier for async operations; define providers in `viewmodels/`
- **Database**: All SQLite operations go through `DatabaseService` singleton; foreign keys are enabled
- **Localization**: App uses Ukrainian locale (`uk`); use `intl` for any new localized strings
- **Linting**: Follow rules in `analysis_options.yaml` (flutter_lints); run `flutter analyze` before committing
- **Naming**: Use Dart conventions — `camelCase` for variables/functions, `PascalCase` for classes, `snake_case` for file names
- **Platform support**: Desktop platforms (Windows/Linux) use `sqflite_common_ffi`; check `DatabaseService` for platform-specific DB paths

## Database Schema

- Database file: `tournament_blueprint_v14.db`
- Key tables: `CMP_TOURNAMENT_TYPE`, `CMP_ENTITY`, plus tournament/team/player/game tables
- Foreign key constraints are enabled

## Important Notes

- The largest file is `tournament_edit_screen.dart` (~2700 lines) — handle with care
- Desktop builds use CMake (Windows/Linux) and Xcode (macOS)
- Android uses Gradle (build.gradle.kts)
- Always run `flutter pub get` after modifying `pubspec.yaml`
