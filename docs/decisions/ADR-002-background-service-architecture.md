# ADR-002: Background Service Architecture and Timer Implementation

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires precise match timing that continues accurately when the app is backgrounded, minimized, or the device is locked. This is critical for soccer match timing where accuracy is essential.

### Requirements
- **Timing Accuracy**: Sub-second precision for match and player timers
- **Background Execution**: Timer continues when app is not visible
- **Battery Optimization**: Minimize battery drain while maintaining precision
- **Android Integration**: Work with Android power management and doze mode
- **State Synchronization**: Seamless sync when app returns to foreground
- **Reliability**: Handle app crashes and device restarts gracefully

### Current Implementation Analysis
The app implements a hybrid background service architecture with:
- Android foreground service for guaranteed execution
- Wall-clock time synchronization for drift compensation
- Multiple timer coordination (match timer + individual player timers)
- Complex state persistence and recovery mechanisms

## Decision

**Chosen**: Hybrid Background Service with Wall-Clock Synchronization

### Architecture Components
```dart
class BackgroundService {
  // Core timer management
  Timer? _backgroundTimer;
  
  // Wall-clock reference for accuracy
  int _referenceWallTime = 0;
  int _referenceMatchTime = 0;
  
  // Android service integration
  FlutterBackground _backgroundService;
  AndroidAlarmManager _alarmManager;
  
  // State synchronization
  SharedPreferences _prefs;
}
```

### Timer Implementation Strategy
1. **Wall-Clock Reference**: Use system time as authoritative source
2. **Drift Compensation**: Regular synchronization to prevent accumulated errors
3. **Background Service**: Android foreground service ensures execution priority
4. **State Persistence**: Critical timer state saved to SharedPreferences
5. **Multi-Timer Coordination**: Single background timer updates all player times

## Rationale

### Precision Requirements Analysis
Soccer matches require:
- **Match Duration**: Precise tracking of 90-minute matches with periods
- **Player Time**: Individual playing time must be accurate for statistics
- **Period Transitions**: Exact timing for halftime and match end notifications
- **Background Accuracy**: Timing continues when app is backgrounded

### Wall-Clock Synchronization Benefits
```dart
void _updateMatchTimeWithWallClock() {
  final currentWallTime = DateTime.now().millisecondsSinceEpoch;
  final elapsedWallTime = currentWallTime - _referenceWallTime;
  final newMatchTime = _referenceMatchTime + (elapsedWallTime ~/ 1000);
  
  // Drift compensation
  final drift = newMatchTime - _expectedMatchTime;
  if (drift.abs() > _driftThreshold) {
    _compensateForDrift(drift);
  }
}
```

### Android Integration Strategy
- **Foreground Service**: Prevents system from killing timer process
- **Wake Locks**: Ensure CPU stays active for timer operations
- **Alarm Manager**: Backup mechanism for period-end notifications
- **Battery Optimization**: Request exemption for critical timing functionality

## Alternatives Considered

### Simple Dart Timer Only
**Rejected** - Reasons:
- **Background Termination**: Flutter timers don't run when app is backgrounded
- **System Throttling**: Android may throttle or kill background Dart isolates
- **Accuracy Loss**: No mechanism to compensate for system sleep or throttling
- **State Loss**: Timer state lost if app is killed by system

### WorkManager-based Background Tasks
**Rejected** - Reasons:
- **Execution Limits**: Android limits background task frequency (15-minute minimum)
- **Precision Loss**: Cannot guarantee sub-second timing accuracy
- **Complexity**: Requires native Android code and complex state management
- **Reliability**: No guarantee of execution during device doze mode

### Isolate-based Background Processing
**Rejected** - Reasons:
- **Platform Limitations**: Flutter isolates don't have reliable background execution
- **State Synchronization**: Complex inter-isolate communication required
- **Resource Usage**: Additional memory overhead for separate isolate
- **Android Integration**: Limited access to Android-specific APIs

### Pure Native Android Service
**Rejected** - Reasons:
- **Development Complexity**: Requires native Android development expertise
- **Flutter Integration**: Complex bidirectional communication with Flutter
- **Platform Coupling**: iOS implementation would require completely different approach
- **Maintenance Burden**: Two separate codebases for timer logic

### Cloud-based Timer Synchronization
**Rejected** - Reasons:
- **Network Dependency**: Requires constant internet connection
- **Latency Issues**: Network latency incompatible with real-time requirements
- **Offline Functionality**: Local matches need offline timer capability
- **Privacy Concerns**: Timer data doesn't require cloud processing

## Consequences

