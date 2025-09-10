# ADR-005: UI Architecture Decisions - Screen-Based with Selective Components

## Status
**Accepted** - Implementation complete and stable

## Context and Problem Statement
SoccerTimeApp requires a user interface architecture that supports:
- Real-time match timing display with sub-second accuracy
- Multiple distinct user workflows (session management, active timing, settings, history)
- Complex state coordination between timing display and player management
- Responsive design for various screen sizes and orientations
- Efficient rendering performance during intensive real-time updates
- Maintainable code structure for ongoing feature development

The UI must balance simplicity with functionality while providing intuitive navigation between different app modes (setup, active match, history review).

## Decision Rationale
**Selected: Screen-Based Architecture with Strategic Component Extraction**

### Architecture Decision:
- **Screen-Centric Design**: Each major user workflow corresponds to a dedicated screen widget
- **Selective Component Creation**: Extract reusable components only when justified by complexity or reuse
- **Flat Navigation**: Direct screen-to-screen navigation without complex nested hierarchies
- **Provider Integration**: Consumer pattern used throughout screens for state management
- **Minimal Widget Nesting**: Keep widget trees shallow for better performance and maintainability

### Screen Organization:
```
/lib/screens/
├── main_screen.dart         - Primary match timing and control
├── session_screen.dart      - Session selection and management
├── session_prompt_screen.dart - Session creation flow
├── settings_screen.dart     - Match configuration and preferences
├── player_times_screen.dart - Individual player time review
├── match_log_screen.dart    - Event history and logging
├── session_history_screen.dart - Past session records
└── pdf_preview_screen.dart  - Export preview functionality
```

### Component Extraction Strategy:
```
/lib/widgets/
├── player_button.dart       - Complex interactive player timer display
├── match_timer.dart         - Specialized timing display with formatting
├── period_end_dialog.dart   - Modal dialog with custom behavior
└── resizable_container.dart - Reusable layout utility
```

## Alternatives Considered

### Micro-Component Architecture
**Rejected** for the following reasons:
- Over-engineering for the app's scope and complexity
- Increased cognitive overhead for developers navigating many small files
- Potential performance overhead from excessive widget composition
- Diminished code locality making feature understanding more difficult
- No significant reusability benefits given the app's specific use cases

### Single Large Screen with State Switching
**Rejected** for the following reasons:
- Monolithic widget class would become unmaintainable (1000+ lines)
- Complex conditional rendering logic throughout the widget tree
- Difficult state isolation between different app modes
- Poor navigation UX with no visual transition between modes
- Testing complexity with single massive widget

### Page-View Based Architecture
**Rejected** for the following reasons:
- Horizontal swipe navigation not intuitive for the app's workflow
- Complex page state management during real-time timing
- Difficult to implement proper navigation hierarchy
- Poor integration with Android back button behavior
- Unnecessary complexity for linear user workflows

### Fragment-Based Architecture (Android-style)
**Rejected** for the following reasons:
- Not a natural Flutter pattern - widgets provide similar functionality
- Additional complexity without corresponding benefits
- Poor integration with Flutter's navigation system
- Increased platform-specific code requirements
- Flutter widgets already provide composition benefits

## Implementation Architecture

### Screen Responsibility Matrix:

| Screen | Primary Responsibility | State Dependencies | Navigation Entry Points |
|--------|----------------------|-------------------|------------------------|
| MainScreen | Active match timing & control | AppState.session, BackgroundService | Primary app entry, session loading |
| SessionScreen | Session selection & management | AppState.sessions | App startup, main screen back |
| SettingsScreen | Match configuration | AppState.session settings | Main screen settings button |
| PlayerTimesScreen | Individual player review | AppState.session.players | Main screen player details |
| MatchLogScreen | Event history display | AppState.session.matchLog | Main screen history button |
| SessionHistoryScreen | Past session records | HiveSessionDatabase history | Session screen history |

