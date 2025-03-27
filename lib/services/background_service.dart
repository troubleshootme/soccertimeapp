import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import '../providers/app_state.dart';

class BackgroundService {
  static const String BACKGROUND_ENABLED_KEY = 'background_service_enabled';
  
  // Singleton instance
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;
  Timer? _backgroundTimer;
  Timer? _reminderVibrationTimer; // Add timer for periodic vibration reminders
  int? _lastBackgroundTimestamp;
  bool _periodEndDetected = false;
  bool _matchEndDetected = false;

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
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    print("Initializing background service...");
    
    // Request Android permissions explicitly
    await _requestPermissions();
    
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
    if (_isRunning) {
      final success = await FlutterBackground.disableBackgroundExecution();
      if (success) {
        _isRunning = false;
        // Save the state to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(BACKGROUND_ENABLED_KEY, false);
        debugPrint('Background service stopped successfully');
      } else {
        debugPrint('Failed to stop background service');
      }
      return success;
    }
    
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

  void startBackgroundTimer(AppState appState) {
    _backgroundTimer?.cancel();
    
    // Reset event flags
    _periodEndDetected = false;
    _matchEndDetected = false;
    
    // Store initial timestamp when starting the background timer
    _lastBackgroundTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    appState.session.lastUpdateTime = _lastBackgroundTimestamp;
    
    print("--- BG Timer Starting ---");
    print("  Timestamp (s) : $_lastBackgroundTimestamp");
    print("  Match Time    : ${appState.session.matchTime}");
    print("  Period        : ${appState.session.currentPeriod}/${appState.session.matchSegments}");
    
    // Calculate period end time for more accurate checking
    final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
    final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
    print("Current period end time: $currentPeriodEndTime (running period ${appState.session.currentPeriod})");
    
    // Update notification with initial match information
    _updateBackgroundNotification(
      _getMatchTimeNotificationText(appState.session.matchTime, currentPeriodEndTime, appState.session.currentPeriod, appState.session.matchSegments)
    );
    
    _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (appState.session.matchRunning && !appState.session.isPaused) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // Use appState's lastUpdateTime as the *single source of truth* for last update time
        final lastUpdate = appState.session.lastUpdateTime ?? now; // Fallback to now if null
        final elapsed = now - lastUpdate;

        // --- START Detailed Logging ---
        print('--- BG Timer Tick ---');
        print('  Now        : $now s');
        print('  LastUpdate : $lastUpdate s');
        print('  Elapsed    : $elapsed s');
        // --- END Detailed Logging ---

        if (elapsed > 0) {
          final oldMatchTime = appState.session.matchTime;
          
          // Calculate period boundary information
          final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
          final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
          
          // Check for period countdown vibration (last 5 seconds)
          if (appState.session.enableMatchDuration && 
              appState.session.enableVibration && 
              !appState.session.hasWhistlePlayed) {
              
            final timeUntilPeriodEnd = currentPeriodEndTime - oldMatchTime;
            
            // If we're in the last 5 seconds of the period, trigger vibration
            if (timeUntilPeriodEnd <= 5 && timeUntilPeriodEnd > 0) {
              // Only vibrate once per second by tracking the last vibration time
              final shouldVibrate = oldMatchTime > (appState.session.lastVibrationSecond ?? -1);
              
              if (shouldVibrate) {
                // Trigger vibration - intensity increases as we get closer to end
                _vibrateCountdown(timeUntilPeriodEnd.toInt());
                
                // Update last vibration time to current match time
                appState.session.lastVibrationSecond = oldMatchTime;
                
                print("Background vibration at T-${timeUntilPeriodEnd.toInt()} seconds to period end");
                
                // Update notification to show countdown
                final periodName = appState.session.matchSegments == 2 ? 'Half' : 'Quarter';
                final countdownText = "⚠️ ${timeUntilPeriodEnd.toInt()} SECONDS TO ${appState.session.currentPeriod}${_getOrdinalSuffix(appState.session.currentPeriod)} $periodName END! ⚠️";
                _updateBackgroundNotification(countdownText);
              }
            }
          }
          
          // Check if this update would cross the period boundary
          final wouldCrossPeriodBoundary = oldMatchTime < currentPeriodEndTime && 
              oldMatchTime + elapsed >= currentPeriodEndTime;
              
          // If we would cross the boundary, set time exactly to the period end
          if (wouldCrossPeriodBoundary && 
              appState.session.enableMatchDuration && 
              !appState.session.hasWhistlePlayed &&
              appState.session.currentPeriod < appState.session.matchSegments) {
              
            print("Background timer would cross period boundary - forcing exact end time");
            
            // Set match time to exactly the period end time
            appState.session.matchTime = currentPeriodEndTime;
            
            // Update player times up to the period end
            for (var playerName in appState.session.players.keys) {
              final player = appState.session.players[playerName]!;
              if (player.active && player.lastActiveMatchTime != null) {
                final timeToAdd = currentPeriodEndTime - player.lastActiveMatchTime!;
                if (timeToAdd > 0) {
                  player.totalTime += timeToAdd;
                  player.lastActiveMatchTime = null; // Reset as player will be deactivated
                }
              }
            }
            
            // Record that a period end was detected
            _periodEndDetected = true;
            
            // Call endPeriod to handle pausing and state changes
            appState.endPeriod();
            
            // Trigger a strong period-end vibration
            if (appState.session.enableVibration) {
              _vibratePeriodEnd();
            }
            
            // Update lastUpdateTime to now
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now;
            
            // Update notification to show period ended
            final periodName = appState.session.matchSegments == 2 ? 'Half' : 'Quarter';
            final periodEndText = "🔔 ${appState.session.currentPeriod}${_getOrdinalSuffix(appState.session.currentPeriod)} $periodName ENDED! 🔔 Vibrating every 10s until you return";
            _updateBackgroundNotification(periodEndText);
            
            print("Period ended in background at exactly $currentPeriodEndTime");
            
            // Start periodic reminder vibrations with vibration setting
            _startReminderVibrations(isPeriodEnd: true, enableVibration: appState.session.enableVibration);
            
            // Pause the match
            appState.session.isPaused = true;
            appState.session.matchRunning = false;
          }
          // Check if this update would cross the match end boundary in final period
          else if (appState.session.enableMatchDuration && 
              appState.session.currentPeriod >= appState.session.matchSegments &&
              oldMatchTime < appState.session.matchDuration && 
              oldMatchTime + elapsed >= appState.session.matchDuration &&
              !appState.session.isMatchComplete) {
              
            print("Background timer would cross match end boundary - forcing exact end time");
            
            // Set match time to exactly the match duration
            appState.session.matchTime = appState.session.matchDuration;
            
            // Update player times up to the match end
            for (var playerName in appState.session.players.keys) {
              final player = appState.session.players[playerName]!;
              if (player.active && player.lastActiveMatchTime != null) {
                final timeToAdd = appState.session.matchDuration - player.lastActiveMatchTime!;
                if (timeToAdd > 0) {
                  player.totalTime += timeToAdd;
                  player.lastActiveMatchTime = null; // Reset as player will be deactivated
                }
              }
            }
            
            // Record that a match end was detected
            _matchEndDetected = true;
            
            // Call endMatch to handle state changes
            appState.endMatch();
            
            // Trigger a strong match-end vibration
            if (appState.session.enableVibration) {
              _vibrateMatchEnd();
            }
            
            // Update lastUpdateTime to now
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now;
            
            // Update notification to show match ended
            _updateBackgroundNotification("🏁 MATCH COMPLETED! 🏁 Vibrating every 10s until you return");
            
            print("Match ended in background at exactly ${appState.session.matchDuration}");
            
            // Start periodic reminder vibrations with vibration setting
            _startReminderVibrations(isMatchEnd: true, enableVibration: appState.session.enableVibration);
            
            // Mark match as complete
            appState.session.isMatchComplete = true;
            
            // Pause the match
            appState.session.isPaused = true;
            appState.session.matchRunning = false;
          }
          // Normal time update - no boundary crossing
          else {
            // --- More Logging ---
            final timeBeforeUpdate = appState.session.matchTime;
            // Update match time using AppState's method (pass elapsed seconds)
            appState.updateMatchTimer(elapsedSeconds: elapsed);
            final newMatchTime = appState.session.matchTime;
            print('  UpdateType : Normal Tick');
            print('  OldMatchTime: $timeBeforeUpdate');
            print('  NewMatchTime: $newMatchTime');
            if (newMatchTime < timeBeforeUpdate) {
               print('  *** WARNING: BG Timer decreased! Old: $timeBeforeUpdate, New: $newMatchTime ***');
            }
            // --- End More Logging ---

            // Store timestamp of last update *after* update occurs
            // CRITICAL: Update AppState's timestamp
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now; // Keep local copy for reference if needed

            // Update notification text periodically
            if (elapsed >= 5 || newMatchTime % 5 == 0) { // Update every 5 seconds
              final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
              final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
              _updateBackgroundNotification(
                _getMatchTimeNotificationText(newMatchTime, currentPeriodEndTime, appState.session.currentPeriod, appState.session.matchSegments)
              );
            }
          }
        } else if (elapsed < 0) {
            // Handle potential clock adjustments
            print("Warning: BG Timer clock adjustment detected (elapsed time negative: $elapsed). Resetting last update time.");
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now;
        }
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

  // Sync time when app resumes
  void syncTimeOnResume(AppState appState) {
    // Use AppState's lastUpdateTime directly
    final lastUpdateTimeBeforeBackground = appState.session.lastUpdateTime;
    final matchTimeBeforeSync = appState.session.matchTime; // Capture time before sync

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final nowSecs = nowMillis ~/ 1000;

    // --- START Detailed Logging ---
    print('--- App Resume Sync ---');
    print('  Now          : $nowSecs ($nowMillis ms)');
    print('  LastUpdatePreBG: $lastUpdateTimeBeforeBackground s');
    print('  MatchTimePreSync: $matchTimeBeforeSync');
    // --- END Detailed Logging ---


    if (lastUpdateTimeBeforeBackground != null) {
      // Calculate elapsed time since the *last update before background*
      final elapsedInBackground = nowSecs - lastUpdateTimeBeforeBackground;

      print('  Elapsed In BG: $elapsedInBackground secs');

      if (elapsedInBackground > 0) {
        // Calculate new time based on time *before* sync
        final newMatchTime = matchTimeBeforeSync + elapsedInBackground;

        // --- More Logging ---
        print('  Calculated New Time: $newMatchTime');
        if (newMatchTime < matchTimeBeforeSync) {
           print('  *** WARNING: Synced time decreased! Old: $matchTimeBeforeSync, New: $newMatchTime ***');
        }
        // --- End More Logging ---

        // Apply the sync adjustment directly to AppState
        appState.session.matchTime = newMatchTime;
        // Update player times based on elapsed time during background
        appState.updatePlayerTimesForBackgroundSync(elapsedInBackground); // Need this new method in AppState

      } else if (elapsedInBackground < 0) {
        print('  *** WARNING: Negative elapsed time calculated during sync! Clock jump? ***');
        // Don't adjust time backwards
      } else {
        print('  No elapsed time detected in background for sync.');
      }
    } else {
      print('  Cannot sync: lastUpdateTimeBeforeBackground is null.');
    }

    // CRITICAL: Update lastUpdateTime to NOW, regardless of sync result
    appState.session.lastUpdateTime = nowSecs;
    print('  Updated lastUpdateTime to: $nowSecs');

  }

  void stopBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> dispose() async {
    print("Disposing BackgroundService"); // Added log
    stopBackgroundTimer();
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
    await stopBackgroundService();
    _lastBackgroundTimestamp = null;
    resetEventFlags();
  }

  // New methods for vibration in background
  
  // Vibrate with appropriate pattern for countdown (5, 4, 3, 2, 1 seconds)
  void _vibrateCountdown(int secondsRemaining) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Intensity increases as countdown decreases
        final amplitude = 128 + ((5 - secondsRemaining) * 25); // 128-228 range
        final duration = 80 + ((5 - secondsRemaining) * 20); // 80-160ms range
        
        Vibration.vibrate(duration: duration, amplitude: amplitude);
        print("Vibrating for countdown: $secondsRemaining seconds left, amplitude: $amplitude, duration: $duration");
      }
    } catch (e) {
      print("Error while vibrating for countdown: $e");
    }
  }
  
  // Vibrate with pattern for period end
  void _vibratePeriodEnd() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Double strong vibration pattern for period end
        Vibration.vibrate(pattern: [0, 200, 100, 200], intensities: [0, 255, 0, 255]);
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
    
    // Check if vibration is enabled
    if (!enableVibration) {
      print("Reminder vibrations not started: vibration disabled in settings");
      return;
    }
    
    print("Starting reminder vibrations for ${isMatchEnd ? 'match end' : 'period end'}");
    
    // Create a new timer that fires every 10 seconds
    _reminderVibrationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      // We'll rely on the initial check, since we have no way to check settings later
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
    if (_reminderVibrationTimer != null) {
      print("Stopping reminder vibrations");
      _reminderVibrationTimer?.cancel();
      _reminderVibrationTimer = null;
    }
  }
} 