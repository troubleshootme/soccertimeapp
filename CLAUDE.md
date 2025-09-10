# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Development Commands

### Flutter Commands
- `flutter pub get` - Install dependencies
- `flutter run` - Run the app in development mode
- `flutter build apk` - Build Android APK
- `flutter clean` - Clean build files

### Testing & Analysis
- `flutter test` - Run tests
- `flutter analyze` - Analyze code for issues

## Architecture Overview

This is a Flutter soccer match timer application with the following key architectural patterns:

### State Management
- Uses **Provider** pattern with `AppState` as the main state provider
- State is centralized in `lib/providers/app_state.dart`
- UI components consume state via `Consumer<AppState>` widgets

### Data Storage
- **Hive** is used as the primary local database (NoSQL key-value store)
- Database operations handled via `HiveSessionDatabase` singleton class
- Stores sessions, players, settings, and session history
- All data persists locally on device

### Core Domain Models
- `Session` - Match configuration and state
- `Player` - Individual player data with timing
- `MatchLogEntry` - Event logging during matches
- `SessionSettings` - Match configuration settings

### Background Services
- `BackgroundService` - Keeps timer running when app is backgrounded
- Uses foreground service with notifications to prevent Android from killing the process
- Handles wake locks and battery optimization permissions

### Project Structure
```
lib/
  ├── models/           # Data models (Session, Player, MatchLogEntry)
  ├── providers/        # State management (AppState)
  ├── screens/          # UI screens (MainScreen, SettingsScreen, etc.)
  ├── services/         # Background services, audio, translation, PDF
  ├── widgets/          # Reusable UI components
  ├── utils/           # Helper functions and utilities
  ├── main.dart        # App entry point with error handling
  └── hive_database.dart # Database layer
```

## Key Features to Understand

### Timer System
- Match timer runs independently from player timers
- Player times accumulate only while they're marked as "active"
- Background service ensures timing continues when app is minimized
- Supports period-based matches (halves/quarters)

### Session Management
- Sessions can be created, loaded, and shared
- Session history automatically saved on match completion
- Backup/restore functionality to Downloads folder
- Read-only mode for viewing historical data

### Match Logging
- All match events logged with timestamps
- Exportable to text format for sharing
- Supports player substitutions, goals, period transitions

## Development Guidelines

### Code Style (from .cursor rules)
- Use **Provider** for state management (not riverpod as suggested in cursor rules)
- Follow Material Design 3 guidelines
- Prefer `StatelessWidget` when possible
- Use descriptive variable names with auxiliary verbs (isLoading, hasError)
- Use snake_case for files/directories, camelCase for variables/methods

### Error Handling
- Comprehensive error handling in `main.dart` with `ErrorHandler` class
- Graceful fallbacks for database initialization failures
- Proper lifecycle management for Hive database connections

### Permissions
- Requires notification permissions for background service
- Battery optimization exemption for background timing
- Full storage access (`MANAGE_EXTERNAL_STORAGE`) for backup/restore

## Testing Notes
- No specific test framework commands found in project
- Uses standard Flutter testing approach with `flutter test`
- Focus on state management and timer accuracy when testing

## Important Implementation Details
- Timer drift prevention through careful background sync
- Proper handling of app lifecycle (pause/resume) states  
- Period transition logic with exact timing calculations
- Translation service for internationalization support