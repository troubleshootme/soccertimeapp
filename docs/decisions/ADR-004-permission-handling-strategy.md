# ADR-004: Permission Handling Strategy and Android Implementation

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires various Android permissions to deliver full functionality:
- Background processing for accurate timer continuation
- Notification display for foreground service and match events
- Storage access for backup/restore functionality
- Battery optimization bypass for reliable background timing
- Vibration for match event feedback

### Requirements
- **Graceful Degradation**: Core functionality works without all permissions
- **User Education**: Clear explanation of permission benefits
- **Progressive Enhancement**: Advanced features require additional permissions
- **Android Compliance**: Follow Android permission best practices
- **Battery Optimization**: Handle Android power management restrictions

### Current Implementation Analysis
The app implements a layered permission strategy:
- Critical permissions requested at startup (notifications, battery optimization)
- Feature permissions requested on-demand (storage for backup/restore)
- Graceful fallback when permissions are denied
- User guidance for permanently denied permissions

## Decision

**Chosen**: Layered Permission Strategy with Progressive Enhancement

### Permission Classification
```dart
enum PermissionLevel {
  critical,    // App core functionality requires these
  feature,     // Specific features require these  
  optional,    // Nice-to-have enhancements
}

// Permission mapping
Map<Permission, PermissionLevel> permissionLevels = {
  Permission.notification: PermissionLevel.critical,
  Permission.ignoreBatteryOptimizations: PermissionLevel.critical,
  Permission.manageExternalStorage: PermissionLevel.feature,
  Permission.vibration: PermissionLevel.optional,
};
```

### Implementation Strategy
1. **Startup Phase**: Request critical permissions with clear explanation
2. **Feature Phase**: Request feature permissions when user attempts to use functionality
3. **Fallback Phase**: Provide alternative functionality when permissions denied
4. **Education Phase**: Guide users to enable permissions manually when needed

## Rationale

### Android Permission Landscape Analysis
Android API evolution affects permission handling:
- **API 21-22**: Basic permission model
- **API 23+**: Runtime permissions introduced
- **API 29+**: Scoped storage changes
- **API 30+**: All files access restrictions
- **API 31+**: Notification permission requirements
- **API 33+**: Enhanced notification controls

### Critical Permission Justification

#### Notification Permission (API 33+)
**Rationale**: Essential for background service operation
```dart
// Required for foreground service notification
await Permission.notification.request();

// Background service cannot run without notification channel
await FlutterBackground.initialize(
  androidConfig: AndroidConfig(
    notificationTitle: "SoccerTime Active",
    notificationText: "Match timer is running",
  ),
);
```

#### Battery Optimization Bypass
**Rationale**: Ensures timer accuracy during background operation
```dart
// Prevents Android from killing background timer
if (await Permission.ignoreBatteryOptimizations.isDenied) {
  await Permission.ignoreBatteryOptimizations.request();
}
```

### Feature Permission Strategy

#### Storage Permission (MANAGE_EXTERNAL_STORAGE)
**Rationale**: Required for backup/restore to Downloads folder
```dart
// Only requested when user initiates backup/restore
Future<void> backupSessions() async {
  final permission = await Permission.manageExternalStorage.status;
  if (permission.isDenied) {
    final result = await _requestStoragePermission();
    if (result.isDenied) {
      _showStoragePermissionEducation();
      return;
    }
  }
  _performBackup();
}
```

## Alternatives Considered

### Request All Permissions Upfront
**Rejected** - Reasons:
- **User Experience**: Permission fatigue leads to denials
- **Android Guidelines**: Contradicts Android best practices
- **Unnecessary Friction**: Users who don't use backup features don't need storage permissions
- **App Store**: May lead to rejection for requesting unnecessary permissions

### Request No Permissions (Degraded Mode)
**Rejected** - Reasons:
- **Core Functionality**: Background timer requires notification permission
- **User Value**: Backup/restore features provide significant user value
- **Competitive Disadvantage**: Other timer apps provide full functionality

### Per-Feature Permission Requests Only
**Rejected** - Reasons:
- **Background Timer**: Critical timer functionality would fail silently without startup permissions
- **User Confusion**: Timer stopping when app backgrounds without clear explanation
- **Reliability**: Unreliable core functionality unacceptable for timer application

### Native Android Permission Handling
**Rejected** - Reasons:
- **Flutter Integration**: Complex bidirectional communication required
- **Platform Coupling**: iOS implementation completely different
- **Maintenance**: Two separate permission systems to maintain
- **Development Speed**: Flutter permission_handler package provides unified API

## Consequences

