import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:vibration/vibration.dart';
import '../providers/app_state.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static const String BACKGROUND_ENABLED_KEY = 'background_service_enabled';
  static const int PERIOD_END_ALARM_ID = 42; // Unique ID for our period end alarm
  
  // Singleton instance
  @pragma('vm:entry-point')
  static final BackgroundService _instance = BackgroundService._internal();
  
  @pragma('vm:entry-point')
  factory BackgroundService() => _instance;
  
  @pragma('vm:entry-point')
  BackgroundService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;
  Timer? _backgroundTimer;
  Timer? _reminderVibrationTimer; // Add timer for periodic vibration reminders
  int? _lastBackgroundTimestamp;
  bool _periodEndDetected = false;
  bool _matchEndDetected = false;
  bool _isTimerActive = false;
  bool _hasPeriodEnded = false;
  bool _hasMatchEnded = false;
  bool _periodEndNotified = false;
  bool _matchEndNotified = false;
  bool _periodsTransitioning = false;
  bool _isPaused = false;
  
  // Store a reference to the current AppState
  AppState? _currentAppState;
  
  // Store time tracking variables
  int _currentMatchTime = 0; 
  int _lastUpdateTimestamp = 0;
  int _timerStartTimestamp = 0;  // Record when the timer actually started
  double _accumulatedDrift = 0.0;  // Add drift tracking variable
  double _partialSeconds = 0.0;  // Track partial seconds to prevent loss during timer switches
  
  // Add listeners for UI updates
  final List<Function(int matchTime)> _timeUpdateListeners = [];
  final List<Function()> _periodEndListeners = [];
  final List<Function()> _matchEndListeners = [];
  
  // Add these variables to the class near other time tracking variables
  int _backgroundEntryTime = 0;  // Timestamp when app goes to background
  int _lastKnownMatchTime = 0;   // Last known match time when app went to background
  DateTime? _referenceWallTime;  // Reference wall clock time (nullable for init)
  int _referenceMatchTime = 0;   // Reference match time for synchronization
  double _lastTickExpectedTotalSeconds = 0.0; // Expected wall-clock time from previous tick
  
  // Add method to register listeners
  void addTimeUpdateListener(Function(int matchTime) listener) {
    _timeUpdateListeners.add(listener);
  }
  
  void removeTimeUpdateListener(Function(int matchTime) listener) {
    _timeUpdateListeners.remove(listener);
  }
  
  void addPeriodEndListener(Function() listener) {
    _periodEndListeners.add(listener);
  }
  
  void removePeriodEndListener(Function() listener) {
    _periodEndListeners.remove(listener);
  }
  
  void addMatchEndListener(Function() listener) {
    _matchEndListeners.add(listener);
  }
  
  void removeMatchEndListener(Function() listener) {
    _matchEndListeners.remove(listener);
  }
  
  // Method to notify time update
  void _notifyTimeUpdate(int newMatchTime) {
    for (var listener in _timeUpdateListeners) {
      try {
        listener(newMatchTime);
      } catch (e) {
        print('Error in time update listener: $e');
      }
    }
  }
  
  // Method to notify period end
  void _notifyPeriodEnd() {
    for (var listener in _periodEndListeners) {
      try {
        listener();
      } catch (e) {
        print('Error in period end listener: $e');
      }
    }
  }
  
  // Method to notify match end
  void _notifyMatchEnd() {
    for (var listener in _matchEndListeners) {
      try {
        listener();
      } catch (e) {
        print('Error in match end listener: $e');
      }
    }
  }

  // Background service configuration for Android
  final androidConfig = const FlutterBackgroundAndroidConfig(
    notificationTitle: 'Soccer Time App',
    notificationText: 'Timers are running in the background',
    notificationImportance: AndroidNotificationImportance.max,
    notificationIcon: const AndroidResource(
      name: 'ic_notification',
      defType: 'drawable',
    ),
    enableWifiLock: false,
  );

  // Initialize background service
  @pragma('vm:entry-point')
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    print("Initializing background service...");
    
    // Request Android permissions explicitly
    await _requestPermissions();
    
    // Initialize Android Alarm Manager
    await AndroidAlarmManager.initialize();
    
    // Check if the device supports background execution
    bool hasPermissions = await FlutterBackground.hasPermissions;
    print("Background permissions check: $hasPermissions");
    if (!hasPermissions) {
      print("No background execution permissions");
      return false;
    }
    
    // Initialize the background service
    print("Calling FlutterBackground.initialize with config...");
    final success = await FlutterBackground.initialize(androidConfig: androidConfig);
    print("Background service initialization result: $success");
    _isInitialized = success;
    return success;
  }
  
  // Request Android permissions needed for foreground service
  Future<void> _requestPermissions() async {
    print("Requesting necessary Android permissions...");
    
    // Request notification permission for Android 13+
    final notificationStatus = await Permission.notification.request();
    print("Notification permission status: $notificationStatus");
    
    // Request post notifications permission explicitly
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    
    // For foreground service
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // Start the background service
  @pragma('vm:entry-point')
  Future<bool> startBackgroundService() async {
    print("startBackgroundService called, initialized: $_isInitialized");
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        print("Failed to initialize background service");
        return false;
      }
    }
    
    if (!_isRunning) {
      print("Enabling background execution...");
      final success = await FlutterBackground.enableBackgroundExecution();
      print("Enable background execution result: $success");
      if (success) {
        _isRunning = true;
        // Save the state to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(BACKGROUND_ENABLED_KEY, true);
        print('Background service started successfully');
      } else {
        print('Failed to start background service');
      }
      return success;
    }
    
    print("Background service already running");
    return true; // Already running
  }

  // Stop the background service
  Future<bool> stopBackgroundService() async {
    print("Stopping background service");
    
    // Stop reminder vibrations completely
    stopReminderVibrations();
    
    // Stop any ongoing vibrations
    try {
      Vibration.cancel();
    } catch (e) {
      print("Error cancelling vibration: $e");
    }
    
    // Important: Reset all flags and state
    _isTimerActive = false;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _lastUpdateTimestamp = 0;
    _currentMatchTime = 0;
    _lastBackgroundTimestamp = null;
    _accumulatedDrift = 0;
    _partialSeconds = 0.0;
    _periodEndDetected = false;
    _matchEndDetected = false;
    _periodsTransitioning = false;
    
    if (_isRunning) {
      final success = await FlutterBackground.disableBackgroundExecution();
      if (success) {
        _isRunning = false;
        // Save the state to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(BACKGROUND_ENABLED_KEY, false);
        print('Background service stopped successfully');
      } else {
        print('Failed to stop background service');
      }
      return success;
    }
    
    print("Background service fully stopped and reset");
    return true; // Already stopped
  }

  // Check if the background service is running
  bool get isRunning => _isRunning;
  
  // Check if a period end was detected while in background
  bool get periodEndDetected => _periodEndDetected;
  
  // Check if match end was detected while in background
  bool get matchEndDetected => _matchEndDetected;
  
  // Reset event flags
  void resetEventFlags() {
    _periodEndDetected = false;
    _matchEndDetected = false;
    
    // Cancel any existing reminder vibration timer
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
  }

  // Restore previous state of background service on app launch
  Future<void> restorePreviousState() async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool(BACKGROUND_ENABLED_KEY) ?? false;
    
    if (wasEnabled) {
      await startBackgroundService();
    }
  }

  @pragma('vm:entry-point')
  void startBackgroundTimer(AppState appState) {
    _backgroundTimer?.cancel();
    
    // CRITICAL FIX: Store reference to AppState for use in other methods
    _currentAppState = appState;
    
    // Reset event flags
    _periodEndDetected = false;
    _matchEndDetected = false;
    
    // Initialize match time from AppState
    _currentMatchTime = appState.session.matchTime;
    
    // Store initial timestamp when starting the background timer
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    _lastBackgroundTimestamp = nowMillis ~/ 1000;
    _lastUpdateTimestamp = nowMillis;
    _timerStartTimestamp = _lastUpdateTimestamp;  // Record exact start timestamp
    appState.session.lastUpdateTime = _lastUpdateTimestamp ~/ 1000;
    
    // CRITICAL NEW FIX: Store reference wall time and match time for absolute synchronization
    _referenceWallTime = DateTime.now();
    _referenceMatchTime = _currentMatchTime;
    
    print("--- Timer Starting ---");
    print("  Timestamp (ms): $_lastUpdateTimestamp");
    print("  Match Time    : $_currentMatchTime");
    print("  Reference Time: ${_referenceWallTime.toString()}");
    print("  Period        : ${appState.session.currentPeriod}/${appState.session.matchSegments}");
    print("  Setup Mode    : ${appState.session.isSetup}");
    
    // CRITICAL FIX: Don't activate timer if in setup mode
    if (appState.session.isSetup) {
      print("Session is in setup mode - timer will not count until setup is complete");
      _isTimerActive = false;
      return;
    }
    
    // Set timer as active only if not in setup mode
    _isTimerActive = true;
    
    // Calculate period end time and schedule alarm
    final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
    final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
    
    print("Current period end time: $currentPeriodEndTime (running period ${appState.session.currentPeriod})");
    
    // If we're already past period end time, force end period immediately
    if (_currentMatchTime >= currentPeriodEndTime && 
        appState.session.enableMatchDuration && 
        !appState.session.hasWhistlePlayed &&
        appState.session.currentPeriod < appState.session.matchSegments) {
      print("Match time already past period end, forcing period end");
      _currentMatchTime = currentPeriodEndTime;
      appState.session.matchTime = currentPeriodEndTime;
      _periodEndDetected = true;
      appState.endPeriod();
      appState.session.isPaused = true;
      appState.session.matchRunning = false;
      _isTimerActive = false;
      _notifyPeriodEnd();
      return;
    }
    
    // Update notification with initial match information
    _updateBackgroundNotification(
      _getMatchTimeNotificationText(_currentMatchTime, currentPeriodEndTime, appState.session.currentPeriod, appState.session.matchSegments)
    );
    
    if (appState.session.enableMatchDuration && !appState.session.hasWhistlePlayed) {
      final timeUntilPeriodEnd = currentPeriodEndTime - _currentMatchTime;
      
      if (timeUntilPeriodEnd > 0) {
        _schedulePeriodEndAlarm(timeUntilPeriodEnd, appState);
      }
    }
    
    // Start the timer that will run in both foreground and background
    _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      // Check if timer is active first
      if (!_isTimerActive) {
        print("Timer not active, skipping tick");
        return;
      }
      
      // CRITICAL FIX: Don't increment time if in setup mode
      if (appState.session.isSetup) {
        print("Match in setup mode, not incrementing time");
        return;
      }
      
      // CRITICAL: Use wall-clock time as source of truth for timer updates
      // instead of incrementing our own counter which can drift
      _updateMatchTimeWithWallClock();
      
      // Every 20 seconds, perform authoritative absolute time synchronization to prevent drift
      if (_currentMatchTime % 20 == 0) {
        _performAuthoritativeTimeSync();
      }
      
      // Update notification periodically
      if (DateTime.now().second % 5 == 0) {
        // Calculate period boundary information
        final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
        final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
        
        _updateBackgroundNotification(
          _getMatchTimeNotificationText(_currentMatchTime, currentPeriodEndTime, 
                                        appState.session.currentPeriod, appState.session.matchSegments)
        );
      }
    });
  }

  // Method to update background notification text
  void _updateBackgroundNotification(String message) {
    if (_isRunning) {
      try {
        // According to flutter_background docs, we can't easily update notifications
        // Instead, stop and restart the service with new notification text
        FlutterBackground.disableBackgroundExecution().then((_) {
          // Update config to use the new message
          final updatedConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: 'Soccer Time App',
            notificationText: message,
            notificationImportance: AndroidNotificationImportance.max,
            notificationIcon: const AndroidResource(
              name: 'ic_notification',
              defType: 'drawable',
            ),
            enableWifiLock: false,
          );
          
          // Re-initialize with updated message
          FlutterBackground.initialize(androidConfig: updatedConfig).then((_) {
            // Re-enable background execution with new notification
            FlutterBackground.enableBackgroundExecution();
          });
        });
        
        print("Updated background notification: $message");
      } catch (e) {
        print("Failed to update background notification: $e");
      }
    }
  }

  // Method to update match time using wall-clock precision anchored to reference time on EVERY tick
  void _updateMatchTimeWithWallClock() {
    // Early return if timer is not active (timer is paused)
    if (!_isTimerActive) return;
    if (_currentAppState != null && _currentAppState!.session.isPaused) return;

    final now = DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;

    // Initialize references if null
    if (_referenceWallTime == null) {
      print("WARN: Initializing timing references in tick.");
      _referenceWallTime = now.subtract(Duration(milliseconds: 100)); 
      _referenceMatchTime = _currentMatchTime;
      _lastUpdateTimestamp = nowMillis; // Still useful for sanity checks
      // No need to initialize _lastTickExpectedTotalSeconds or _partialSeconds here
    }

    // Calculate elapsed time since WALL CLOCK REFERENCE point
    final elapsedMillisSinceReference = nowMillis - _referenceWallTime!.millisecondsSinceEpoch;
    if (elapsedMillisSinceReference < 0) { 
      print("WARN: Negative elapsed time since reference ($elapsedMillisSinceReference ms), resetting references.");
      _referenceWallTime = now;
      _referenceMatchTime = _currentMatchTime;
      _lastUpdateTimestamp = nowMillis;
      // Reset other related state if needed, though sync should handle this primarily
      _partialSeconds = 0.0; 
      _lastTickExpectedTotalSeconds = _currentMatchTime.toDouble();
      return; 
    }
    final elapsedSecsSinceReference = elapsedMillisSinceReference / 1000.0;

    // Calculate the authoritative expected integer match time using round() for closer alignment
    final targetMatchTime = (_referenceMatchTime + elapsedSecsSinceReference).round();

    // Store original match time for comparison
    final originalMatchTime = _currentMatchTime;

    // Update match time only if the authoritative target time is ahead
    if (targetMatchTime > _currentMatchTime) {
      final secondsToAdd = targetMatchTime - _currentMatchTime;
      _currentMatchTime = targetMatchTime;
      // Reduce logging frequency - maybe log only every 5-10 seconds?
      if (_currentMatchTime % 5 == 0) { 
        print("Tick Update: $originalMatchTime → $_currentMatchTime (+${secondsToAdd}s, Ref: ${_referenceWallTime!.second}s/${_referenceMatchTime}s, Now: ${now.second}s)");
      }

      // Update AppState immediately
      if (_currentAppState != null) {
        _currentAppState!.session.matchTime = _currentMatchTime;
        _currentAppState!.session.lastUpdateTime = nowMillis ~/ 1000;
      }
      // Notify listeners
      _notifyTimeUpdate(_currentMatchTime);
    } else if (targetMatchTime < _currentMatchTime) {
        // This case indicates a significant issue or time jump backwards, likely requires a sync reset
        print("WARN: Target match time ($targetMatchTime) is LESS than current time ($_currentMatchTime). Waiting for next sync.");
        // Don't reset references here, let the periodic sync handle it cleanly.
    }

    // Update the last actual timestamp
    _lastUpdateTimestamp = nowMillis;

    // No need to update _lastTickExpectedTotalSeconds or _partialSeconds in this approach
  }

  // Replace the _performAbsoluteTimeSync method with an authoritative version
  void _performAuthoritativeTimeSync() {
    if (_currentAppState == null || !_isTimerActive) return;
    
    // Recalculate expected time based on wall clock using milliseconds for precision
    final now = DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;
    final elapsedMillisSinceReference = nowMillis - _referenceWallTime!.millisecondsSinceEpoch;
    final expectedMatchTimeMillis = (_referenceMatchTime * 1000) + elapsedMillisSinceReference;
    final expectedMatchTime = (expectedMatchTimeMillis / 1000).floor(); // Use floor to be conservative
    
    final drift = expectedMatchTime - _currentMatchTime;
    
    print("=== AUTHORITATIVE TIME SYNC ===");
    print("  Ref Wall Time: ${_referenceWallTime.toString()}");
    print("  Current Wall Time: ${now.toString()} ($nowMillis ms)");
    print("  Ref Match Time: $_referenceMatchTime");
    print("  Current Match Time: $_currentMatchTime");
    print("  Expected Match Time (ms calc): $expectedMatchTime");
    print("  Detected Drift: ${drift.toStringAsFixed(2)} seconds");
    
    // Correct time if drift is significant (at least 1 full second)
    if (drift.abs() >= 1.0) {
      print("  CORRECTING TIME: $_currentMatchTime → $expectedMatchTime");
      _currentMatchTime = expectedMatchTime;
      
      // Update AppState immediately
      _currentAppState!.session.matchTime = _currentMatchTime;
      _currentAppState!.session.lastUpdateTime = now.millisecondsSinceEpoch ~/ 1000;
      
      // Notify UI of the update
      _notifyTimeUpdate(_currentMatchTime);
    } else {
      print("  Drift is within tolerance (< 1.0s), no correction needed.");
    }
    
    // Reset reference points and partial seconds for the next interval
    _referenceWallTime = now;
    _referenceMatchTime = _currentMatchTime;
    _partialSeconds = 0.0; // CRITICAL: Reset partial seconds on sync
    _lastTickExpectedTotalSeconds = _currentMatchTime.toDouble(); // CRITICAL: Reset last expected time
    
    print("  New reference wall time: ${_referenceWallTime.toString()}");
    print("  New reference match time: $_referenceMatchTime");
    print("  Partial seconds reset to 0.0");
    print("  Last tick expected reset to: ${_lastTickExpectedTotalSeconds.toStringAsFixed(3)}");
  }

  // Method to sync time when app comes to foreground
  void syncTimeOnResume(AppState appState) {
    // Get high precision timestamps
    final now = DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;
    final nowSecs = nowMillis ~/ 1000;
    
    // Store current state before sync for comparison
    final matchTimeBeforeSync = appState.session.matchTime;
    final lastUpdateTimeBeforeBackground = appState.session.lastUpdateTime;
    final wasTimerActive = _isTimerActive && appState.session.matchRunning && !appState.session.isPaused;
    
    // --- START Detailed Logging ---
    print('--- App Resume Sync (HIGH PRECISION) ---');
    print('  Now          : $nowSecs ($nowMillis ms)');
    print('  Background Entry: $_backgroundEntryTime ms');
    print('  LastKnownMatchTime: $_lastKnownMatchTime');
    print('  LastUpdatePreBG: $lastUpdateTimeBeforeBackground s');
    print('  MatchTimePreSync: $matchTimeBeforeSync');
    print('  CurrentMatchTime (Internal): $_currentMatchTime');
    print('  Timer was active: $wasTimerActive');
    print('  Period ended flag: $_periodEndDetected');
    print('  Match ended flag: $_matchEndDetected');
    // --- END Detailed Logging ---

    // Only update time if timer was active when app went to background
    if (wasTimerActive && _backgroundEntryTime > 0) {
      // Calculate elapsed time since background entry with millisecond precision
      final elapsedMillisRaw = nowMillis - _backgroundEntryTime;
      
      // Add a small fixed compensation for transition overhead (e.g., context switching)
      const transitionCompensationMillis = 500; // 0.5 seconds
      final elapsedMillis = elapsedMillisRaw + transitionCompensationMillis;

      final elapsedSecs = elapsedMillis / 1000.0; // Use compensated value for logging/calcs
      
      print('  Elapsed In BG (Raw): ${(elapsedMillisRaw / 1000.0).toStringAsFixed(3)} secs');
      print('  Compensation Added : ${(transitionCompensationMillis / 1000.0).toStringAsFixed(3)} secs');
      print('  Total Compensated  : ${elapsedSecs.toStringAsFixed(3)} secs');
      
      if (elapsedSecs > 0) { // Check compensated time
        // Calculate the authoritative match time based on wall clock using COMPENSATED milliseconds
        final expectedMatchTimeMillis = (_lastKnownMatchTime * 1000) + elapsedMillis;
        // Use round() here for resume sync accuracy to capture full background duration
        final expectedMatchTime = (expectedMatchTimeMillis / 1000).round();
        
        // Detect drift between expected and internal state (before sync)
        final drift = expectedMatchTime - _currentMatchTime;
        print('  Expected match time (ms calc, round): $expectedMatchTime, internal time: $_currentMatchTime, drift: $drift');
        
        // Set the authoritative match time
        int newMatchTime = expectedMatchTime;
        
        // CRITICAL FIX: Cap the time ONLY if match duration is enabled AND the period end hasn't already been handled
        final currentPeriodEndTime = _getPeriodEndTime(appState);
        if (appState.session.enableMatchDuration &&
            !_periodEndDetected && 
            newMatchTime >= currentPeriodEndTime) { 
          newMatchTime = currentPeriodEndTime;
          print('  Capping time at period end: $currentPeriodEndTime (period end detected during sync)');
          _periodEndDetected = true;
        }
        
        // CRITICAL FIX: Cap the time ONLY if match duration is enabled AND the match end hasn't already been handled
        if (appState.session.enableMatchDuration &&
            !_matchEndDetected && 
            newMatchTime >= appState.session.matchDuration) { 
          newMatchTime = appState.session.matchDuration;
          print('  Capping time at match end: ${appState.session.matchDuration} (match end detected during sync)');
          _matchEndDetected = true;
        }
        
        print('  Final authoritative match time: $newMatchTime (was: $_currentMatchTime)');
        
        // Update internal match time
        _currentMatchTime = newMatchTime;
        
        // Update app state match time
        appState.session.matchTime = newMatchTime;
        
        // CRITICAL: Reset ALL timing references based on THIS sync point
        _referenceWallTime = now;           // Anchor wall clock reference to now
        _referenceMatchTime = _currentMatchTime; // Anchor match time reference to the newly calculated time
        _lastUpdateTimestamp = nowMillis;  // Ensure the next tick calculates delta from now
        _partialSeconds = 0.0;           // Reset fractional accumulator for a clean start
        _timerStartTimestamp = nowMillis; // Also reset the timer start reference if used elsewhere
        _lastTickExpectedTotalSeconds = _currentMatchTime.toDouble(); // CRITICAL: Reset last expected time
        
        appState.session.lastUpdateTime = nowSecs; // Update app state timestamp
        
        print('  RESET references on resume sync:');
        print('    Ref Wall: ${_referenceWallTime.toString()}');
        print('    Ref Match: $_referenceMatchTime');
        print('    Last Update TS: $_lastUpdateTimestamp');
        print('    Partial Seconds: $_partialSeconds');
        print('    Last Tick Expected: ${_lastTickExpectedTotalSeconds.toStringAsFixed(3)}');
      }
    } else {
      print('  No time update needed: timer was not active or no background data');
      
      // Even if no update was strictly needed, reset references to the current time 
      // to prevent issues if the timer is started shortly after.
      _referenceWallTime = now;
      _referenceMatchTime = _currentMatchTime; // Use current time
      _lastUpdateTimestamp = nowMillis;
      _partialSeconds = 0.0; 
      _timerStartTimestamp = nowMillis;
      _lastTickExpectedTotalSeconds = _currentMatchTime.toDouble(); // CRITICAL: Reset last expected time
      print('  RESET references even though no time change occurred.');
    }
    
    // Reset background tracking variables (these are different from timing references)
    _backgroundEntryTime = 0;
    _lastKnownMatchTime = 0;
    
    // Check for period end and match end again after sync
    _checkPeriodEnd();
    _checkMatchEnd();
    
    // Notify UI immediately after sync
    _notifyTimeUpdate(_currentMatchTime);
  }
  
  // Helper method to get the current period end time
  int _getPeriodEndTime(AppState appState) {
    final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
    return periodDuration * appState.session.currentPeriod;
  }

  void stopBackgroundTimer() {
    print("Stopping background timer");
    _isTimerActive = false;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _lastUpdateTimestamp = 0;
    _lastBackgroundTimestamp = 0;
  }

  void pauseTimer() {
    print("Pausing background timer at match time: $_currentMatchTime");
    _isTimerActive = false;
    
    // Cancel the background timer
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    // DON'T reset timestamps - just mark timer as inactive
    // This preserves the timer state for when we resume
    
    // Important: Make sure the timer is not running
    if (_currentAppState != null) {
      _currentAppState!.session.matchRunning = false;
      _currentAppState!.session.isPaused = true;
      
      // Ensure match time is synchronized
      _currentAppState!.session.matchTime = _currentMatchTime;
    }
  }
  
  void resumeTimer() {
    print("Resuming background timer - setting active flag and ensuring timer loop runs.");
    
    // Stop any reminder vibrations when timer is resumed
    stopReminderVibrations();
    
    // --- Simplified --- 
    // DO NOT reset timestamps or partialSeconds here. 
    // syncTimeOnResume is responsible for setting the correct state before this runs.
    
    // Set timer as active - This allows the existing timer loop (if running) 
    // or a newly created one to execute _updateMatchTimeWithWallClock.
    _isTimerActive = true;
    
    // Log current timer state (using the time set by syncTimeOnResume)
    print("Timer marked active. Current Match Time (should be synced): $_currentMatchTime");
    
    // Check immediately if resuming right into a period end state
    // This handles cases where the period ended exactly during the background transition
    if (_currentAppState != null) {
      final periodDuration = _currentAppState!.session.matchDuration ~/ _currentAppState!.session.matchSegments;
      final currentPeriodEndTime = periodDuration * _currentAppState!.session.currentPeriod;
      
      if (_currentMatchTime >= currentPeriodEndTime && 
          _currentAppState!.session.enableMatchDuration && 
          _currentAppState!.session.currentPeriod < _currentAppState!.session.matchSegments &&
          !_currentAppState!.session.hasWhistlePlayed) {
        // Log only when period end is actually detected on resume
        print("PERIOD END DETECTED immediately on resume! Time: $_currentMatchTime, Period End: $currentPeriodEndTime");
        
        // Set flags
        _periodEndDetected = true;
        _periodsTransitioning = true;
        
        // Call endPeriod on app state
        _currentAppState!.endPeriod();
        
        // Don't activate timer (critical)
        _isTimerActive = false;
        
        // Notify period end
        _notifyPeriodEnd();
        
        // Start vibration reminders
        _startReminderVibrations(isPeriodEnd: true, enableVibration: _currentAppState!.session.enableVibration);
        
        // Exit early - prevent timer creation
        return;
      }
    }
    
    // Ensure the Timer.periodic loop is running.
    // If _backgroundTimer is null, create it. If it's already running, this does nothing.
    if (_backgroundTimer == null) {
      print("Background timer was null, creating new Timer.periodic loop.");
      _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        // Standard timer loop logic...
        if (!_isTimerActive) {
          print("Timer marked inactive, cancelling timer loop.");
          timer.cancel();
          _backgroundTimer = null; // Ensure timer is nullified
          return;
        }
        
        _updateMatchTimeWithWallClock();
        _checkPeriodEnd();
        _checkMatchEnd();
        
        // Periodic authoritative sync (moved inside the loop)
        if (_currentMatchTime % 20 == 0 && _currentMatchTime > 0) { // Avoid sync at 0
            _performAuthoritativeTimeSync();
        }
      });
    } else {
      print("Background timer already exists, ensuring it continues.");
    }
  }
  
  // Returns the current match time
  int getCurrentMatchTime() {
    return _currentMatchTime;
  }
  
  // Method to update match time externally (for period transitions etc.)
  void setMatchTime(int newMatchTime) {
    _currentMatchTime = newMatchTime;
    
    // CRITICAL FIX: Reset timer start timestamp when match time is manually changed
    _timerStartTimestamp = DateTime.now().millisecondsSinceEpoch;
    _lastUpdateTimestamp = _timerStartTimestamp;
    
    print("Match time manually updated to $_currentMatchTime");
    print("Timer start timestamp reset to $_timerStartTimestamp");
    
    _notifyTimeUpdate(_currentMatchTime);
    
    // Ensure timer is running if it should be
    if (_isTimerActive && _backgroundTimer == null) {
      // Create a new timer
      _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (!_isTimerActive) {
          timer.cancel();
          return;
        }
        
        // Update match time
        _updateMatchTimeWithWallClock();
        
        // Check for period end
        _checkPeriodEnd();
        
        // Check for match end
        _checkMatchEnd();
      });
      print("Background timer created in setMatchTime");
    }
    
    // Stop reminder vibrations when match time is manually set
    // This happens when starting next period
    stopReminderVibrations();
  }
  
  // Check if timer is active
  bool isTimerActive() {
    return _isTimerActive;
  }

  // Sync AppState with current timer state
  void syncAppState(AppState appState) {
    // CRITICAL FIX: Maintain reference to AppState
    _currentAppState = appState;
    
    appState.session.matchTime = _currentMatchTime;
    appState.session.lastUpdateTime = _lastUpdateTimestamp;
    print("AppState synced with timer: matchTime=$_currentMatchTime, lastUpdateTime=$_lastUpdateTimestamp");
  }

  Future<void> dispose() async {
    print("Disposing BackgroundService");
    stopBackgroundTimer();
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
    await AndroidAlarmManager.cancel(PERIOD_END_ALARM_ID);
    await stopBackgroundService();
    _lastBackgroundTimestamp = null;
    _timeUpdateListeners.clear();
    _periodEndListeners.clear();
    _matchEndListeners.clear();
    resetEventFlags();
  }

  // New methods for vibration in background
  
  // Vibrate with pattern for period end
  void _vibratePeriodEnd() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Strong double vibration for period end
        Vibration.vibrate(pattern: [0, 300, 150, 300], intensities: [0, 255, 0, 255]);
        print("Vibrating for period end");
      }
    } catch (e) {
      print("Error while vibrating for period end: $e");
    }
  }
  
  // Vibrate with pattern for match end
  void _vibrateMatchEnd() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Triple strong vibration pattern for match end
        Vibration.vibrate(pattern: [0, 250, 100, 250, 100, 250], intensities: [0, 255, 0, 255, 0, 255]);
        print("Vibrating for match end");
      }
    } catch (e) {
      print("Error while vibrating for match end: $e");
    }
  }

  // Helper to generate notification text from match time
  String _getMatchTimeNotificationText(int matchTime, int periodEndTime, int currentPeriod, int totalPeriods) {
    // Format match time
    final minutes = matchTime ~/ 60;
    final seconds = matchTime % 60;
    final timeStr = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    
    // Calculate time until period end
    final timeUntilEnd = periodEndTime - matchTime;
    
    // Choose proper period name
    final periodName = totalPeriods == 2 ? 'Half' : 'Quarter';
    
    // Build notification text
    if (timeUntilEnd <= 60 && timeUntilEnd > 5) {
      // Last minute of period
      return "⏱️ $timeStr - $currentPeriod${_getOrdinalSuffix(currentPeriod)} $periodName ends in ${timeUntilEnd}s";
    } else if (timeUntilEnd <= 5 && timeUntilEnd > 0) {
      // Last 5 seconds countdown
      return "⚠️ $timeStr - $timeUntilEnd SECONDS TO PERIOD END! ⚠️";
    } else {
      // Regular time display
      return "⏱️ $timeStr - $currentPeriod${_getOrdinalSuffix(currentPeriod)}/$totalPeriods $periodName";
    }
  }
  
  // Helper for ordinal suffixes
  String _getOrdinalSuffix(int number) {
    if (number % 10 == 1 && number % 100 != 11) return "st";
    if (number % 10 == 2 && number % 100 != 12) return "nd";
    if (number % 10 == 3 && number % 100 != 13) return "rd";
    return "th";
  }

  // Start periodic reminder vibrations
  void _startReminderVibrations({bool isPeriodEnd = false, bool isMatchEnd = false, required bool enableVibration}) {
    // Cancel any existing timer
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
    
    // Check if vibration is enabled
    if (!enableVibration) {
      print("Reminder vibrations not started: vibration disabled in settings");
      return;
    }
    
    print("Starting reminder vibrations for ${isMatchEnd ? 'match end' : 'period end'}");
    
    // Create a new timer that fires every 10 seconds
    _reminderVibrationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      // Check if the timer is still needed - stop if not
      if (_isTimerActive && !_periodEndDetected && !_matchEndDetected) {
        print("Stopping reminder vibrations - timer active and no events detected");
        timer.cancel();
        _reminderVibrationTimer = null;
        return;
      }
      
      print("Vibrating Match End Reminder");
      
      // Send the appropriate vibration
      if (isMatchEnd) {
        _vibrateMatchEndReminder();
      } else if (isPeriodEnd) {
        _vibratePeriodEndReminder();
      }
    });
  }
  
  // Vibrate pattern for period end reminder
  void _vibratePeriodEndReminder() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Two short pulses for period end reminder
        Vibration.vibrate(
          pattern: [0, 120, 100, 120], 
          intensities: [0, 180, 0, 180]
        );
        print("Vibrating period end reminder");
      }
    } catch (e) {
      print("Error while vibrating for period end reminder: $e");
    }
  }
  
  // Vibrate pattern for match end reminder
  void _vibrateMatchEndReminder() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Three short pulses for match end reminder
        Vibration.vibrate(
          pattern: [0, 120, 100, 120, 100, 120], 
          intensities: [0, 220, 0, 220, 0, 220]
        );
        print("Vibrating match end reminder");
      }
    } catch (e) {
      print("Error while vibrating for match end reminder: $e");
    }
  }

  // Add a new method to stop reminder vibrations
  void stopReminderVibrations() {
    print("Stopping all reminder vibrations");
    
    // Cancel the timer
    if (_reminderVibrationTimer != null) {
      print("Cancelling reminder vibration timer");
      _reminderVibrationTimer?.cancel();
      _reminderVibrationTimer = null;
    }
    
    // Cancel any ongoing vibrations
    try {
      Vibration.cancel();
    } catch (e) {
      print("Error cancelling vibration: $e");
    }
    
    // Reset flags that trigger vibrations
    _periodEndDetected = false;
    _matchEndDetected = false;
  }

  // Schedule an alarm to wake up before period end
  Future<void> _schedulePeriodEndAlarm(int secondsUntilPeriodEnd, AppState appState) async {
    // Cancel any existing alarm first
    await AndroidAlarmManager.cancel(PERIOD_END_ALARM_ID);
    
    // Calculate when to wake up - exactly 5 seconds before period end
    final wakeupTime = DateTime.now().add(Duration(seconds: secondsUntilPeriodEnd - 5));
    
    print("Scheduling period end alarm for: $wakeupTime");
    print("Current match time: ${appState.session.matchTime}, Seconds until period end: $secondsUntilPeriodEnd");
    
    // Store the expected period end time and settings for validation
    final prefs = await SharedPreferences.getInstance();
    final expectedEndTime = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secondsUntilPeriodEnd;
    await prefs.setInt('expected_period_end', expectedEndTime);
    
    // Store both sound and vibration settings
    await prefs.setBool('vibration_enabled', appState.session.enableVibration);
    await prefs.setBool('sound_enabled', appState.session.enableSound);
    
    // Schedule exact alarm that will wake up the device
    await AndroidAlarmManager.oneShot(
      Duration(seconds: secondsUntilPeriodEnd - 5),
      PERIOD_END_ALARM_ID,
      _handlePeriodEndAlarm,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      alarmClock: true, // This ensures the alarm will fire even in doze mode
    );
  }
  
  // Static callback for the alarm
  @pragma('vm:entry-point')
  static void _handlePeriodEndAlarm() async {
    print("Period end alarm triggered!");
    
    // Get the singleton instance
    final instance = BackgroundService();
    
    // Get the shared preferences to check expected end time and settings
    final prefs = await SharedPreferences.getInstance();
    final expectedEndTime = prefs.getInt('expected_period_end') ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    print("Expected period end time: $expectedEndTime");
    print("Current time: $currentTime");
    
    // If we're more than 30 seconds before the expected end time, don't trigger
    if (currentTime < expectedEndTime - 30) {
      print("Alarm triggered too early, ignoring!");
      return;
    }
    
    // Check both sound and vibration settings
    final vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    final soundEnabled = prefs.getBool('sound_enabled') ?? false;
    
    print("Sound enabled: $soundEnabled, Vibration enabled: $vibrationEnabled");
    
    // Only vibrate if enabled
    if (vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      // Start countdown vibrations with precise timing
      for (int i = 5; i > 0; i--) {
        print("Countdown vibration: $i seconds remaining");
        
        // Calculate vibration parameters based on remaining time
        final duration = 150 + ((5 - i) * 30);  // 150ms to 270ms
        final intensity = 128 + ((5 - i) * 25);  // 128 to 228
        
        // Vibrate with increasing intensity
        await Vibration.vibrate(duration: duration, amplitude: intensity);
        
        if (i > 1) {
          // Wait exactly one second minus the vibration duration
          final waitTime = 1000 - duration;
          await Future.delayed(Duration(milliseconds: waitTime));
        }
      }
    }
  }

  void _checkPeriodEnd() {
    if (!_isTimerActive || _periodEndDetected || _periodsTransitioning) {
      print("_checkPeriodEnd: Early return - timer not active or period already detected");
      return;
    }
    
    if (_currentAppState == null) {
      print("_checkPeriodEnd: Early return - currentAppState is null");
      return;
    }
    
    final currentTime = _currentMatchTime;
    final periodDuration = _currentAppState!.session.matchDuration ~/ _currentAppState!.session.matchSegments;
    final currentPeriodEndTime = periodDuration * _currentAppState!.session.currentPeriod;
    final isFinalPeriod = _currentAppState!.session.currentPeriod >= _currentAppState!.session.matchSegments;
    final matchDurationEnabled = _currentAppState!.session.enableMatchDuration;
    final hasWhistlePlayed = _currentAppState!.session.hasWhistlePlayed;
    
    // Debug log all relevant period information
    print("_checkPeriodEnd: Checking period conditions");
    print("  Current Time: $currentTime");
    print("  Period End Time: $currentPeriodEndTime");
    print("  Period: ${_currentAppState!.session.currentPeriod}/${_currentAppState!.session.matchSegments}");
    print("  Final Period: $isFinalPeriod");
    print("  Match Duration Enabled: $matchDurationEnabled");
    print("  Has Whistle Played: $hasWhistlePlayed");
    print("  Registered Listeners: ${_periodEndListeners.length}");
    
    // Only check for period end if match duration is enabled and it's not the final period
    if (matchDurationEnabled && !isFinalPeriod) {
      print("_checkPeriodEnd: Period end tracking enabled");
      
      if (currentTime >= currentPeriodEndTime && !_periodEndDetected && !hasWhistlePlayed) {
        print("\n\n🔔🔔🔔 PERIOD END DETECTED in background service! 🔔🔔🔔");
        print("Current time: $currentTime has reached period end time: $currentPeriodEndTime\n\n");
        
        // Set the flags to prevent multiple notifications
        _periodEndDetected = true;
        _periodsTransitioning = true;
        
        // Immediately pause the timer
        _isTimerActive = false;
        
        // Call end period on app state
        print("Calling endPeriod() on AppState");
        _currentAppState!.endPeriod();
        
        // Update app state pause flags
        _currentAppState!.session.matchRunning = false;
        _currentAppState!.session.isPaused = true;
        
        // Start vibration reminders if vibration is enabled
        _startReminderVibrations(isPeriodEnd: true, enableVibration: _currentAppState!.session.enableVibration);
        
        // Notify listeners using the dedicated method
        print("Notifying period end listeners (count: ${_periodEndListeners.length})");
        _notifyPeriodEnd();
        
        // Cancel the timer to completely stop it, not just pause it
        _backgroundTimer?.cancel();
        _backgroundTimer = null;
        
        print("Period end sequence complete");
      } else {
        print("_checkPeriodEnd: Period end conditions not met yet");
      }
    } else {
      print("_checkPeriodEnd: Period end tracking disabled or in final period");
    }
  }

  void _checkMatchEnd() {
    if (!_isTimerActive || _matchEndDetected) return;
    
    if (_currentAppState == null) return;
    
    final currentTime = _currentMatchTime;
    
    if (currentTime >= _currentAppState!.session.matchDuration && !_matchEndDetected) {
      print("MATCH END DETECTED in background service!");
      _matchEndDetected = true;
      _isTimerActive = false;
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      
      // Call endMatch on app state
      _currentAppState!.endMatch();
      
      // Start vibration reminders if enabled
      _startReminderVibrations(isMatchEnd: true, enableVibration: _currentAppState!.session.enableVibration);
      
      // Notify listeners using the dedicated method
      _notifyMatchEnd();
      
      // Don't stop the background service yet - we need it for reminders
    }
  }

  // Method to handle screen focus changes
  void onScreenFocusChange(bool hasFocus) {
    print("Screen focus changed: hasFocus=$hasFocus");
    
    // Simple functionality for now - just handle the focus change
    if (hasFocus && _isTimerActive && _backgroundTimer == null) {
      print("Screen regained focus with active timer - recreating timer");
      _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (!_isTimerActive) {
          timer.cancel();
          return;
        }
        
        // Update match time
        _updateMatchTimeWithWallClock();
        
        // Check for period end
        _checkPeriodEnd();
        
        // Check for match end
        _checkMatchEnd();
      });
    }
  }

  // Add this method to track when the app goes to background
  void onAppBackground() {
    print("App going to background - recording state");
    
    // Record timestamp and match time when entering background
    _backgroundEntryTime = DateTime.now().millisecondsSinceEpoch;
    _lastKnownMatchTime = _currentMatchTime;
    
    // Add verification log
    print("VERIFY - Service State Set: _backgroundEntryTime=$_backgroundEntryTime, _lastKnownMatchTime=$_lastKnownMatchTime");
    
    print("Background entry time: $_backgroundEntryTime");
    print("Last known match time: $_lastKnownMatchTime");
  }
} 