### Positive
- **Accurate Timing**: Wall-clock synchronization maintains sub-second accuracy
- **Reliable Background Execution**: Foreground service ensures timer continues
- **Battery Conscious**: Optimized to minimize unnecessary processing
- **Robust State Management**: Handles app crashes and system kills gracefully
- **Platform Integration**: Leverages Android power management best practices
- **Testable Architecture**: Clear separation between timing logic and platform services

### Negative
- **Implementation Complexity**: Sophisticated synchronization logic required
- **Battery Usage**: Foreground service consumes battery during matches
- **Permission Requirements**: Requires multiple Android permissions
- **Code Complexity**: Complex state management and error recovery
- **Platform-Specific**: Android-focused implementation with iOS implications

### Neutral
- **User Experience**: Notifications required for foreground service (acceptable)
- **Testing Complexity**: Background service testing requires device testing
- **Maintenance**: Ongoing Android API compatibility requirements

## Implementation Details

### Service Lifecycle Management
```dart
Future<void> initialize() async {
  await _requestBackgroundPermissions();
  await AndroidAlarmManager.initialize();
  await _initializeBackgroundService();
}

Future<void> startBackgroundTimer() async {
  _referenceWallTime = DateTime.now().millisecondsSinceEpoch;
  _referenceMatchTime = _currentMatchTime;
  
  _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
    _updateMatchTimeWithWallClock();
    _updatePlayerTimes();
    _saveTimerState();
  });
}
```

### State Persistence Strategy
```dart
Future<void> _saveTimerState() async {
  await _prefs.setInt('referenceWallTime', _referenceWallTime);
  await _prefs.setInt('referenceMatchTime', _referenceMatchTime);
  await _prefs.setInt('currentMatchTime', _currentMatchTime);
  await _prefs.setBool('timerRunning', _timerRunning);
}

Future<void> _restoreTimerState() async {
  _referenceWallTime = _prefs.getInt('referenceWallTime') ?? 0;
  _referenceMatchTime = _prefs.getInt('referenceMatchTime') ?? 0;
  _currentMatchTime = _prefs.getInt('currentMatchTime') ?? 0;
  _timerRunning = _prefs.getBool('timerRunning') ?? false;
}
```

### Drift Compensation Algorithm
```dart
void _compensateForDrift(int drift) {
  if (drift > 0) {
    // Timer is ahead - slow down updates
    _adjustTimerInterval(1100); // Slightly slower updates
  } else {
    // Timer is behind - speed up updates  
    _adjustTimerInterval(900);  // Slightly faster updates
  }
  
  // Re-establish wall-clock reference
  _referenceWallTime = DateTime.now().millisecondsSinceEpoch;
  _referenceMatchTime = _currentMatchTime;
}
```

### Error Recovery Mechanisms
- **Crash Recovery**: Restore timer state from SharedPreferences
- **Time Jump Detection**: Detect and handle system clock changes
- **Service Restart**: Automatic service restart if process is killed
- **State Validation**: Verify timer state consistency on resume

## Testing Strategy

### Unit Testing
- **Timer Logic**: Mock system time for deterministic tests
- **Drift Compensation**: Test various drift scenarios
- **State Persistence**: Verify save/restore operations

### Integration Testing
- **Background Execution**: Test timer accuracy during app backgrounding
- **Device Sleep**: Verify timing continues during device sleep
- **App Lifecycle**: Test state synchronization across app lifecycle events

### Performance Testing
- **Battery Usage**: Monitor battery consumption during extended matches
- **Memory Usage**: Track memory usage over long running periods
- **CPU Usage**: Verify minimal CPU usage during timer operations

## Security Considerations

### Permission Management
- **Battery Optimization**: Request exemption from battery optimization
- **Foreground Service**: Declare foreground service permissions
- **Wake Lock**: Minimal wake lock usage to preserve battery

### Data Privacy
- **Local Storage**: Timer state stored locally, no cloud transmission
- **Minimal Permissions**: Request only necessary permissions for functionality

## Related ADRs
- [ADR-001](./ADR-001-local-storage-hive.md): Hive database used for timer state persistence
- [ADR-003](./ADR-003-state-management-provider.md): AppState coordinates with background service
- [ADR-004](./ADR-004-permission-handling-strategy.md): Permission strategy for background execution
- [ADR-006](./ADR-006-service-layer-organization.md): Background service as part of service layer

## Review Notes
This architecture balances timing accuracy with battery efficiency. The wall-clock synchronization approach provides reliable precision while the foreground service ensures execution continuity. The complexity is justified by the critical timing requirements for soccer match management.