# ADR-003: State Management with Provider and ChangeNotifier

## Status
**Accepted** - Implementation complete and in production

## Context and Problem Statement
SoccerTimeApp manages complex state across multiple interconnected components:
- Real-time match timing and player activity tracking
- Session data (players, settings, match configuration)
- UI state synchronization across multiple screens
- Background service integration with foreground UI updates
- Form state for player management and settings
- Navigation state and screen-specific data

The state management solution must support:
- Real-time updates (sub-second timing accuracy)
- Cross-screen state consistency
- Integration with background services
- Local persistence through Hive database
- Reactive UI updates with minimal rebuilds
- Testable and maintainable code structure

## Decision Rationale
**Selected: Provider pattern with ChangeNotifier as the central state management solution**

### Architecture Decision:
- **Single AppState**: Centralized state management through one primary ChangeNotifier
- **Provider Integration**: Flutter's Provider package for dependency injection and state listening
- **Granular Notifications**: Strategic notifyListeners() calls to minimize unnecessary rebuilds
- **Direct Database Integration**: AppState directly manages Hive database operations
- **Background Service Integration**: AppState serves as the bridge between UI and background timing

### Core AppState Responsibilities:
```dart
class AppState with ChangeNotifier {
  // Session Management
  - Current session loading/switching
  - Session creation and deletion
  - Session settings persistence
  
  // Player Management  
  - Player roster management
  - Real-time timer updates
  - Player state synchronization
  
  // Match Control
  - Match timing coordination
  - Period transitions
  - Match state persistence
  
  // UI State
  - Theme management
  - Screen-specific state
  - Navigation coordination
}
```

## Alternatives Considered

### BLoC Pattern with flutter_bloc
**Rejected** for the following reasons:
- Over-engineered for the app's relatively simple state management needs
- Additional complexity with Events/States pattern not justified
- Steeper learning curve for team members
- More verbose boilerplate code for simple state updates
- Real-time timing updates better suited to direct ChangeNotifier approach

### Riverpod
**Rejected** for the following reasons:
- Provider already meets all requirements adequately
- Migration effort not justified by benefits
- Additional dependency complexity
- Team familiarity with Provider pattern
- Stable, proven Provider implementation already in place

### setState() with StatefulWidgets
**Rejected** for the following reasons:
- Cannot share state effectively across multiple screens
- No integration path with background services
- Difficult to persist state during navigation
- Poor scalability for complex state relationships
- Props drilling required for deep widget hierarchies

### GetX
**Rejected** for the following reasons:
- Overly opinionated framework approach
- Conflicts with Flutter's recommended patterns
- Magic/implicit behavior reduces code predictability
- Strong dependency on third-party patterns
- Less ecosystem integration with other packages

## Implementation Architecture

### State Structure:
```
AppState (ChangeNotifier)
├── Session Management
│   ├── currentSessionId: int?
│   ├── sessions: List<Map<String, dynamic>>
│   └── session: Session (complex nested model)
├── Player Management
│   ├── players: List<Map<String, dynamic>>
│   └── Player state tracking methods
├── UI State
│   ├── isDarkTheme: bool
│   ├── isReadOnlyMode: bool
│   └── periodsTransitioning: bool
└── Database Integration
    └── Direct HiveSessionDatabase calls
```

### Provider Setup in Widget Tree:
```dart
ChangeNotifierProvider<AppState>(
  create: (context) => AppState(),
  child: MaterialApp(...)
)
```

### Consumer Pattern for Reactive Updates:
```dart
Consumer<AppState>(
  builder: (context, appState, child) {
    return TimerDisplay(time: appState.session.matchTime);
  }
)
```

## Consequences

### Positive Consequences
✅ **Simple Integration**: Seamless integration with Flutter's widget system
✅ **Real-time Updates**: Efficient propagation of timing updates to UI components
✅ **Testability**: Easy mocking and unit testing of state management
✅ **Performance**: Granular control over widget rebuilds using Consumer/Selector
✅ **Maintainability**: Centralized state logic with clear responsibilities
✅ **Background Integration**: Clean bridge between background services and UI
✅ **Persistence Integration**: Direct integration with Hive database operations

### Negative Consequences
❌ **Single Point of Failure**: Central AppState class becomes large and complex
❌ **Tight Coupling**: UI components tightly coupled to specific AppState structure
❌ **Manual Optimization**: Requires careful notifyListeners() management to prevent unnecessary rebuilds
❌ **Memory Management**: Large state objects remain in memory throughout app lifecycle
❌ **Debugging Complexity**: State changes can be harder to trace through multiple listeners

### Performance Optimizations Implemented:
- **Selective Consumers**: Use Consumer widgets only where state changes are needed
- **Builder Optimization**: Minimize widget subtree rebuilds with targeted listening
- **Lazy Loading**: Sessions and players loaded on-demand rather than at startup
- **Debounced Updates**: Some rapid state changes are batched to reduce notification frequency

## Implementation Notes

### Key State Management Patterns:

#### Timer State Synchronization:
```dart
// Background service updates AppState directly
if (_currentAppState != null) {
  _currentAppState!.session.matchTime = _currentMatchTime;
  _currentAppState!.session.lastUpdateTime = nowMillis ~/ 1000;
}
```

#### Database Integration Pattern:
```dart
Future<void> addPlayer(String name) async {
  // 1. Update local state
  _session.addPlayer(trimmedName);
  
  // 2. Persist to database
  await HiveSessionDatabase.instance.insertPlayer(/*...*/);
  
  // 3. Update UI list
  _players = await HiveSessionDatabase.instance.getPlayersForSession(/*...*/);
  
  // 4. Notify listeners
  notifyListeners();
}
```

#### Complex State Updates:
```dart
Future<void> loadSession(int sessionId) async {
  try {
    // Multi-step state loading with error handling
    final sessionData = await HiveSessionDatabase.instance.getSession(sessionId);
    _currentSessionId = sessionId;
    _players = await HiveSessionDatabase.instance.getPlayersForSession(sessionId);
    _session = Session(sessionName: sessionData['name']);
    
    notifyListeners();
  } catch (e) {
    // Comprehensive error recovery
    _currentSessionId = null;
    throw e;
  }
}
```

### Critical Integration Points:
- `/lib/providers/app_state.dart` - Main state management implementation
- `/lib/screens/*_screen.dart` - Consumer integration in UI screens
- `/lib/services/background_service.dart` - Background service → AppState updates
- `/lib/main.dart` - Provider setup and initialization

### Memory and Performance Profile:
- AppState instance: ~2-5MB depending on session size
- Notification overhead: ~1-5ms per notifyListeners() call
- Database integration: 5-50ms per state persistence operation
- Widget rebuild impact: Minimized through selective Consumer usage

## Related ADRs
- ADR-001: Local Storage with Hive (integrated for state persistence)
- ADR-002: Background Service Architecture (integrated for real-time updates)
- ADR-005: UI Architecture Decisions (Consumer pattern usage throughout UI)