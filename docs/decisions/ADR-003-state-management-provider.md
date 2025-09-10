# ADR-003: State Management with Provider and ChangeNotifier

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires reactive state management that can handle:
- Real-time timer updates (multiple timers updating frequently)
- Complex match state (sessions, players, settings, match log)
- Background service coordination (timer synchronization)
- UI responsiveness (immediate updates across multiple screens)
- Data persistence (automatic saving of state changes)

### Requirements
- **Real-Time Updates**: Sub-second UI updates for timer displays
- **State Coordination**: Synchronize between background service and UI
- **Reactive UI**: Automatic UI updates when state changes
- **Performance**: Minimize unnecessary widget rebuilds
- **Simplicity**: Maintainable state management without excessive complexity
- **Testing**: Mockable and testable state management

### Current Implementation Analysis
The app uses a centralized `AppState` class extending `ChangeNotifier` with the Provider pattern:
- Single source of truth for all application state
- Direct integration with background service for timer updates
- Automatic UI updates through `Consumer` and `Selector` widgets
- Built-in persistence to Hive database

## Decision

**Chosen**: Provider Pattern with Centralized AppState using ChangeNotifier

### Implementation Architecture
```dart
class AppState with ChangeNotifier {
  // Core state
  models.Session _session = models.Session();
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _players = [];
  int? _currentSessionId;
  
  // State accessors with getters
  models.Session get session => _session;
  List<Map<String, dynamic>> get sessions => _sessions;
  
  // State mutators with notifications
  Future<void> addPlayer(String name) async {
    _session.addPlayer(name);
    await saveSession();
    notifyListeners(); // Triggers UI updates
  }
}
```

### Provider Integration Pattern
```dart
// App-level provider setup
ChangeNotifierProvider(
  create: (context) => AppState(),
  child: SoccerTimeApp(),
)

// Consumer usage for reactive UI
Consumer<AppState>(
  builder: (context, appState, child) => 
    TimerDisplay(appState.session.matchTime),
)

// Selector for performance optimization
Selector<AppState, int>(
  selector: (context, appState) => appState.session.matchTime,
  builder: (context, matchTime, child) => Text(formatTime(matchTime)),
)
```

## Rationale

### Real-Time Performance Analysis
The timer system requires frequent state updates:
- **Match Timer**: Updates every 1-2 seconds
- **Player Timers**: Individual player time tracking
- **Period Transitions**: State changes at period boundaries
- **Background Sync**: Coordination with background service

Provider/ChangeNotifier provides:
- **O(1) Notification**: Efficient listener notification
- **Granular Updates**: Selective widget rebuilding with Selector
- **Automatic Disposal**: Framework handles listener cleanup

### Centralized State Benefits
Single AppState approach provides:
- **Consistency**: Single source of truth prevents state inconsistencies
- **Coordination**: Easy coordination between timers, players, and UI
- **Persistence**: Centralized save logic ensures data consistency
- **Testing**: Single object to mock for comprehensive testing

### Flutter Integration Advantages
- **Framework Native**: Built into Flutter with optimized performance
- **Reactive Widgets**: Consumer/Selector widgets provide automatic updates
- **Development Tools**: Excellent debugging support with Flutter Inspector
- **Learning Curve**: Familiar pattern for Flutter developers

## Alternatives Considered

### BLoC (Business Logic Components)
**Rejected** - Reasons:
- **Complexity**: Excessive boilerplate for simple state management needs
- **Stream Overhead**: Stream-based architecture adds unnecessary complexity
- **Real-Time Performance**: Additional layer may impact timer update performance
- **Learning Curve**: Higher complexity than needed for team expertise level

```dart
// BLoC would require complex event/state mapping:
class TimerBloc extends Bloc<TimerEvent, TimerState> {
  TimerBloc() : super(TimerInitial()) {
    on<TimerStarted>(_onTimerStarted);
    on<TimerTicked>(_onTimerTicked);
    // ... extensive boilerplate for simple operations
  }
}
```

### Riverpod
**Rejected** - Reasons:
- **Migration Cost**: Would require refactoring existing Provider-based code
- **Added Complexity**: Code generation and additional concepts
- **Team Familiarity**: Team already proficient with Provider pattern
- **Stable Foundation**: Provider pattern working well for current requirements

### GetX
**Rejected** - Reasons:
- **Framework Lock-in**: Heavy dependency on GetX ecosystem
- **Flutter Integration**: Less integrated with Flutter's reactive architecture
- **Debugging**: Limited debugging tools compared to Provider
- **Community**: Smaller community and ecosystem than Provider

### Redux/Flutter Redux
**Rejected** - Reasons:
- **Overkill**: Time-travel debugging and immutability not needed
- **Boilerplate**: Excessive code for simple state operations
- **Performance**: Immutable state copying could impact real-time updates
- **Complexity**: Action/reducer pattern adds unnecessary complexity

### MobX
**Rejected** - Reasons:
- **Code Generation**: Requires build runner and generated code
- **Debugging**: Less transparent than ChangeNotifier for debugging
- **Flutter Integration**: Not as tightly integrated as Provider
- **Performance**: Observable overhead for frequent timer updates

