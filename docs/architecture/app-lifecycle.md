# App Lifecycle and State Management Documentation

## Overview

This document provides comprehensive documentation of the SoccerTimeApp's lifecycle behavior, state transitions, and how timers and services behave during each lifecycle phase. The app implements complex background timer functionality that must continue running when the device is backgrounded or locked.

## App Lifecycle States

The SoccerTimeApp implements `WidgetsBindingObserver` in both the main app widget and the main screen to handle lifecycle transitions. The app responds to the following Flutter lifecycle states:

### 1. App Startup (Cold Start)

**State Flow:** `detached` → `inactive` → `resumed`

**Initialization Sequence:**
1. **Flutter Framework Initialization**
   - `WidgetsFlutterBinding.ensureInitialized()`
   - Hive database initialization
   - Permission requests (notifications, battery optimization)

2. **Service Initialization**
   - Background service initialization
   - Android Alarm Manager initialization
   - Wakelock enablement

3. **UI Setup**
   - System UI configuration (portrait orientation, status bar)
   - Directory creation for session storage
   - Error handler registration

4. **Database and State Setup**
   - Hive session database initialization
   - AppState provider creation
   - Route configuration

**Critical Components Active:**
- Permission Manager (requesting initial permissions)
- Hive Database (initializing storage)
- Background Service (preparing for timer functionality)
- Wakelock (keeping screen active)

**Potential Failure Points:**
- Permission denial (notifications, battery optimization)
- Hive database initialization failure
- Background service initialization failure
- Directory creation errors

### 2. App Foreground (Active State)

**State:** `AppLifecycleState.resumed`

**Active Components:**
- **UI Refresh Timer**: Updates match time display every 100ms
- **Background Service**: Maintains authoritative match time
- **Wakelock**: Keeps screen active during matches
- **Database Connection**: Active Hive connection for session management
- **Audio/Vibration Services**: Available for period/match end notifications

**Timer Synchronization:**
- UI timer (`_matchTimer`) runs independently for display updates
- Background service maintains authoritative time calculation
- UI queries background service for current match time
- Time updates propagated through listeners and notifiers

**State Management:**
```dart
// Main screen timer management
Timer? _matchTimer;
ValueNotifier<int> _matchTimeNotifier = ValueNotifier<int>(0);

// Background service provides authoritative time
int getCurrentMatchTime() => _backgroundService.getCurrentMatchTime();
```

### 3. App Background Transition

**State Transition:** `resumed` → `inactive` → `paused`

**Inactive State Handling:**
- Temporary state during transition
- Background entry time recorded (if not already set)
- UI timer continues running (not cancelled in inactive state)
- Background service state synchronized

**Paused State Handling:**
- **UI Timer Cancellation**: `_matchTimer?.cancel()` to prevent unnecessary processing
- **Database Connection Closure**: `HiveSessionDatabase.instance.close()` to prevent locking
- **Background Service Activation**: Starts if match is running and not paused
- **Wakelock Retention**: Kept active to maintain background timer accuracy

**Critical Background Transition Code:**
```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    // Record background entry time
    _backgroundEntryTime = DateTime.now().millisecondsSinceEpoch;
    _lastKnownMatchTime = _matchTime;
    
    // Cancel UI timer
    _matchTimer?.cancel();
    
    // Close database to prevent locking
    HiveSessionDatabase.instance.close();
    
    // Start background service if match is running
    if (appState.session.matchRunning && !appState.session.isPaused) {
      _backgroundService.startBackgroundService();
    }
  }
}
```

### 4. App Resume (Return to Foreground)

**State Transition:** `paused` → `inactive` → `resumed`

**Resume Sequence:**
1. **Time Synchronization**: Background service calculates elapsed time
2. **UI Timer Restart**: Immediate restart with zero delay to prevent stalling
3. **Database Reconnection**: `HiveSessionDatabase.instance.init()`
4. **Wakelock Re-enablement**: Ensures screen stays active
5. **State Reset**: Background tracking variables cleared

**Time Synchronization Logic:**
```dart
if (state == AppLifecycleState.resumed) {
  // Immediate UI timer restart
  if (appState.session.matchRunning && !appState.session.isPaused) {
    _startMatchTimer(initialDelay: 0);
  }
  
  // Sync time from background service
  _backgroundService.syncTimeOnResume(appState);
  
  // Update UI with synced time
  setState(() {
    _matchTime = _backgroundService.getCurrentMatchTime();
    _matchTimeNotifier.value = _matchTime;
  });
}
```

### 5. App Termination

**State:** `AppLifecycleState.detached`

**Cleanup Sequence:**
- **Wakelock Disable**: `WakelockPlus.disable()`
- **Database Closure**: `HiveSessionDatabase.instance.close()`
- **Timer Cleanup**: All timers cancelled
- **Service Cleanup**: Background service stopped
- **Observer Removal**: Lifecycle observer removed

## Background Service Lifecycle

### Service States

The background service maintains several critical states:

```dart
class BackgroundService {
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _isTimerActive = false;
  bool _isPaused = false;
  
  // Time tracking
  int _currentMatchTime = 0;
  int _timerStartTimestamp = 0;
  double _accumulatedDrift = 0.0;
}
```

### Service Lifecycle Events

