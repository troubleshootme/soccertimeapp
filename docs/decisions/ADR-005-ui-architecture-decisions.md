# ADR-005: UI Architecture - Screen-Based with Selective Components

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires a UI architecture that supports:
- Real-time timer updates across multiple screens
- Complex match management interface with many controls
- Responsive design for various Android screen sizes
- Maintainable code structure for team development
- Performance optimization for frequent UI updates

### Requirements
- **Real-Time Updates**: Timer displays must update sub-second
- **Complex Interactions**: Match controls, player management, settings
- **Navigation**: Multiple screens with state preservation
- **Performance**: Smooth 60fps during timer operations
- **Maintainability**: Clear code organization for team development
- **Testability**: Components must be testable in isolation

### Current Implementation Analysis
The app uses a hybrid screen-based architecture with strategic component extraction:
- 8 main screens handling primary use cases
- Selective component extraction for complex/reusable UI elements
- Screen-centric navigation with preserved state
- Direct Provider integration for real-time updates

## Decision

**Chosen**: Screen-Based Architecture with Selective Component Extraction

### Architecture Overview
```
lib/screens/          # Primary screen-based navigation
├── main_screen.dart           # 3,812 lines - Primary match interface
├── session_prompt_screen.dart # Session selection and creation  
├── session_screen.dart        # Individual session management
├── settings_screen.dart       # Application configuration
├── match_log_screen.dart      # Match event history
├── player_times_screen.dart   # Player statistics and timing
├── session_history_screen.dart# Historical match review
└── pdf_preview_screen.dart    # PDF export preview

lib/widgets/          # Extracted reusable components
├── match_timer.dart           # Timer display component
├── player_button.dart         # Player interaction controls
├── period_end_dialog.dart     # Match event dialogs
└── resizable_container.dart   # UI layout utilities
```

### Navigation Pattern
```dart
// Screen-based routing with preserved state
MaterialApp(
  routes: {
    '/': (context) => SessionPromptScreen(),
    '/main': (context) => MainScreen(),
    '/settings': (context) => SettingsScreen(),
    '/session_history': (context) => SessionHistoryScreen(),
  },
)
```

## Rationale

### Screen-Centric Design Benefits
The 8-screen approach provides:
- **Clear Mental Model**: Each screen represents a distinct user workflow
- **State Locality**: Screen-specific state kept close to usage
- **Navigation Simplicity**: Simple route-based navigation
- **Code Locality**: Related functionality grouped in single files
- **Team Development**: Different screens can be developed independently

### Selective Component Strategy
Rather than micro-components, strategic extraction focuses on:
- **Reusable Elements**: Components used across multiple screens
- **Complex Logic**: UI elements with sophisticated behavior
- **Performance Critical**: Components requiring optimization (timers)
- **Testing Isolation**: Components that need independent testing

### Real-Time Integration Pattern
```dart
// Direct Provider integration in screens
Consumer<AppState>(
  builder: (context, appState, child) => Column(
    children: [
      TimerDisplay(appState.session.matchTime),
      PlayerList(appState.session.players),
      MatchControls(appState.session.matchRunning),
    ],
  ),
)
```

## Alternatives Considered

### Micro-Component Architecture
**Rejected** - Reasons:
- **Over-Engineering**: 50+ micro-components for relatively simple UI
- **Indirection Overhead**: Complex component hierarchies reduce code clarity
- **State Complexity**: Prop drilling and complex state passing
- **Development Overhead**: Excessive file switching for simple changes
- **Team Complexity**: Higher learning curve for new developers

```dart
// Micro-component approach would create excessive hierarchy:
MatchScreen(
  children: [
    MatchHeader(child: TimerSection(child: TimerDisplay())),
    MatchBody(children: [
      PlayerSection(children: [
        PlayerList(children: [
          PlayerItem(child: PlayerButton()),
          // ... excessive nesting
        ])
      ])
    ])
  ]
)
```

### Single Page Application (SPA)
**Rejected** - Reasons:
- **Code Concentration**: Single massive widget tree (4000+ lines)
- **State Management**: All UI state in single component
- **Navigation**: Complex conditional rendering for different views
- **Performance**: Full UI rebuild for navigation changes
- **Team Development**: Merge conflicts and parallel development issues

### Native Android Architecture (Activities/Fragments)
**Rejected** - Reasons:
- **Flutter Integration**: Complex Flutter-to-native communication
- **State Synchronization**: Difficult state sharing between native and Flutter
- **Development Complexity**: Two separate UI systems to maintain
- **Platform Coupling**: iOS implementation completely different
- **Flutter Benefits Lost**: Loses Flutter's reactive UI benefits

### BLoC-based Component Architecture
**Rejected** - Reasons:
- **Over-Engineering**: BLoC pattern adds complexity for simple UI operations
- **Real-Time Performance**: Additional layers may impact timer update performance
- **Team Familiarity**: Team comfortable with Provider/ChangeNotifier patterns
- **Boilerplate**: Excessive code for simple UI state management

### Page-based Architecture (PageView)
**Rejected** - Reasons:
- **Navigation Limitations**: Swipe-based navigation doesn't match app UX goals
- **State Preservation**: Complex state management across pages
- **Screen Size Issues**: Poor utilization of available screen space
- **User Experience**: Doesn't match expected soccer app interaction patterns

