# ADR-006: Service Layer Organization and Responsibilities

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires a service layer to abstract platform-specific functionality and business logic from the UI layer. The services must handle:
- Background timer operations and Android integration
- Audio playback for match events
- Haptic feedback for user interactions
- File operations for backup/restore and PDF generation
- Session management and remote storage
- Internationalization and user preferences

### Requirements
- **Platform Abstraction**: Hide Android-specific APIs from UI components
- **Testability**: Services must be mockable for unit testing
- **Single Responsibility**: Each service handles one domain concern
- **Loose Coupling**: Services should minimize dependencies on each other
- **Resource Management**: Proper lifecycle management and cleanup
- **Performance**: Efficient operations that don't block UI

### Current Implementation Analysis
The app implements 7 domain-organized services:
- Background service for timer management and Android integration
- Audio service for whistle sound effects
- Haptic service for vibration feedback
- PDF service for match report generation
- File service for backup/restore operations
- Session service for remote session management
- Translation service for internationalization

## Decision

**Chosen**: Domain-Organized Service Layer with Single Responsibility Principle

### Service Architecture
```
lib/services/
├── background_service.dart    # Android background timer integration
├── audio_service.dart         # Audio playback management
├── haptic_service.dart        # Vibration feedback coordination
├── pdf_service.dart          # PDF generation and export
├── file_service.dart         # File I/O and backup operations
├── session_service.dart      # Remote session management
└── translation_service.dart  # Internationalization support
```

### Service Responsibility Matrix
| Service | Primary Domain | Platform Integration | State Management |
|---------|----------------|---------------------|------------------|
| BackgroundService | Timer accuracy & background execution | ✅ Android APIs | ✅ Complex state |
| AudioService | Audio playback | ✅ Audio system | ❌ Stateless |
| HapticService | Haptic feedback | ✅ Vibration API | ❌ Stateless |
| PdfService | Document generation | ❌ Platform agnostic | ✅ Cache management |
| FileService | File I/O operations | ✅ Storage APIs | ❌ Stateless |
| SessionService | Remote session sync | ✅ Network APIs | ❌ Stateless |
| TranslationService | Internationalization | ❌ Asset loading | ✅ Static translations |

## Rationale

### Domain-Oriented Organization Benefits
Each service focuses on a specific domain:
- **BackgroundService**: Complex timer management with Android integration
- **AudioService**: Simple audio playback abstraction
- **HapticService**: Vibration pattern management
- **PdfService**: Document generation and formatting
- **FileService**: File operations and sharing
- **SessionService**: Remote API and local storage coordination
- **TranslationService**: Localization and text management

### Single Responsibility Application
```dart
// Good: AudioService only handles audio
class AudioService {
  Future<void> playWhistle() async {
    if (_isAudioEnabled()) {
      await _audioPlayer.play('assets/audio/whistle.mp3');
    }
  }
}

// Good: HapticService only handles vibration
class HapticService {
  Future<void> playerToggle() async {
    if (_isVibrationEnabled()) {
      await Vibration.vibrate(duration: 100);
    }
  }
}
```

### Platform Abstraction Strategy
Services hide platform complexity from UI:
```dart
// BackgroundService abstracts Android complexity
class BackgroundService {
  Future<void> startBackgroundTimer() async {
    await _initializeAndroidForegroundService();
    await _requestBatteryOptimizationExemption();
    await _startWallClockTimer();
    // UI doesn't need to know Android specifics
  }
}
```

## Alternatives Considered

### Monolithic Service Architecture
**Rejected** - Reasons:
- **Violation of SRP**: Single service handling multiple domains
- **Testing Complexity**: Difficult to mock specific functionality
- **Development Coupling**: Changes in one domain affect others
- **Code Navigation**: Large service files difficult to navigate

```dart
// Rejected monolithic approach:
class AppService {
  // Audio, haptics, files, background, PDF all in one class
  Future<void> playWhistle() async { /* audio logic */ }
  Future<void> vibrateDevice() async { /* haptic logic */ }
  Future<void> generatePDF() async { /* PDF logic */ }
  // 2000+ lines mixing concerns
}
```

### Feature-Based Service Organization
**Rejected** - Reasons:
- **Cross-Feature Dependencies**: Timer functionality spans multiple features
- **Service Duplication**: Similar operations duplicated across features
- **Inconsistent Patterns**: Different service patterns for each feature

```dart
// Rejected feature-based approach:
lib/features/
├── match_timing/services/timer_service.dart
├── player_management/services/player_service.dart  
├── match_logging/services/logging_service.dart
// Audio/haptics duplicated in each feature
```

### Repository Pattern with Service Layer
**Rejected** - Reasons:
- **Over-Engineering**: Additional abstraction layer not needed
- **Complexity**: Repository + Service + Provider creates too many layers
- **Performance**: Extra indirection impacts real-time timer operations
- **Team Expertise**: Team comfortable with direct service approach

### Utility Classes Instead of Services
**Rejected** - Reasons:
- **State Management**: Some services require state (BackgroundService, PdfService)
- **Resource Management**: Services need proper lifecycle management
- **Platform Integration**: Complex Android integration requires service approach
- **Testing**: Static utility classes harder to mock than service instances

### Native Platform Services
**Rejected** - Reasons:
- **Platform Coupling**: Separate implementations for Android/iOS
- **Flutter Integration**: Complex communication between Flutter and native
- **Maintenance**: Two codebases to maintain for each service
- **Development Speed**: Flutter services faster to develop and iterate

## Consequences

### Positive
- **Clear Responsibility Boundaries**: Each service has well-defined domain
- **Testability**: Services can be mocked independently
- **Platform Abstraction**: UI layer insulated from platform specifics
- **Code Organization**: Related functionality grouped logically
- **Parallel Development**: Different services can be developed independently
- **Reusability**: Services can be reused across different UI components
- **Maintainability**: Changes isolated to specific domains

