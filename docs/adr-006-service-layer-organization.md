# ADR-006: Service Layer Organization and Responsibilities

## Status
**Accepted** - Implementation complete and in production

## Context and Problem Statement
SoccerTimeApp requires a well-organized service layer to handle:
- External integrations (file system, audio, haptic feedback)
- Background processing and timing services
- Cross-cutting concerns (translations, PDF generation)
- Platform-specific functionality abstraction
- Separation of business logic from UI components
- Testable interfaces for complex operations

The service architecture must provide:
- Clear separation of concerns with single responsibility principle
- Reusable components across multiple UI screens
- Platform abstraction for Android/iOS differences
- Easy mocking and testing capabilities
- Consistent error handling and logging patterns
- Integration points with the core state management system

## Decision Rationale
**Selected: Domain-Organized Service Layer with Dependency Injection**

### Service Architecture Principles:
1. **Single Responsibility**: Each service handles one specific domain or platform concern
2. **Dependency Injection**: Services initialized once and injected where needed
3. **Platform Abstraction**: Hide platform differences behind service interfaces
4. **Stateless Design**: Services maintain minimal state, delegate to AppState when needed
5. **Error Boundary**: Services handle their own error cases and provide fallbacks

### Service Organization:
```
/lib/services/
├── audio_service.dart         - Sound effects and audio feedback
├── background_service.dart    - Background timing and notifications
├── file_service.dart          - File I/O and export/import operations
├── haptic_service.dart        - Tactile feedback abstraction
├── pdf_service.dart           - PDF generation and formatting
├── session_service.dart       - Remote session synchronization (legacy)
└── translation_service.dart   - Internationalization and localization
```

## Service Responsibilities

### AudioService
**Domain**: Sound effects and audio feedback
```dart
class AudioService {
  // Platform-specific audio playback
  - playWhistleSound()
  - playNotificationSound()  
  - setContext(BuildContext) // Flutter context integration
}
```
**Key Decisions**:
- Context-aware for platform-specific audio handling
- Singleton pattern for resource management
- Graceful degradation when audio unavailable

### BackgroundService
**Domain**: Background timing and system integration
```dart
class BackgroundService {
  // Background execution management
  - startBackgroundService() / stopBackgroundService()
  - Timer precision and drift compensation
  - Period/match end detection and notifications
  - Foreground/background state synchronization
}
```
**Key Decisions**:
- Singleton for system-wide background state
- Direct integration with AppState for real-time updates
- Complex timing logic isolated from UI concerns

### FileService
**Domain**: File system operations and data export
```dart
class FileService {
  // File I/O operations
  - exportSessionData()
  - importSessionData()
  - Platform-specific file picker integration
  - PDF file management
}
```
**Key Decisions**:
- Platform abstraction for file system differences
- Permission handling integration
- Async/await pattern for all I/O operations

### HapticService
**Domain**: Tactile feedback abstraction
```dart
class HapticService {
  // Haptic feedback control
  - lightImpact() / mediumImpact() / heavyImpact()
  - Platform capability detection
  - User preference integration
}
```
**Key Decisions**:
- Simple abstraction over platform haptic APIs
- Graceful handling when haptics unavailable
- Integration with user vibration preferences

### PDFService
**Domain**: PDF document generation and formatting
```dart
class PDFService {
  // PDF generation
  - generateMatchReport()
  - Session data formatting
  - Table layout and styling
}
```
**Key Decisions**:
- Specialized service for complex PDF layout logic
- Reusable formatting across different report types
- Memory-efficient document generation

### TranslationService
**Domain**: Internationalization and localization
```dart
class TranslationService {
  // I18n support
  - get(String key) -> String
  - Asset-based translation loading
  - Fallback to English for missing translations
}
```
**Key Decisions**:
- Singleton for application-wide translation access
- Asset-based translations for offline functionality
- Simple key-based lookup system

## Alternatives Considered

### Repository Pattern with Interfaces
**Rejected** for the following reasons:
- Over-engineering for the app's relatively simple data access patterns
- Additional abstraction layers not justified by current requirements
- No multiple data source implementations to warrant interface abstractions
- Flutter's plugin system already provides necessary platform abstractions

