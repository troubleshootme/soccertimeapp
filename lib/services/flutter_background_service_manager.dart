import 'package:flutter_background_service/flutter_background_service.dart';

/// Manager for the Flutter background service
class FlutterBackgroundServiceManager {
  static final FlutterBackgroundServiceManager _instance = FlutterBackgroundServiceManager._internal();
  factory FlutterBackgroundServiceManager() => _instance;
  FlutterBackgroundServiceManager._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isRunning = false;

  /// Start the background service with timer data
  Future<bool> startTimer({
    required int matchTime,
    required int period,
    required bool isPaused,
  }) async {
    try {
      if (!_isRunning) {
        _service.invoke('setAsForeground');
        _isRunning = true;
      }

      // Send timer data to the service
      _service.invoke('updateTimer', {
        'matchTime': matchTime,
        'period': period,
        'isPaused': isPaused,
      });

      return true;
    } catch (e) {
      print('Error starting Flutter background service: $e');
      return false;
    }
  }

  /// Update timer data in the service
  Future<bool> updateTimer({
    required int matchTime,
    required int period,
    required bool isPaused,
  }) async {
    try {
      _service.invoke('updateTimer', {
        'matchTime': matchTime,
        'period': period,
        'isPaused': isPaused,
      });
      return true;
    } catch (e) {
      print('Error updating timer in Flutter background service: $e');
      return false;
    }
  }

  /// Start period end alert
  Future<bool> startPeriodEndAlert() async {
    try {
      _service.invoke('startAlert');
      return true;
    } catch (e) {
      print('Error starting period end alert: $e');
      return false;
    }
  }

  /// Stop period end alert
  Future<bool> stopPeriodEndAlert() async {
    try {
      _service.invoke('stopAlert');
      return true;
    } catch (e) {
      print('Error stopping period end alert: $e');
      return false;
    }
  }

  /// Stop the background service
  Future<bool> stopTimer() async {
    try {
      _service.invoke('stopService');
      _isRunning = false;
      return true;
    } catch (e) {
      print('Error stopping Flutter background service: $e');
      return false;
    }
  }

  /// Check if service is running
  bool get isServiceRunning => _isRunning;
}