### Plain setState
**Rejected** - Reasons:
- **State Sharing**: Difficult to share state across multiple widgets
- **Coordination**: No mechanism for background service state coordination
- **Performance**: Full widget tree rebuilds for any state change
- **Testing**: Difficult to test state logic without UI

## Consequences

### Positive
- **Excellent Performance**: ChangeNotifier optimized for frequent updates
- **Simple Mental Model**: Easy to understand and debug state flow
- **Efficient UI Updates**: Selector widgets minimize unnecessary rebuilds
- **Background Integration**: Seamless coordination with background service
- **Testing Friendly**: Easy to mock AppState for unit testing
- **Flutter Native**: Leverages framework's reactive architecture
- **Developer Productivity**: Familiar patterns with minimal boilerplate

### Negative
- **Centralized State**: Large AppState class with multiple responsibilities (1,616 lines)
- **Coupling**: UI tightly coupled to single state object
- **Global State**: All state accessible globally, potential for misuse
- **Memory Usage**: All state kept in memory (acceptable for app's data size)

### Neutral
- **Scalability**: May need decomposition for larger applications (planned refactoring)
- **State Granularity**: Some unnecessary rebuilds due to coarse-grained notifications

## Implementation Details

### State Update Patterns
```dart
// Synchronous state updates
void togglePlayer(String name) {
  _session.togglePlayerActive(name);
  notifyListeners(); // Immediate UI update
}

// Asynchronous state updates with persistence
Future<void> addPlayer(String name) async {
  _session.addPlayer(name);
  await saveSession(); // Persist to database
  notifyListeners(); // UI update after persistence
}
```

### Background Service Integration
```dart
// Background service updates AppState directly
class BackgroundService {
  AppState? _appState;
  
  void updateMatchTime(int newTime) {
    _appState?.updateMatchTime(newTime);
    // AppState handles UI notifications
  }
}
```

### Performance Optimizations
```dart
// Use Selector for granular updates
Selector<AppState, List<Player>>(
  selector: (context, appState) => appState.session.players.values.toList(),
  builder: (context, players, child) => PlayerList(players),
  shouldRebuild: (previous, next) => 
    !listEquals(previous, next), // Custom equality check
)

// ValueListenableBuilder for high-frequency updates
ValueListenableBuilder<int>(
  valueListenable: _matchTimeNotifier,
  builder: (context, matchTime, child) => TimerDisplay(matchTime),
)
```

### State Persistence Integration
```dart
Future<void> saveSession() async {
  // Persist state changes to Hive database
  await HiveSessionDatabase.instance.saveSessionSettings(_currentSessionId!, {
    'enableMatchDuration': _session.enableMatchDuration,
    'matchDuration': _session.matchDuration,
    // ... other settings
  });
  
  // No notifyListeners() here - caller handles UI updates
}
```

## Testing Strategy

### Unit Testing
```dart
// Mock AppState for business logic testing
class MockAppState extends Mock implements AppState {}

test('player addition updates session', () async {
  final appState = AppState();
  await appState.addPlayer('John Doe');
  
  expect(appState.session.players.containsKey('John Doe'), true);
});
```

### Widget Testing
```dart
// Test UI updates with ChangeNotifierProvider
testWidgets('timer display updates when state changes', (tester) async {
  final appState = AppState();
  
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(home: TimerDisplay()),
    ),
  );
  
  appState.updateMatchTime(90);
  await tester.pump();
  
  expect(find.text('01:30'), findsOneWidget);
});
```

### Performance Testing
- **Rebuild Monitoring**: Track widget rebuild frequency during timer updates
- **Memory Profiling**: Monitor memory usage during long matches
- **State Update Performance**: Measure notification and UI update latency

## Migration Considerations

### Future Refactoring Plans
Given the technical debt analysis identifying the 1,616-line AppState class, future improvements may include:

1. **State Decomposition**
   ```dart
   // Split into focused providers
   MultiProvider(
     providers: [
       ChangeNotifierProvider<SessionState>(create: (_) => SessionState()),
       ChangeNotifierProvider<PlayerState>(create: (_) => PlayerState()),
       ChangeNotifierProvider<TimerState>(create: (_) => TimerState()),
     ],
   )
   ```

2. **Provider Composition**
   - Maintain Provider pattern while decomposing state
   - Use ProxyProvider for state coordination
   - Preserve reactive UI patterns

## Related ADRs
- [ADR-002](./ADR-002-background-service-architecture.md): Background service integrates with AppState
- [ADR-001](./ADR-001-local-storage-hive.md): State persistence through Hive database
- [ADR-005](./ADR-005-ui-architecture-decisions.md): UI architecture leverages Provider pattern
- [ADR-006](./ADR-006-service-layer-organization.md): Service layer coordinates through AppState

## Review Notes
The Provider/ChangeNotifier pattern effectively serves the app's real-time state management needs. While the centralized AppState approach has led to a large class, the reactive architecture and performance characteristics are well-suited for the timer-centric application. Future decomposition can maintain the pattern while improving maintainability.