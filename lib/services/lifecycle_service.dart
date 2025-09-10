import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/background_service.dart';

/// Service class to handle app lifecycle management with identical behavior
class LifecycleService {
  static final LifecycleService _instance = LifecycleService._internal();
  factory LifecycleService() => _instance;
  LifecycleService._internal();

  final BackgroundService _backgroundService = BackgroundService();

  // Track exact timestamps for background transitions
  int? _backgroundEntryTime;
  int? _lastKnownMatchTime;
  bool _isInitialized = false;

  /// Initialize the lifecycle service
  void initialize() {
    _isInitialized = true;
  }

  /// Handle app lifecycle state changes with identical behavior to original
  void handleAppLifecycleStateChange(
    BuildContext context,
    AppLifecycleState state, {
    required VoidCallback onResume,
    required VoidCallback onPause,
    required VoidCallback onInactive,
  }) {
    print("App lifecycle state changed to: $state");
    
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed(context, onResume);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _handleAppPausedOrInactive(context, state, onPause, onInactive);
    }
  }

  /// Handle app resumed state with identical behavior
  void _handleAppResumed(BuildContext context, VoidCallback onResume) {
    // App came to foreground
    final resumeTime = DateTime.now().millisecondsSinceEpoch;
    print("App resumed at $resumeTime");
    
    if (_isInitialized) {
      final appState = Provider.of<AppState>(context, listen: false);
      
      // CRITICAL FIX: Immediately start UI timer to prevent stalling
      if (appState.session.matchRunning && !appState.session.isPaused) {
        print("Immediately starting UI refresh timer to prevent stalling");
        onResume(); // This should start the timer with zero delay
      }
      
      // Sync the match time using the authoritative method in the background service
      _backgroundService.syncTimeOnResume(appState);
      
      // Reset event flags in the background service
      _backgroundService.resetEventFlags();
      
      // If match was running when app went to background, resume timer
      if (appState.session.matchRunning && !appState.session.isPaused) {
        print("Resuming background timer because match is running and not paused");
        _backgroundService.resumeTimer();
      }
    }
    
    // Reset background tracking variables
    _backgroundEntryTime = null;
    _lastKnownMatchTime = null;
  }

  /// Handle app paused or inactive state with identical behavior
  void _handleAppPausedOrInactive(
    BuildContext context,
    AppLifecycleState state,
    VoidCallback onPause,
    VoidCallback onInactive,
  ) {
    final transitionState = state;
    print("App lifecycle transition to: $transitionState");
    
    // Track when we enter background state
    if (_backgroundEntryTime == null) {
      _backgroundEntryTime = DateTime.now().millisecondsSinceEpoch;
      print("Background entry time recorded: $_backgroundEntryTime");
      
      // Store the current match time when entering background
      final appState = Provider.of<AppState>(context, listen: false);
      _lastKnownMatchTime = appState.session.matchTime;
      print("Last known match time: $_lastKnownMatchTime");
    }
    
    if (_isInitialized) {
      final appState = Provider.of<AppState>(context, listen: false);
      
      // Cancel UI refresh timer ONLY when paused (inactive might just be temporary)
      if (state == AppLifecycleState.paused) {
        print("Cancelling UI refresh timer due to paused state.");
        onPause(); // This should cancel the timer
      } else {
        onInactive(); // Handle inactive state
      }
      
      // Sync state and notify service ONCE per transition
      // Check if _backgroundEntryTime was just set to avoid double calls
      if (_backgroundEntryTime != null && _lastKnownMatchTime != null) { 
        print("Ensuring background service state is synced (state: $transitionState)");
        _backgroundService.syncAppState(appState);
        print("!!! lifecycle_service: Calling _backgroundService.onAppBackground() (state: $transitionState) !!!"); 
        _backgroundService.onAppBackground();
      } else {
        print("!!! lifecycle_service: Skipping call to onAppBackground - background time not set yet (state: $transitionState)");
      }
      
      // Start background service if needed (typically on paused)
      if (state == AppLifecycleState.paused && appState.session.matchRunning && !appState.session.isPaused) {
        if (!_backgroundService.isRunning) {
          print("Attempting to start background service due to paused state.");
          _backgroundService.startBackgroundService().then((success) {
            print("Background service start attempt complete (success: $success)");
          });
        }
      }
    } else {
      print("!!! lifecycle_service: Lifecycle change ($transitionState) but _isInitialized is FALSE !!!");
    }
  }

  /// Check if background timers need to be reset after session reset
  void checkBackgroundTimersAfterReset(AppState appState) {
    if (!_isInitialized) return;
    
    // Check if session was reset (match time is 0 and not paused)
    if (appState.session.matchTime == 0 && !appState.session.isPaused) {
      print("Session appears to have been reset, ensuring background timers are stopped");
      
      // Stop any running background timers
      if (_backgroundService.isTimerActive()) {
        print("Stopping background timer due to session reset");
        _backgroundService.pauseTimer();
      }
      
      // Reset background service state
      _backgroundService.resetEventFlags();
      
      // Reset our tracking variables
      _backgroundEntryTime = null;
      _lastKnownMatchTime = null;
    }
  }

  /// Get current background entry time
  int? get backgroundEntryTime => _backgroundEntryTime;

  /// Get last known match time
  int? get lastKnownMatchTime => _lastKnownMatchTime;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Reset lifecycle tracking variables
  void reset() {
    _backgroundEntryTime = null;
    _lastKnownMatchTime = null;
  }
}