### Positive
- **Graceful Degradation**: App functions with reduced features when permissions denied
- **User Control**: Users can choose which features to enable
- **Android Compliance**: Follows Android permission best practices
- **Clear Communication**: Users understand why each permission is needed
- **Competitive Features**: Full functionality available when permissions granted
- **Future Proof**: Handles Android API changes gracefully

### Negative
- **Implementation Complexity**: Multiple code paths for different permission states
- **User Education Required**: Users must understand permission implications
- **Support Complexity**: Troubleshooting permission-related issues
- **Testing Overhead**: Must test all permission combinations

### Neutral
- **Initial Setup**: Some users need to grant permissions during first use
- **Android Version Differences**: Permission behavior varies across Android versions

## Implementation Details

### Startup Permission Flow
```dart
Future<void> _requestPermissions() async {
  print("Requesting necessary permissions at startup...");
  
  // Critical: Notification permission for background service
  final notificationStatus = await Permission.notification.request();
  if (notificationStatus.isDenied) {
    _showPermissionRequiredDialog('notification');
  }
  
  // Critical: Battery optimization for timer accuracy
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}
```

### Feature Permission Flow
```dart
Future<void> _requestStoragePermissionWithEducation() async {
  // Show explanation before requesting
  final shouldRequest = await _showPermissionEducationDialog(
    'Storage Access Needed',
    'To backup your session data to Downloads folder, we need storage access.',
  );
  
  if (!shouldRequest) return;
  
  final status = await Permission.manageExternalStorage.request();
  if (status.isDenied) {
    _showManualPermissionGuidance();
  }
}
```

### Permission Education Strategy
```dart
void _showManualPermissionGuidance() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Storage Permission Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('To enable backup functionality:'),
          Text('1. Open Android Settings'),
          Text('2. Find "Apps" or "Application Manager"'),
          Text('3. Find "SoccerTime"'),
          Text('4. Tap "Permissions"'),
          Text('5. Enable "Files and media" permission'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => openAppSettings(),
          child: Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

### Graceful Fallback Implementation
```dart
Future<void> backupSessions() async {
  final hasStorageAccess = await Permission.manageExternalStorage.isGranted;
  
  if (hasStorageAccess) {
    // Full functionality: Save to Downloads folder
    await _saveToDownloadsFolder();
  } else {
    // Fallback: Share via system sharing
    await _shareBackupFile();
  }
}
```

## Testing Strategy

### Permission Testing Matrix
```dart
// Test all permission combinations
enum PermissionScenario {
  allGranted,
  notificationDenied,
  storageDenied,
  batteryOptimizationDenied,
  allDenied,
}
```

### Device Testing Requirements
- **Various Android Versions**: API 21, 26, 29, 31, 33
- **Different OEMs**: Samsung, Xiaomi, OnePlus (different permission UIs)
- **Battery Optimization**: Test with different power management settings
- **Permission States**: Granted, denied, permanently denied scenarios

### Automated Testing
```dart
// Mock permission responses for unit testing
class MockPermissionHandler extends Mock implements PermissionHandler {
  @override
  Future<PermissionStatus> request(Permission permission) async {
    return PermissionStatus.granted; // or denied based on test scenario
  }
}
```

## Android Version Compatibility

### API 21-22 (Android 5.0-5.1)
- All permissions granted at install time
- No runtime permission requests needed
- Simpler permission handling logic

### API 23-28 (Android 6.0-9.0)
- Runtime permissions introduced
- Standard permission request flow
- Limited scoped storage impact

### API 29-30 (Android 10-11)
- Scoped storage introduction
- MANAGE_EXTERNAL_STORAGE for full access
- Background location restrictions

### API 31+ (Android 12+)
- Notification permission requirement
- Enhanced battery optimization controls
- Stricter background service limitations

### API 33+ (Android 13+)
- Notification permission mandatory
- Granular media permissions
- Runtime notification permission required

## Security Considerations

### Permission Minimization
- Request only necessary permissions for functionality
- Avoid requesting permissions "just in case"
- Regular audit of requested permissions

### User Privacy
- Clear explanation of data usage for each permission
- Local-only data processing (no cloud transmission)
- Transparent permission usage in privacy policy

### Data Protection
- Secure storage of user data even with storage permission
- No unnecessary data collection
- Proper data cleanup when permissions revoked

## Related ADRs
- [ADR-002](./ADR-002-background-service-architecture.md): Background service requires notification and battery permissions
- [ADR-001](./ADR-001-local-storage-hive.md): Local storage doesn't require sensitive permissions
- [ADR-006](./ADR-006-service-layer-organization.md): Service layer handles permission-dependent functionality

## Review Notes
The layered permission strategy balances functionality with user control and Android compliance. The progressive enhancement approach ensures core timer functionality while enabling advanced features for users who grant additional permissions. The implementation handles Android's evolving permission landscape gracefully.