## Consequences

### Positive
- **Clear Organization**: Easy to understand code structure
- **Development Speed**: Rapid development of new screens/features
- **State Locality**: Screen-specific state kept close to usage
- **Navigation Simplicity**: Standard Flutter navigation patterns
- **Team Productivity**: Multiple developers can work on different screens
- **Code Reuse**: Strategic component extraction where beneficial
- **Performance**: Direct Provider integration for real-time updates
- **Testability**: Screens and components can be tested independently

### Negative
- **Large Screen Files**: MainScreen at 3,812 lines requires refactoring
- **Code Duplication**: Some UI patterns repeated across screens
- **Tight Coupling**: Some screens tightly coupled to AppState
- **Complex Screens**: Match management screen handles multiple concerns

### Neutral
- **Component Extraction**: Ongoing process as components prove reusable
- **Refactoring Opportunities**: Large screens can be decomposed incrementally
- **Navigation Evolution**: May evolve to nested navigation as app grows

## Implementation Details

### Screen Structure Pattern
```dart
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Screen-specific state
  ValueNotifier<int> _matchTimeNotifier = ValueNotifier(0);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Match Timer')),
      body: Consumer<AppState>(
        builder: (context, appState, child) => _buildMatchInterface(appState),
      ),
    );
  }
  
  Widget _buildMatchInterface(AppState appState) {
    // Screen-specific UI construction
  }
}
```

### Component Extraction Criteria
```dart
// Extract when component meets these criteria:
// 1. Used in multiple screens
// 2. Complex behavior requiring isolation
// 3. Performance critical (frequent updates)
// 4. Needs independent testing

class TimerDisplay extends StatelessWidget {
  final int seconds;
  
  const TimerDisplay(this.seconds, {Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary( // Performance optimization
      child: Text(
        formatTime(seconds),
        style: Theme.of(context).textTheme.headline2,
      ),
    );
  }
}
```

### State Management Integration
```dart
// Screens integrate directly with Provider
class PlayerTimesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<AppState, Map<String, Player>>(
      selector: (context, appState) => appState.session.players,
      builder: (context, players, child) => PlayerTimesList(players),
    );
  }
}
```

## Performance Considerations

### Real-Time Update Optimization
- **RepaintBoundary**: Isolate frequently updating components
- **Selector Widgets**: Minimize rebuilds to specific data changes
- **ValueListenableBuilder**: High-frequency updates bypass Provider

### Memory Management
- **Screen Lifecycle**: Proper disposal of screen resources
- **State Cleanup**: Clear state when navigating away from screens
- **Component Caching**: Cache expensive components where appropriate

### UI Performance Monitoring
```dart
// Performance monitoring for screen transitions
class PerformanceMonitoredScreen extends StatefulWidget {
  @override
  _PerformanceMonitoredScreenState createState() => 
    _PerformanceMonitoredScreenState();
}

class _PerformanceMonitoredScreenState extends State<PerformanceMonitoredScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Monitor screen render performance
    });
  }
}
```

## Testing Strategy

### Screen Testing
```dart
// Screen-level widget testing
testWidgets('MainScreen displays current match time', (tester) async {
  final mockAppState = MockAppState();
  when(mockAppState.session).thenReturn(mockSession);
  
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: mockAppState,
      child: MaterialApp(home: MainScreen()),
    ),
  );
  
  expect(find.text('00:00'), findsOneWidget);
});
```

### Component Testing
```dart
// Isolated component testing
testWidgets('TimerDisplay formats seconds correctly', (tester) async {
  await tester.pumpWidget(
    MaterialApp(home: TimerDisplay(90)),
  );
  
  expect(find.text('01:30'), findsOneWidget);
});
```

### Integration Testing
- **Navigation Testing**: Screen transitions and state preservation
- **Real-Time Testing**: Timer updates across screen changes
- **State Testing**: AppState integration across screens

## Future Evolution

### Planned Refactoring
Based on technical debt analysis, planned improvements include:

1. **MainScreen Decomposition** (3,812 lines → multiple components)
   ```dart
   // Extract major sections into focused widgets
   class MainScreen extends StatefulWidget {
     @override
     Widget build(BuildContext context) {
       return Scaffold(
         body: Column(children: [
           TimerSection(),      // ~500 lines
           PlayerSection(),     // ~800 lines  
           ControlsSection(),   // ~600 lines
           StatusSection(),     // ~400 lines
         ]),
       );
     }
   }
   ```

2. **Nested Navigation**: For complex workflows
3. **Component Library**: Standardized components as patterns emerge
4. **Screen Composition**: Larger screens composed of focused sections

## Related ADRs
- [ADR-003](./ADR-003-state-management-provider.md): Provider pattern integration with screens
- [ADR-002](./ADR-002-background-service-architecture.md): Background service coordination through screens
- [ADR-006](./ADR-006-service-layer-organization.md): Service layer accessed through screens

## Review Notes
The screen-based architecture with selective component extraction balances simplicity with functionality. While MainScreen requires refactoring due to size, the overall approach provides clear organization and development velocity. The architecture supports the app's real-time requirements while maintaining maintainability for the development team.