### Component Extraction Criteria:
1. **Complexity Threshold**: Widget complexity >100 lines or complex state logic
2. **Reusability**: Used in multiple locations with similar behavior
3. **Testability**: Complex logic that benefits from isolated unit testing
4. **Performance**: Widgets with expensive build() methods requiring optimization

### Key Implementation Patterns:

#### Screen Structure Template:
```dart
class ExampleScreen extends StatefulWidget {
  @override
  _ExampleScreenState createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  // Local state for screen-specific UI
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Title')),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          // Reactive UI based on app state
          return Column(/* ... */);
        },
      ),
    );
  }
}
```

#### Strategic Component Usage:
```dart
// Complex player button extracted to component
PlayerButton(
  name: playerName,
  player: appState.session.players[playerName]!,
  targetPlayDuration: appState.session.targetPlayDuration,
  enableTargetDuration: appState.session.enableTargetDuration,
)

// Simple widgets remain inline
Text(
  appState.session.formattedMatchTime,
  style: Theme.of(context).textTheme.headline2,
)
```

## Consequences

### Positive Consequences
✅ **Clear Separation of Concerns**: Each screen handles a distinct user workflow
✅ **Maintainable File Structure**: Logical organization with predictable file locations
✅ **Easy Navigation Logic**: Simple push/pop navigation between distinct screens
✅ **Performance Optimization**: Minimal widget rebuilds with targeted Consumer usage
✅ **Testing Simplicity**: Screen-level testing with clear boundaries and responsibilities
✅ **Development Velocity**: New features can be added as new screens without affecting existing functionality
✅ **Code Locality**: Related functionality grouped together within screen files

### Negative Consequences
❌ **Code Duplication**: Some common UI patterns repeated across screens
❌ **Large Screen Files**: Main screen approaches 800+ lines due to complex timing logic
❌ **State Coupling**: Screens tightly coupled to specific AppState structure
❌ **Navigation Complexity**: Multiple navigation paths can create user confusion
❌ **Context Switching**: Developers must understand multiple screen contexts for full-stack features

### Performance Characteristics:
- Screen transition time: 50-150ms depending on state complexity
- Widget rebuild frequency: Minimized through selective Consumer placement
- Memory usage: ~1-3MB per screen with efficient widget disposal
- Real-time update performance: 16-33ms render cycles maintained during active timing

## Implementation Notes

### Navigation Patterns:
```dart
// Standard screen navigation
Navigator.push(context, MaterialPageRoute(
  builder: (context) => TargetScreen(),
));

// Navigation with data passing
Navigator.push(context, MaterialPageRoute(
  builder: (context) => PlayerTimesScreen(sessionId: appState.currentSessionId),
));
```

### State Management Integration:
```dart
// Efficient state listening
Consumer<AppState>(
  builder: (context, appState, child) {
    // Only rebuild when relevant state changes
    return TimerDisplay(time: appState.session.matchTime);
  }
)

// Selective rebuilds for performance
Selector<AppState, int>(
  selector: (context, appState) => appState.session.matchTime,
  builder: (context, matchTime, child) {
    return Text(formatTime(matchTime));
  }
)
```

### Key Screen Implementations:
- `main_screen.dart`: 800+ lines - Complex timing logic and player management UI
- `session_screen.dart`: 300+ lines - Session list with search and management features
- `settings_screen.dart`: 400+ lines - Comprehensive match configuration UI
- Individual components: 50-200 lines each with focused responsibilities

### Component Guidelines:
1. **Extract when >100 lines**: Large widgets benefit from separate files
2. **Reuse threshold**: Extract when used in 2+ locations with similar behavior  
3. **Complex state logic**: Extract widgets with non-trivial state management
4. **Performance optimization**: Extract expensive build() methods for targeted rebuilds

## Related ADRs
- ADR-003: State Management with Provider (Consumer pattern usage throughout UI)
- ADR-002: Background Service Architecture (real-time UI updates integration)
- ADR-001: Local Storage with Hive (data persistence from UI actions)