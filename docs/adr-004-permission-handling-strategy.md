# ADR-004: Permission Handling Strategy and Android Implementation

## Status
**Accepted** - Implementation complete and actively maintained

## Context and Problem Statement
SoccerTimeApp requires multiple Android permissions to provide core functionality:
- **Background execution** for continuous match timing
- **Notifications** for period/match end alerts
- **Storage access** for session data export/import
- **Exact alarm scheduling** for precise timing events
- **Battery optimization exemption** for reliable background operation
- **Foreground service** for persistent background timing

The permission system must:
- Request permissions at appropriate times (just-in-time)
- Handle permission denials gracefully
- Provide clear user education about permission necessity
- Support different Android API levels (21+)
- Maintain functionality when possible permissions are denied
- Comply with Google Play Store policies

## Decision Rationale
**Selected: Layered Permission Strategy with Progressive Enhancement**

### Permission Architecture:
1. **Critical Permissions**: Required for core app functionality (requested at startup)
2. **Feature Permissions**: Enhance user experience (requested when feature is used)
3. **Optional Permissions**: Provide convenience features (requested contextually)
4. **Graceful Degradation**: App remains functional with reduced permissions

### Implementation Strategy:
```dart
// Multi-tiered permission request system
await _requestCriticalPermissions();  // App startup
await _requestFeaturePermissions();   // Feature activation
await _requestOptionalPermissions();  // Context-specific
```

## Permission Classification

### Critical Permissions (Required for Core Functionality):
```xml
<!-- Background execution for match timing -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- Notifications for period/match alerts -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### Feature Permissions (Enhanced Experience):
```xml
<!-- Exact timing for precision match events -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />

<!-- Battery optimization exemption -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

### Optional Permissions (Convenience Features):
```xml
<!-- File export/import functionality -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

## Implementation Architecture

### Permission Request Flow:
```
App Launch
├── Check Critical Permissions
├── Request if Missing
├── Initialize Core Services
└── Enable Feature Permissions on Demand

Background Service Start
├── Verify Foreground Service Permission
├── Request Notification Permission
├── Request Battery Optimization Exemption
└── Start Background Timing

File Operations
├── Check Storage Permissions
├── Request if Needed for Export/Import
└── Fallback to App-Specific Storage
```

### Key Implementation Components:

#### BackgroundService Permission Handling:
```dart
Future<void> _requestPermissions() async {
  // Request notification permission for Android 13+
  final notificationStatus = await Permission.notification.request();
  
  // Request battery optimization exemption
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}
```

#### Progressive Permission Request:
```dart
Future<bool> initialize() async {
  // Check existing permissions first
  bool hasPermissions = await FlutterBackground.hasPermissions;
  
  if (!hasPermissions) {
    await _requestPermissions();
    hasPermissions = await FlutterBackground.hasPermissions;
  }
  
  return hasPermissions;
}
```

## Alternatives Considered

### Upfront Permission Request
**Rejected** for the following reasons:
- Poor user experience with permission wall at app launch
- Higher likelihood of users denying permissions without context
- Violates Google Play Store best practices for permission requests
- Creates barrier to initial app exploration and trial

### Runtime Permission Checking Only
**Rejected** for the following reasons:
- Cannot guarantee critical functionality availability
- Poor user experience with repeated permission prompts
- Difficult to provide clear error messages for missing permissions
- Inconsistent app behavior based on permission state

### Minimal Permission Approach
**Rejected** for the following reasons:
- Core app functionality (background timing) requires elevated permissions
- User expects reliable background operation for sports timing
- Competitive timing apps require similar permission sets
- Feature limitations would significantly impact user value

## Android API Level Considerations

### API 21-22 (Android 5.0-5.1):
- Basic foreground service permissions
- Limited notification control
- No exact alarm restrictions

### API 23-29 (Android 6.0-10):
- Runtime permission model introduced
- Storage access framework integration
- Background processing restrictions

### API 30-33 (Android 11-13):
- Scoped storage enforcement
- Exact alarm permission requirements
- Enhanced notification permission controls
- Background app restrictions

### API 34+ (Android 14+):
- Foreground service type specifications
- Enhanced battery optimization controls
- Stricter background activity limitations

## Consequences

### Positive Consequences
✅ **Reliable Core Functionality**: Critical permissions ensure background timing works
✅ **Good User Experience**: Just-in-time permission requests with clear context
✅ **Compliance**: Follows Google Play Store permission best practices
✅ **Graceful Degradation**: App functions even with limited permissions
✅ **Transparency**: Clear communication about why permissions are needed
✅ **Future-Proof**: Handles different Android API levels appropriately

### Negative Consequences
❌ **Complex Implementation**: Multiple permission handling paths increase code complexity
❌ **User Confusion**: Some users may not understand why permissions are needed
❌ **Platform Dependency**: Heavy reliance on Android-specific permission system
❌ **Maintenance Overhead**: Must track Android API changes and permission model updates
❌ **Testing Complexity**: Must test various permission grant/deny scenarios

### Risk Mitigation Strategies:
- **User Education**: Clear explanation of permission benefits in app UI
- **Fallback Mechanisms**: Alternative functionality when permissions are denied
- **Permission Monitoring**: Regular checks for permission revocation
- **Documentation**: Clear instructions for users to manually grant permissions
- **Testing Matrix**: Comprehensive testing across permission states and Android versions

## Implementation Notes

### Critical Code Locations:
- `/lib/services/background_service.dart` - Main permission request logic
- `/android/app/src/main/AndroidManifest.xml` - Permission declarations
- Background service initialization flow
- File service permission checks

### Permission Request Best Practices:
1. **Contextual Requests**: Ask for permissions when user tries to use related features
2. **Clear Rationale**: Explain why each permission is needed for specific functionality
3. **Graceful Handling**: Continue app operation with reduced functionality if permissions denied
4. **Re-request Strategy**: Periodically check and offer to re-enable denied permissions

### Error Handling Patterns:
```dart
Future<bool> startBackgroundService() async {
  if (!_isInitialized) {
    final initialized = await initialize();
    if (!initialized) {
      print("Failed to initialize background service due to permissions");
      return false; // Degrade gracefully
    }
  }
  
  // Attempt to start with available permissions
  final success = await FlutterBackground.enableBackgroundExecution();
  return success;
}
```

### User Experience Considerations:
- Permission requests appear only when user attempts to use related features
- Clear messaging about what functionality requires which permissions
- Settings screen provides access to re-enable denied permissions
- App continues to function with core features even if some permissions denied

## Related ADRs
- ADR-002: Background Service Architecture (depends on foreground service permissions)
- ADR-006: Service Layer Organization (file services require storage permissions)