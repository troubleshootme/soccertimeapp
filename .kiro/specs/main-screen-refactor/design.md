# Design Document

## Overview

The main_screen.dart refactoring will decompose the monolithic 3800+ line file into a coordinated set of specialized components. The design follows Flutter's composition-over-inheritance principle and separates concerns into logical, testable units while maintaining all existing functionality.

## Architecture

### Component Hierarchy

```
MainScreen (Coordinator - <500 lines)
├── MatchTimerWidget (Timer Management)
├── PlayerManagementWidget (Player Operations)
├── MatchControlsWidget (Play/Pause/Reset Controls)
├── SessionInfoWidget (Session Display)
├── MatchTimeDisplayWidget (Time Display)
└── Services (Extracted Logic)
    ├── DialogService (Dialog Management)
    ├── NotificationService (Snackbar Management)
    └── LifecycleService (App Lifecycle Management)
```

### Design Principles

1. **Single Responsibility**: Each component handles one specific aspect of functionality
2. **Composition**: Components are composed together rather than inheriting complex behavior
3. **State Isolation**: Each component manages its own internal state while coordinating through the main AppState
4. **Service Extraction**: Complex logic is moved to dedicated service classes
5. **Backward Compatibility**: All existing functionality and user experience remains unchanged

## Components and Interfaces

### 1. MainScreen (Coordinator)

**Responsibility**: Orchestrate components and handle high-level state coordination

**Key Methods**:
- `initState()` - Initialize components and services
- `dispose()` - Clean up components and services
- `build()` - Compose child components

**State Variables** (Reduced):
- Component references
- High-level coordination flags

### 2. MatchTimerWidget

**Responsibility**: All timer-related functionality including background service integration

**Interface**:
```dart
class MatchTimerWidget extends StatefulWidget {
  final ValueNotifier<int> matchTimeNotifier;
  final VoidCallback? onPeriodEnd;
  final VoidCallback? onMatchEnd;
  final VoidCallback? onTimeUpdate;
  
  const MatchTimerWidget({
    required this.matchTimeNotifier,
    this.onPeriodEnd,
    this.onMatchEnd,
    this.onTimeUpdate,
  });
}
```

**Key Methods**:
- `startTimer()` - Start match timer with background service
- `stopTimer()` - Pause timer
- `resetTimer()` - Reset to zero
- `_onTimeUpdate()` - Handle background service time updates
- `_checkPeriodEnd()` - Monitor for period transitions
- `_checkMatchEnd()` - Monitor for match completion

**State Variables**:
- `Timer? _matchTimer`
- `bool _isPaused`
- `BackgroundService _backgroundService`
- Drift compensation variables

### 3. PlayerManagementWidget

**Responsibility**: Player list display, adding, removing, and player time management

**Interface**:
```dart
class PlayerManagementWidget extends StatefulWidget {
  final bool isTableExpanded;
  final VoidCallback onToggleExpansion;
  final FocusNode addPlayerFocusNode;
  
  const PlayerManagementWidget({
    required this.isTableExpanded,
    required this.onToggleExpansion,
    required this.addPlayerFocusNode,
  });
}
```

**Key Methods**:
- `_showAddPlayerDialog()` - Display add player interface
- `_togglePlayerByName()` - Toggle player active state
- `_showPlayerActionsDialog()` - Show player-specific actions
- `_removePlayer()` - Remove player with confirmation
- `_editPlayer()` - Edit player name
- `_resetPlayerTime()` - Reset individual player time

**State Variables**:
- Player list state
- Expansion state
- Focus management

### 4. MatchControlsWidget

**Responsibility**: Play/pause/reset controls and match state management

**Interface**:
```dart
class MatchControlsWidget extends StatefulWidget {
  final bool isPaused;
  final bool isSetup;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onReset;
  final VoidCallback? onEndMatch;
  
  const MatchControlsWidget({
    required this.isPaused,
    required this.isSetup,
    required this.onTogglePlayPause,
    required this.onReset,
    this.onEndMatch,
  });
}
```

**Key Methods**:
- `_buildPlayPauseButton()` - Render play/pause control
- `_buildResetButton()` - Render reset control
- `_buildEndMatchButton()` - Render end match control
- `_validateMatchStart()` - Check if match can start

### 5. SessionInfoWidget

**Responsibility**: Display session name and match information

**Interface**:
```dart
class SessionInfoWidget extends StatelessWidget {
  final String sessionName;
  final int currentPeriod;
  final int totalPeriods;
  final bool isDark;
  
  const SessionInfoWidget({
    required this.sessionName,
    required this.currentPeriod,
    required this.totalPeriods,
    required this.isDark,
  });
}
```

### 6. MatchTimeDisplayWidget

**Responsibility**: Display match time with proper formatting and styling

**Interface**:
```dart
class MatchTimeDisplayWidget extends StatelessWidget {
  final ValueNotifier<int> matchTimeNotifier;
  final bool isPaused;
  final bool isDark;
  
  const MatchTimeDisplayWidget({
    required this.matchTimeNotifier,
    required this.isPaused,
    required this.isDark,
  });
}
```

## Data Models

### Component Communication

Components communicate through:

1. **AppState Provider**: Shared application state
2. **Callback Functions**: Parent-to-child communication for actions
3. **ValueNotifiers**: Reactive updates for frequently changing data (like match time)
4. **Service Interfaces**: Shared services for cross-cutting concerns

### State Management Strategy

- **Local State**: Each component manages its own UI state
- **Shared State**: AppState provider for application-wide state
- **Service State**: Services maintain their own internal state
- **Reactive Updates**: ValueNotifiers for high-frequency updates

## Error Handling

### Component-Level Error Handling

Each component implements:
- Null safety checks
- Mounted widget validation
- Graceful degradation for service failures
- Error boundaries for isolated failures

### Service-Level Error Handling

Services implement:
- Try-catch blocks for external operations
- Fallback mechanisms for service failures
- Error logging and reporting
- State recovery mechanisms

## Testing Strategy

### Unit Testing

1. **Component Tests**: Test each widget component in isolation
2. **Service Tests**: Test service logic independently
3. **State Tests**: Test state management and transitions
4. **Integration Tests**: Test component interactions

### Widget Testing

1. **Component Rendering**: Verify each component renders correctly
2. **User Interactions**: Test button presses and user inputs
3. **State Changes**: Verify UI updates with state changes
4. **Callback Execution**: Test parent-child communication

### Integration Testing

1. **Full Screen Tests**: Test complete main screen functionality
2. **Service Integration**: Test background service integration
3. **State Synchronization**: Test state consistency across components
4. **Performance Tests**: Verify no performance regression

## Migration Strategy

### Phase 1: Extract Services
- Create DialogService for dialog management
- Create NotificationService for snackbar management
- Create LifecycleService for app lifecycle management

### Phase 2: Extract Timer Component
- Move all timer-related logic to MatchTimerWidget
- Maintain background service integration
- Test timer functionality thoroughly

### Phase 3: Extract Player Management
- Move player operations to PlayerManagementWidget
- Maintain all existing player functionality
- Test player interactions

### Phase 4: Extract UI Components
- Create MatchControlsWidget for controls
- Create SessionInfoWidget for session display
- Create MatchTimeDisplayWidget for time display

### Phase 5: Refactor Main Screen
- Reduce MainScreen to coordination logic only
- Compose all extracted components
- Verify complete functionality

### Phase 6: Testing and Validation
- Comprehensive testing of all components
- Performance validation
- User experience verification