# Arbi Chief - Project Guide

## Overview

Arbi Chief is a cross-platform tournament management application for sports arbiters and organizers built with Flutter. It supports 14 sport types (chess, checkers, table tennis, swimming, and more) with comprehensive player/team management, match scheduling, result tracking, and PDF report generation. The UI is primarily in Ukrainian.

## Tech Stack

- **Framework**: Flutter (Dart 3.7+)
- **State Management**: Riverpod (MVVM pattern)
- **Database**: SQLite (sqflite)
- **PDF**: pdf + printing packages
- **Platforms**: Android, iOS, Windows, macOS, Linux, Web

## Architecture

MVVM pattern with Riverpod providers:

```
lib/
├── models/          # Data models (tournament, player, team, etc.)
├── services/        # Database & business logic (CRUD, sync, reports)
├── viewmodels/      # Riverpod providers and state notifiers
├── views/           # UI screens (18 screens)
└── sports/          # Sport-specific scoring and configuration
    ├── chess/
    ├── table_tennis/
    └── swimming/
```

## Key Files

- `lib/main.dart` — App entry point, multi-window setup
- `lib/services/database_service.dart` — SQLite schema (v14), migrations
- `lib/sports/sport_type_config.dart` — Sport type definitions and UI config
- `pubspec.yaml` — Dependencies and app metadata

## Build & Run

```bash
flutter pub get                # Install dependencies
flutter run -d <device>        # Run (windows/macos/linux/chrome)
flutter analyze                # Static analysis
flutter test                   # Run tests
flutter build <platform>       # Build release (apk/ios/windows/linux/macos/web)
```

## Database

SQLite with schema version 14. Core tables: `CMP_TOURNAMENT`, `CMP_PLAYER`, `CMP_TEAM`, `CMP_EVENT`, `CMP_ENTITY`. All tables have `sync_uid` column for cross-device synchronization.

## Code Conventions

- Ukrainian language for UI strings and some comments
- Riverpod `StateNotifier` / `AsyncNotifier` for state management
- Services handle all database operations; ViewModels call services
- Sport-specific logic lives under `lib/sports/<sport_name>/`
- Material Design 3 theming with dark/light mode support

## Testing

```bash
flutter test                   # Run widget tests
flutter analyze                # Lint with flutter_lints
```

Tests are in `test/`. Currently minimal — `widget_test.dart` is a placeholder.

## Important Notes

- Database files (*.db) are generated at runtime and excluded from version control
- Windows stores DB alongside the executable; other platforms use system DB path
- Multi-window support (standings display) uses `desktop_multi_window` package
- Gender is auto-detected from Ukrainian patronymic names
