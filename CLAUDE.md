# Arbi Chief - Project Guide

## AI Persona

You are a **senior Flutter/Dart programmer** with deep expertise in cross-platform mobile and desktop development, state management with Riverpod, SQLite databases, and the Flutter ecosystem.

## Overview

Arbi Chief is a cross-platform tournament management application for sports arbiters and organizers built with Flutter. It supports 14 sport types with comprehensive player/team management, match scheduling, result tracking, and PDF report generation. The UI is primarily in Ukrainian.

### Supported Sports (14 total)

| Sport (Ukrainian) | Sport (English) | Status |
|---|---|---|
| Шахи | Chess | Fully implemented |
| Шашки | Checkers | Fully implemented |
| Настільний теніс | Table Tennis | Fully implemented |
| Плавання | Swimming | Fully implemented |
| Футзал | Futsal | Registered |
| Гирьовий спорт | Kettlebell Sport | Registered |
| Армрестлінг | Arm Wrestling | Registered |
| Волейбол | Volleyball | Registered |
| Стрітбол | Streetball | Registered |
| Легка атлетика | Track & Field | Registered |
| Велоспорт | Cycling | Registered |
| Баскетбол | Basketball | Registered |
| Пауерліфтинг | Powerlifting | Registered |
| Перетягування канату | Tug of War | Registered |

> "Fully implemented" = has dedicated scoring logic, service, and UI tabs. "Registered" = available in sport selection but uses generic tournament flow.

## Tech Stack

- **Framework**: Flutter (Dart 3.7+)
- **State Management**: Riverpod 3.x (MVVM pattern)
- **Database**: SQLite via sqflite + sqflite_common_ffi (desktop)
- **PDF**: pdf + printing packages
- **Desktop**: desktop_multi_window (multi-window standings)
- **Platforms**: Android, iOS, Windows, macOS, Linux, Web

## Architecture

MVVM pattern with Riverpod providers:

```
lib/
├── main.dart                # App entry point, multi-window setup
├── models/                  # Data models (7 files)
│   ├── entity_model.dart
│   ├── player_model.dart
│   ├── report_model.dart
│   ├── sport_type_config.dart   # Re-exports from sports/
│   ├── swimming_model.dart
│   ├── team_model.dart
│   └── tournament_model.dart
├── services/                # Database & business logic (7 files)
│   ├── database_service.dart        # SQLite schema v14, migrations
│   ├── database_sync_service.dart   # Cross-device sync
│   ├── player_service.dart
│   ├── report_service.dart          # PDF report generation
│   ├── swimming_service.dart
│   ├── team_service.dart
│   └── tournament_service.dart
├── viewmodels/              # Riverpod providers (11 files)
│   ├── font_scale_provider.dart
│   ├── nav_provider.dart
│   ├── navigation_viewmodel.dart
│   ├── player_viewmodel.dart
│   ├── report_viewmodel.dart
│   ├── shared_providers.dart
│   ├── sport_type_provider.dart
│   ├── standings_window_provider.dart
│   ├── team_viewmodel.dart
│   ├── theme_provider.dart
│   └── tournament_viewmodel.dart
├── views/                   # UI screens (18 files)
│   ├── main_view.dart
│   ├── player_view.dart
│   ├── report_view.dart
│   ├── reports_list_view.dart
│   ├── settings_view.dart
│   ├── sport_selection_screen.dart
│   ├── standings_window.dart
│   ├── swimming_results_tab.dart
│   ├── swimming_team_standings_tab.dart
│   ├── team_edit_screen.dart
│   ├── team_view.dart
│   ├── tournament_add_screen.dart
│   ├── tournament_cross_table_tab.dart
│   ├── tournament_edit_screen.dart
│   ├── tournament_game_results_tab.dart
│   ├── tournament_players_tab.dart
│   ├── tournament_teams_tab.dart
│   └── tournament_view.dart
└── sports/                  # Sport-specific logic (3 sport modules)
    ├── sport_type_config.dart       # Sport type definitions & UI config
    ├── chess/
    │   └── chess_scoring.dart
    ├── swimming/
    │   ├── swimming_model.dart
    │   ├── swimming_results_tab.dart
    │   ├── swimming_service.dart
    │   └── swimming_team_standings_tab.dart
    └── table_tennis/
        ├── table_tennis_providers.dart
        ├── table_tennis_scoring.dart
        └── table_tennis_service.dart
```

**Total: ~53 Dart source files**

### Data Flow

```
Views (UI) → ViewModels (Riverpod providers) → Services → SQLite Database
```

- **Views** render UI and dispatch user actions to ViewModels
- **ViewModels** (StateNotifier / AsyncNotifier) manage state and call Services
- **Services** perform all database CRUD operations and business logic
- **Sports modules** encapsulate sport-specific scoring, rules, and UI

## Key Files

- `lib/main.dart` — App entry point, multi-window setup
- `lib/services/database_service.dart` — SQLite schema (v14), all migrations
- `lib/services/database_sync_service.dart` — Cross-device sync via sync_uid
- `lib/sports/sport_type_config.dart` — Sport type definitions, board labels, scoring config
- `lib/views/tournament_view.dart` — Main tournament screen with tabbed navigation
- `lib/views/sport_selection_screen.dart` — Sport picker (controls which sports are enabled)
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

SQLite with schema version 14. Core tables:

| Table | Purpose |
|---|---|
| `CMP_TOURNAMENT` | Tournament metadata (name, dates, sport type, settings) |
| `CMP_PLAYER` | Player records (name, rating, patronymic for gender detection) |
| `CMP_TEAM` | Team records |
| `CMP_EVENT` | Match/game results and scheduling |
| `CMP_ENTITY` | Generic entity storage |

All tables have `sync_uid` column for cross-device synchronization.

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
- Only 4 of 14 sports have full dedicated implementations (chess, checkers, table tennis, swimming); the rest use the generic tournament flow