### Negative
- **Service Proliferation**: 7 services to manage and coordinate
- **Initialization Complexity**: Service startup and dependency management
- **Memory Usage**: Multiple service instances in memory
- **Context Dependencies**: Some services require BuildContext (anti-pattern)

### Neutral
- **Inter-Service Communication**: Minimal communication between services
- **Service Discovery**: Services accessed through direct instantiation
- **Resource Cleanup**: Manual disposal management required

## Implementation Details

### Service Interface Patterns
```dart
// Stateless service pattern (AudioService, HapticService, FileService)
abstract class StatelessService {
  // No internal state
  // Direct operation methods
  Future<void> performOperation();
}

// Stateful service pattern (BackgroundService, PdfService)  
abstract class StatefulService {
  // Internal state management
  bool _initialized = false;
  
  Future<void> initialize();
  Future<void> dispose();
}
```

### Service Lifecycle Management
```dart
// Service initialization in main.dart
Future<void> initializeServices() async {
  final backgroundService = BackgroundService();
  await backgroundService.initialize();
  
  // Register with service locator if implemented
  ServiceLocator.register<BackgroundService>(backgroundService);
}
```

### Error Handling Patterns
```dart
// Consistent error handling across services
abstract class ServiceErrorHandler {
  void handleError(Object error, StackTrace stackTrace, String context);
  
  Future<T> safeExecute<T>(Future<T> Function() operation, String context) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      handleError(error, stackTrace, context);
      rethrow;
    }
  }
}
```

### Service Integration with State Management
```dart
// Services integrate with AppState through composition
class AppState with ChangeNotifier {
  final BackgroundService _backgroundService;
  final AudioService _audioService;
  
  AppState({
    required BackgroundService backgroundService,
    required AudioService audioService,
  }) : _backgroundService = backgroundService,
       _audioService = audioService;
       
  Future<void> startMatch() async {
    await _backgroundService.startBackgroundTimer();
    await _audioService.playWhistle();
    notifyListeners();
  }
}
```

## Testing Strategy

### Service Unit Testing
```dart
// Mock services for unit testing
class MockBackgroundService extends Mock implements BackgroundService {}
class MockAudioService extends Mock implements AudioService {}

test('match start triggers background timer and audio', () async {
  final mockBackground = MockBackgroundService();
  final mockAudio = MockAudioService();
  
  final appState = AppState(
    backgroundService: mockBackground,
    audioService: mockAudio,
  );
  
  await appState.startMatch();
  
  verify(mockBackground.startBackgroundTimer()).called(1);
  verify(mockAudio.playWhistle()).called(1);
});
```

### Service Integration Testing
```dart
// Test actual service implementations
group('BackgroundService Integration', () {
  test('timer continues during app backgrounding', () async {
    final service = BackgroundService();
    await service.initialize();
    await service.startBackgroundTimer();
    
    // Simulate app backgrounding
    await service.handleAppLifecycle(AppLifecycleState.paused);
    
    // Verify timer continues
    expect(service.isTimerRunning, true);
  });
});
```

### Service Performance Testing
- **Memory Usage**: Monitor service memory consumption
- **Response Time**: Measure service operation latency
- **Resource Leaks**: Verify proper resource cleanup

## Service-Specific Analysis

### BackgroundService (Critical Complexity)
**Lines**: 1,233 | **Complexity**: High | **SRP Score**: 2/10
- **Issues**: Multiple responsibilities (timer, background, vibration, notifications)
- **Recommendation**: Split into TimerService + BackgroundServiceManager
- **Priority**: High - affects entire app performance

### PdfService (Medium Complexity)  
**Lines**: 1,176 | **Complexity**: Medium | **SRP Score**: 6/10
- **Issues**: PDF generation mixed with icon creation and file management
- **Recommendation**: Extract IconService and improve file operations
- **Priority**: Medium - affects export functionality

### Other Services (Well-Designed)
AudioService, HapticService, FileService, SessionService, TranslationService show good SRP adherence with focused responsibilities.

## Future Evolution

### Service Locator Pattern
```dart
// Planned service locator for better dependency management
class ServiceLocator {
  static final Map<Type, Object> _services = {};
  
  static void register<T extends Object>(T service) {
    _services[T] = service;
  }
  
  static T get<T extends Object>() {
    return _services[T] as T;
  }
}
```

### Service Interface Abstractions
```dart
// Planned service interfaces for better testing
abstract class IBackgroundService {
  Future<void> startBackgroundTimer();
  Future<void> stopBackgroundTimer();
  Stream<int> get timeUpdates;
}

class BackgroundService implements IBackgroundService {
  // Implementation details
}
```

### Service Composition
```dart
// Planned service composition for complex operations
class MatchService {
  final IBackgroundService _backgroundService;
  final IAudioService _audioService;
  final IHapticService _hapticService;
  
  Future<void> startMatch() async {
    await _backgroundService.startBackgroundTimer();
    await _audioService.playWhistle();
    await _hapticService.matchStart();
  }
}
```

## Related ADRs
- [ADR-002](./ADR-002-background-service-architecture.md): BackgroundService implementation details
- [ADR-003](./ADR-003-state-management-provider.md): Service integration with AppState
- [ADR-004](./ADR-004-permission-handling-strategy.md): Permission handling across services
- [ADR-005](./ADR-005-ui-architecture-decisions.md): Service access from UI components

## Review Notes
The domain-organized service layer provides clear separation of concerns and platform abstraction. While BackgroundService requires refactoring due to SRP violations, the overall service architecture supports the app's requirements effectively. The pattern scales well for additional domains and provides good testing isolation.