# Arbi Chief

A cross-platform tournament management application built with Flutter for organizing and managing sports competitions. Designed for tournament arbiters and organizers to handle player registration, team composition, match scheduling, result tracking, and report generation.

## Features

- **Multi-Sport Support** — 14 sport types including chess, table tennis, checkers, volleyball, basketball, futsal, swimming, powerlifting, armwrestling, track & field, tennis, cycling, rope jumping, orienteering, and Go
- **Tournament Management** — Create, edit, and manage tournaments with stages and rounds
- **Player & Team Registration** — Maintain a database of players and teams, assign them to tournaments
- **Game Result Tracking** — Record match results with sport-specific scoring (e.g., set-by-set for table tennis)
- **Cross-Table Generation** — Automatic standings with individual player and team cross-tables per board/position
- **PDF Reports** — Generate and print tournament reports with full statistics
- **Search** — Search players and teams across the entire database with keyboard shortcut support

## Architecture

The project follows an **MVVM** pattern with Riverpod for state management:

```
lib/
├── main.dart                    # App entry point with Riverpod setup
├── models/                      # Data models (Tournament, Player, Team, Game, SportTypeConfig)
├── services/                    # Data access layer (SQLite database, CRUD operations)
├── viewmodels/                  # State management with Riverpod providers
└── views/                       # UI screens and widgets
```

### Key Components

| Layer | Description |
|-------|-------------|
| **Models** | `TournamentModel`, `PlayerModel`, `TeamModel`, `GameModel`, `SportTypeConfig` |
| **Services** | `DatabaseService` (SQLite), `TournamentService`, `PlayerService`, `TeamService` |
| **ViewModels** | Riverpod providers for tournaments, players, teams, navigation, and sport type state |
| **Views** | Sport selection, tournament list/edit, player/team management, reports, settings |

## Tech Stack

- **Flutter** (Dart SDK 3.7+)
- **Riverpod** 3.2 — Reactive state management and dependency injection
- **SQLite** (sqflite + sqflite_common_ffi) — Local database with schema migrations (v14)
- **PDF / Printing** — PDF generation and print preview
- **Material Design 3** — UI theming
- **Localization** — Ukrainian (uk) as primary locale

## Database

SQLite database with the following core tables:

- `CMP_TOURNAMENT_TYPE` — Sport type definitions
- `CMP_TOURNAMENT` — Tournament records
- `CMP_TOURNAMENT_STAGE` — Tournament rounds/stages
- `CMP_PLAYER` — Player database
- `CMP_TEAM` — Team database
- `CMP_PLAYER_TOURNAMENT` — Tournament participation links
- `CMP_PLAYER_TEAM` — Team membership links
- `CMP_EVENT` — Match/game events
- `CMP_ATTR` / `CMP_ATTR_VALUE` — Configurable tournament attributes

## Supported Platforms

- Android
- iOS
- Windows
- macOS
- Linux
- Web

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Dart 3.7+)

### Run the app

```bash
# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Run on a specific platform
flutter run -d windows
flutter run -d chrome
```

### Build

```bash
# Android APK
flutter build apk

# iOS
flutter build ios

# Windows desktop
flutter build windows
```

## Project Status

- **Version**: 1.0.0+1
- **Active development** with 60+ commits
- Uses `flutter_lints` for static analysis
