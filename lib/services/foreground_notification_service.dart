import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for managing foreground notifications and vibration alerts
class ForegroundNotificationService {
  static const MethodChannel _channel = MethodChannel('soccertime/foreground');
  
  static final ForegroundNotificationService _instance = ForegroundNotificationService._internal();
  factory ForegroundNotificationService() => _instance;
  ForegroundNotificationService._internal();

  bool _isServiceRunning = false;
  Timer? _updateTimer;

  /// Initialize the foreground notification service
  Future<bool> initialize() async {
    try {
      // Request notification permission
      final notificationPermission = await Permission.notification.request();
      if (!notificationPermission.isGranted) {
        print('Notification permission denied');
        return false;
      }

      // Request battery optimization exemption
      final batteryOptimization = await Permission.ignoreBatteryOptimizations.request();
      if (!batteryOptimization.isGranted) {
        print('Battery optimization exemption denied - service may be killed');
      }

      return true;
    } catch (e) {
      print('Error initializing foreground service: $e');
      return false;
    }
  }

  /// Start the foreground service with timer
  Future<bool> startTimer({
    required int matchTime,
    required int period,
    required bool isPaused,
    int alertTimeSeconds = 5,
  }) async {
    try {
      final result = await _channel.invokeMethod('startTimer', {
        'matchTime': matchTime,
        'period': period,
        'isPaused': isPaused,
        'alertTimeSeconds': alertTimeSeconds,
      });

      if (result == true) {
        _isServiceRunning = true;
        _startUpdateTimer();
        print('Foreground service started successfully');
        return true;
      }
      return false;
    } catch (e) {
      print('Error starting foreground service: $e');
      return false;
    }
  }

  /// Pause the timer
  Future<bool> pauseTimer() async {
    try {
      final result = await _channel.invokeMethod('pauseTimer');
      if (result == true) {
        print('Timer paused in foreground service');
        return true;
      }
      return false;
    } catch (e) {
      print('Error pausing timer: $e');
      return false;
    }
  }

  /// Resume the timer
  Future<bool> resumeTimer() async {
    try {
      final result = await _channel.invokeMethod('resumeTimer');
      if (result == true) {
        print('Timer resumed in foreground service');
        return true;
      }
      return false;
    } catch (e) {
      print('Error resuming timer: $e');
      return false;
    }
  }

  /// Stop the foreground service
  Future<bool> stopTimer() async {
    try {
      final result = await _channel.invokeMethod('stopTimer');
      if (result == true) {
        _isServiceRunning = false;
        _updateTimer?.cancel();
        print('Foreground service stopped');
        return true;
      }
      return false;
    } catch (e) {
      print('Error stopping foreground service: $e');
      return false;
    }
  }

  /// Update the timer display in the notification
  Future<bool> updateTimer({
    required int matchTime,
    required int period,
    required bool isPaused,
  }) async {
    try {
      final result = await _channel.invokeMethod('updateTimer', {
        'matchTime': matchTime,
        'period': period,
        'isPaused': isPaused,
      });
      return result == true;
    } catch (e) {
      print('Error updating timer: $e');
      return false;
    }
  }

  /// Start period end alert (vibration)
  Future<bool> startPeriodEndAlert() async {
    try {
      final result = await _channel.invokeMethod('startPeriodEndAlert');
      if (result == true) {
        print('Period end alert started');
        return true;
      }
      return false;
    } catch (e) {
      print('Error starting period end alert: $e');
      return false;
    }
  }

  /// Stop period end alert
  Future<bool> stopPeriodEndAlert() async {
    try {
      final result = await _channel.invokeMethod('stopPeriodEndAlert');
      if (result == true) {
        print('Period end alert stopped');
        return true;
      }
      return false;
    } catch (e) {
      print('Error stopping period end alert: $e');
      return false;
    }
  }

  /// Check if the service is running
  bool get isServiceRunning => _isServiceRunning;

  /// Start a timer to update the notification periodically
  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isServiceRunning) {
        // This will be called by the main timer service
        // to update the notification display
      }
    });
  }

  /// Dispose the service
  void dispose() {
    _updateTimer?.cancel();
    _isServiceRunning = false;
  }
}