1. **Initialization** (`initialize()`)
   - Permission verification
   - Flutter background service setup
   - Alarm manager configuration

2. **Timer Start** (`startTimer()`)
   - Record start timestamp
   - Initialize time tracking variables
   - Start periodic timer (100ms intervals)

3. **Background Activation** (`startBackgroundService()`)
   - Request foreground service permission
   - Configure background execution
   - Maintain timer accuracy during background

4. **Resume Synchronization** (`syncTimeOnResume()`)
   - Calculate elapsed background time
   - Apply time corrections
   - Reset drift tracking

5. **Service Cleanup** (`stopBackgroundService()`)
   - Cancel all timers
   - Stop foreground service
   - Reset state variables

## Timer Accuracy and Synchronization

### Dual Timer Architecture

The app uses a dual-timer approach:

1. **UI Timer**: Fast refresh for smooth display (100ms intervals)
2. **Background Timer**: Authoritative time calculation (100ms intervals)

### Time Calculation Methods

**Foreground Time Calculation:**
```dart
// UI timer updates display
_matchTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
  setState(() {
    _matchTime = _backgroundService.getCurrentMatchTime();
    _matchTimeNotifier.value = _matchTime;
  });
});
```

**Background Time Calculation:**
```dart
// Background service maintains authoritative time
int getCurrentMatchTime() {
  if (!_isTimerActive) return _currentMatchTime;
  
  final now = DateTime.now().millisecondsSinceEpoch;
  final elapsed = (now - _timerStartTimestamp) / 1000.0;
  return _currentMatchTime + elapsed.floor();
}
```

### Drift Compensation

The background service implements drift compensation to maintain accuracy:

```dart
double _accumulatedDrift = 0.0;
double _partialSeconds = 0.0;

void _handleTimerTick() {
  final expectedTime = _lastTickExpectedTotalSeconds + 0.1;
  final actualTime = (DateTime.now().millisecondsSinceEpoch - _timerStartTimestamp) / 1000.0;
  final drift = actualTime - expectedTime;
  
  _accumulatedDrift += drift;
  
  // Apply correction if drift exceeds threshold
  if (_accumulatedDrift.abs() > 0.05) {
    _currentMatchTime += _accumulatedDrift.round();
    _accumulatedDrift = 0.0;
  }
}
```

## Database Lifecycle Management

### Connection Management

The app manages Hive database connections based on lifecycle state:

**Foreground:** Active connection for real-time session management
**Background:** Connection closed to prevent file locking issues
**Resume:** Connection re-established with initialization

### Session Persistence

Session data is persisted during lifecycle transitions:

```dart
// Background transition - save current state
await appState.saveSession();
HiveSessionDatabase.instance.close();

// Resume - restore connection and reload state
await HiveSessionDatabase.instance.init();
await appState.loadSession(currentSessionId);
```

## Error Handling During Lifecycle

### Initialization Errors

```dart
bool hasInitializationError = false;
String errorMessage = '';

try {
  await HiveSessionDatabase.instance.init();
} catch (e) {
  hasInitializationError = true;
  errorMessage = e.toString();
}
```

### Runtime Error Recovery

The app implements error boundaries and recovery mechanisms:

```dart
class ErrorHandler {
  void handleFlutterError(FlutterErrorDetails details) {
    if (_shouldSuppressError(details.exception.toString())) {
      // Log and suppress known issues
      return;
    }
    FlutterError.presentError(details);
  }
}
```

### Background Service Error Handling

```dart
// Service initialization failure fallback
if (!await _backgroundService.initialize()) {
  // Continue with foreground-only mode
  _showUserMessage("Background timer unavailable - using foreground mode");
}
```

## Performance Considerations

### Memory Management

- **Timer Cleanup**: All timers cancelled during lifecycle transitions
- **Listener Management**: Event listeners properly removed
- **Resource Disposal**: Database connections and services properly disposed

### Battery Optimization

- **Selective Wakelock**: Only active during matches
- **Efficient Timers**: 100ms intervals balance accuracy with battery usage
- **Background Service**: Minimal processing during background execution

### UI Performance

- **Conditional Updates**: UI updates only when necessary
- **State Batching**: Multiple state changes batched into single updates
- **Timer Coordination**: UI and background timers synchronized to prevent conflicts

## Troubleshooting Common Issues

### Timer Synchronization Issues

**Problem**: UI time doesn't match background time after resume
**Solution**: Immediate UI timer restart with zero delay

### Database Locking Issues

**Problem**: Database access fails after background/resume cycle
**Solution**: Proper connection closure/reopening during lifecycle transitions

### Permission-Related Failures

**Problem**: Background service fails to start due to missing permissions
**Solution**: Runtime permission verification and user guidance

### Memory Leaks

**Problem**: Timers continue running after app termination
**Solution**: Proper cleanup in `dispose()` and `didChangeAppLifecycleState()`

## Best Practices

1. **Always verify permissions** before starting background services
2. **Implement proper cleanup** in all lifecycle transition handlers
3. **Use authoritative time sources** to prevent synchronization issues
4. **Handle initialization failures gracefully** with user-friendly error messages
5. **Test lifecycle transitions thoroughly** on different Android versions
6. **Monitor battery usage** and optimize timer intervals as needed
7. **Implement proper error boundaries** to prevent app crashes during transitions