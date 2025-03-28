# Soccer Time

A Flutter application for managing soccer matches, tracking player time, and handling match statistics. Perfect for coaches, referees, and team managers.

## Features

### Match Management
- Create and manage multiple matches
- Track match duration and periods
- Support for custom match durations and number of periods
- Background timer service for accurate time tracking
- Vibration and sound notifications for period changes

### Player Management
- Add and remove players during matches
- Track individual player time on the field
- Quick player substitution interface
- Player statistics tracking

### Backup & Restore
- Backup match data to Downloads folder
- Restore from previous backups
- Automatic backup file naming with timestamps
- Support for multiple backup files

### Customization
- Dark/Light theme support
- Customizable match settings
- Adjustable notification preferences
- Configurable sound and vibration feedback

## Getting Started

### Prerequisites
- Flutter SDK
- Android Studio / VS Code
- Android device or emulator (Android 10 or higher recommended)

### Installation
1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Storage Permissions

The app requires full storage access permission (`MANAGE_EXTERNAL_STORAGE`) to:
- Save backup files to the Downloads folder
- Restore from existing backups
- Manage backup files

This permission is requested only when you try to backup or restore your data, not at app startup. When you click either "Backup Sessions" or "Restore Sessions", you'll be prompted to grant this permission.

### Why Full Storage Access?

The app needs full storage access to:
1. Save backup files to your Downloads folder for easy access
2. Read existing backup files from your Downloads folder
3. Manage backup files (create, read, update, delete)

### How to Grant Permission

When you try to backup or restore:
1. You'll see a dialog explaining why the permission is needed
2. Click "Continue" to open Android Settings
3. Find "All files access" or "Files and media" permission
4. Enable it for Soccer Time
5. Return to the app to continue with backup/restore

### Note for Android 13+

On Android 13 and newer devices, you'll need to grant "All files access" permission through the system settings. This is a security requirement from Android and cannot be bypassed.

## Background Service

The app uses a background service to ensure accurate time tracking even when the app is minimized. This requires:
- Notification permission for the foreground service
- Battery optimization exemption to prevent the service from being killed

These permissions are requested at app startup to ensure proper functionality.

## Development

### Project Structure
```
lib/
  ├── models/         # Data models
  ├── providers/      # State management
  ├── screens/        # UI screens
  ├── services/       # Background and utility services
  ├── utils/          # Helper functions and constants
  └── main.dart       # App entry point
```

### Key Dependencies
- `provider`: State management
- `hive`: Local database
- `permission_handler`: Permission management
- `flutter_background_service`: Background timer service
- `android_alarm_manager_plus`: Alarm management
- `wakelock_plus`: Screen wake lock
- `share_plus`: File sharing

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Flutter team for the amazing framework
- All contributors and users of the app
- The soccer community for their feedback and suggestions