### Service Locator Pattern (GetIt)
**Rejected** for the following reasons:
- Provider pattern already handles dependency injection adequately
- Additional dependency not justified by benefits
- Service locator pattern can make dependencies less explicit
- Flutter's widget tree provides natural dependency injection

### Microservice Architecture
**Rejected** for the following reasons:
- Excessive complexity for single mobile application
- No network boundaries or separate deployment needs
- Monolithic mobile app architecture more appropriate
- Unnecessary overhead for simple service coordination

### Static Utility Classes
**Rejected** for the following reasons:
- Difficult to mock for testing
- No instance state management for context-dependent operations
- Poor integration with Flutter's lifecycle management
- Limited flexibility for future enhancements

## Implementation Architecture

### Service Initialization Pattern:
```dart
class _ScreenState extends State<Screen> {
  late AudioService _audioService;
  late HapticService _hapticService;
  
  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _hapticService = HapticService();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audioService.setContext(context); // Context-dependent initialization
  }
}
```

### Service Integration with State Management:
```dart
// Services integrated through AppState methods
class AppState with ChangeNotifier {
  Future<void> togglePlayer(String name) async {
    // Business logic
    final player = _session.players[name]!;
    player.active = !player.active;
    
    // Service integration
    if (shouldPlaySound) {
      _audioService.playNotificationSound();
    }
    if (shouldVibrate) {
      _hapticService.lightImpact();
    }
    
    await saveSession();
    notifyListeners();
  }
}
```

### Error Handling Pattern:
```dart
class AudioService {
  Future<void> playWhistleSound() async {
    try {
      // Attempt to play sound
      await audioPlayer.play(AssetSource('sounds/whistle.mp3'));
    } catch (e) {
      print('Error playing whistle sound: $e');
      // Graceful degradation - no sound but app continues
    }
  }
}
```

## Consequences

### Positive Consequences
✅ **Clear Separation**: Each service has well-defined domain boundaries
✅ **Testability**: Services easily mocked for unit testing
✅ **Reusability**: Services used across multiple screens without duplication
✅ **Platform Abstraction**: Hide Android/iOS differences behind service APIs
✅ **Maintainability**: Changes to external integrations isolated to specific services
✅ **Error Isolation**: Service-level error handling prevents app crashes
✅ **Single Responsibility**: Each service focused on one specific concern

### Negative Consequences
❌ **Additional Abstraction**: Extra layer between UI and platform APIs
❌ **Initialization Complexity**: Services require proper lifecycle management
❌ **Indirect Dependencies**: Services depend on each other through AppState
❌ **Testing Overhead**: Must mock multiple services for integration tests
❌ **Code Distribution**: Related functionality spread across service files

### Performance Impact:
- Service initialization: 1-5ms per service at startup
- Method call overhead: <1ms for typical service operations
- Memory usage: ~1-2MB total for all service instances
- Platform integration: Minimal overhead through efficient native bindings

## Implementation Notes

### Service Dependencies:
```
AppState
├── Uses: AudioService, HapticService, BackgroundService
├── Coordinates: Service calls with state changes
└── Manages: Service lifecycle through screen transitions

BackgroundService
├── Updates: AppState directly for timing synchronization
├── Uses: System services (notifications, alarms)
└── Isolated: Complex timing logic from UI concerns

FileService
├── Integrates: Platform file picker plugins
├── Handles: Permission requirements
└── Provides: Data export/import functionality
```

### Key Integration Points:
- Services instantiated in screen `initState()` methods
- AppState coordinates service calls with state changes
- BackgroundService maintains direct AppState reference for real-time updates
- Context-dependent services receive Flutter BuildContext in `didChangeDependencies()`

### Testing Strategy:
```dart
// Service mocking for unit tests
class MockAudioService extends AudioService {
  bool whistlePlayed = false;
  
  @override
  Future<void> playWhistleSound() async {
    whistlePlayed = true;
  }
}
```

### Extension Points:
- New services follow established patterns for easy integration
- Platform-specific implementations isolated within service boundaries
- Service interfaces can be extracted if multiple implementations needed
- Error handling patterns consistent across all services

## Related ADRs
- ADR-003: State Management with Provider (services integrate through AppState)
- ADR-002: Background Service Architecture (BackgroundService as central timing coordinator)
- ADR-004: Permission Handling Strategy (FileService integration with permission system)