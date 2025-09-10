import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/background_service.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../services/dialog_service.dart';
import 'dart:async';

/// Widget class to handle all timer-related functionality including background service integration
class MatchTimerWidget extends StatefulWidget {
  final ValueNotifier<int> matchTimeNotifier;
  final VoidCallback? onPeriodEnd;
  final VoidCallback? onMatchEnd;
  final VoidCallback? onTimeUpdate;
  final VoidCallback? onTimerStateChange;

  const MatchTimerWidget({
    Key? key,
    required this.matchTimeNotifier,
    this.onPeriodEnd,
    this.onMatchEnd,
    this.onTimeUpdate,
    this.onTimerStateChange,
  }) : super(key: key);

  @override
  _MatchTimerWidgetState createState() => _MatchTimerWidgetState();
}

class _MatchTimerWidgetState extends State<MatchTimerWidget> {
  // Timer state variables
  int _matchTime = 0;
  bool _isPaused = false;
  Timer? _matchTimer;
  bool _isInitialized = false;

  // Services
  late final AudioService _audioService;
  late final HapticService _hapticService;
  final BackgroundService _backgroundService = BackgroundService();
  final DialogService _dialogService = DialogService();

  // UI update optimization
  DateTime _lastUIUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _hapticService = HapticService();
    _initializeTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Set the context for the AudioService
    _audioService.setContext(context);
    
    // Get AppState
    final appState = Provider.of<AppState>(context, listen: true);
    
    // Check if this is initial setup
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Do initial setup if needed
      if (appState.session.matchRunning && !appState.session.isPaused && !appState.session.isSetup) {
        // Match is already running, start the timer
        print("Match is already running at initialization, starting timers");
        startTimer();
      }
    }
    
    // Check if we should reset background timers when session is reset
    _checkBackgroundTimersAfterReset(appState);
  }

  @override
  void dispose() {
    // Cleanup
    _matchTimer?.cancel();
    
    // Remove listeners from background service
    _backgroundService.removeTimeUpdateListener(_onTimeUpdate);
    _backgroundService.removePeriodEndListener(_onPeriodEnd);
    _backgroundService.removeMatchEndListener(_onMatchEnd);
    
    super.dispose();
  }

  /// Initialize timer with background service integration
  void _initializeTimer() {
    // Initialize the background service
    _backgroundService.initialize().then((_) {
      // Restore the background service if it was previously running
      _backgroundService.restorePreviousState();
      
      // Register for time updates from the background service
      _backgroundService.addTimeUpdateListener(_onTimeUpdate);
      _backgroundService.addPeriodEndListener(_onPeriodEnd);
      _backgroundService.addMatchEndListener(_onMatchEnd);
    });
  }

  /// Check if background timers need to be reset after session reset
  void _checkBackgroundTimersAfterReset(AppState appState) {
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
    }
  }

  /// Handler for time updates from the BackgroundService
  void _onTimeUpdate(int newMatchTime) {
    if (mounted) {
      setState(() {
        _matchTime = newMatchTime;
        widget.matchTimeNotifier.value = newMatchTime;
      });
      
      // Notify parent of time update
      widget.onTimeUpdate?.call();
    }
  }

  /// Handler for period end events from BackgroundService
  void _onPeriodEnd() {
    print("\n\n🔔🔔🔔 _onPeriodEnd handler called in MatchTimerWidget! 🔔🔔🔔\n\n");
    
    if (!mounted) {
      print("CRITICAL ERROR: _onPeriodEnd called but widget not mounted!");
      return;
    }
    
    final appState = Provider.of<AppState>(context, listen: false);
    print("Current period in appState: ${appState.session.currentPeriod}");
    print("periodsTransitioning flag: ${appState.periodsTransitioning}");
    
    // Force UI update to ensure we have the latest state
    setState(() {
      _isPaused = true; // Ensure we show as paused
    });
    
    // Use addPostFrameCallback to ensure dialog appears after any pending UI updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        print("Showing period end dialog for period ${appState.session.currentPeriod}");
        // Show period end dialog using DialogService
        _dialogService.showPeriodEndDialog(context, appState.session.currentPeriod);
      } else {
        print("CRITICAL ERROR: Widget no longer mounted in post-frame callback!");
      }
    });
    
    // Notify parent of period end
    widget.onPeriodEnd?.call();
  }

  /// Handler for match end events from BackgroundService
  void _onMatchEnd() {
    if (mounted) {
      // Show match end dialog using DialogService
      _dialogService.showPeriodEndDialog(
        context,
        0, // period number doesn't matter for match end
        isMatchEnd: true,
      );
    }
    
    // Notify parent of match end
    widget.onMatchEnd?.call();
  }

  /// Start the match timer with identical behavior to original
  void startTimer({int initialDelay = 500}) {
    final appState = Provider.of<AppState>(context, listen: false);

    // CRITICAL FIX: Add a check for setup mode to prevent timer from running prematurely
    if (appState.session.isSetup) {
      print("WARNING: Attempted to start match timer while in setup mode - this should not happen");
      return;
    }
    
    // Cancel any existing foreground timer first
    _matchTimer?.cancel();
    _matchTimer = null;
    
    // Make sure background service is initialized
    _backgroundService.initialize().then((_) {
      print("Starting match timer - isSetup=${appState.session.isSetup}, isPaused=${appState.session.isPaused}");
      
      // Start the background timer with current app state
      _backgroundService.startBackgroundTimer(appState);
      
      // Notify background service that match has started
      _backgroundService.onMatchStart();
      
      // Set UI state to match timer state
      setState(() {
        _isPaused = false;
      });
      
      // Update app state to show match is running and not paused
      appState.session.matchRunning = true;
      appState.session.isPaused = false;
      
      // Start a new UI refresh timer with the specified initial delay
      _matchTimer = Timer.periodic(Duration(milliseconds: initialDelay), (timer) {
        // Check if we should stop the UI timer
        if (!mounted) {
          print("UI not mounted, cancelling UI refresh timer");
          timer.cancel();
          return;
        }

        // Check if app is paused - don't update if paused
        if (_isPaused || appState.session.isPaused) {
          // Don't update times while paused
          return;
        }

        // Get background timer status
        final backgroundTime = _backgroundService.getCurrentMatchTime();
        final backgroundIsActive = _backgroundService.isTimerActive();
        
        if (backgroundIsActive) {
          // Update match time from background service
          _updateMatchTime(backgroundTime);
          
          // Check for period end
          _checkPeriodEnd();
          
          // Check for match end
          _checkMatchEnd();
        } else {
          // Background timer is not active, stop UI timer
          print("Background timer not active, stopping UI timer");
          timer.cancel();
          _matchTimer = null;
        }
      });
      
      print("UI refresh timer started after match start");
    });
    
    // Notify parent of timer state change
    widget.onTimerStateChange?.call();
  }

  /// Stop the match timer with identical behavior to original
  void stopTimer() {
    // Cancel UI refresh timer
    _matchTimer?.cancel();
    _matchTimer = null;

    // Pause the background timer
    _backgroundService.pauseTimer();
    
    // Notify background service that match is paused
    _backgroundService.onMatchPause();
    
    // Update UI state
    setState(() {
      _isPaused = true;
    });
    
    // Update app state
    final appState = Provider.of<AppState>(context, listen: false);
    appState.session.isPaused = true;
    
    // Notify parent of timer state change
    widget.onTimerStateChange?.call();
  }

  /// Reset the match with identical behavior to original
  void resetMatch() {
    // Get app state
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Stop timers
    _matchTimer?.cancel();
    _matchTimer = null;
    _backgroundService.stopBackgroundTimer();
    
    // Reset match in app state
    appState.session.matchTime = 0;
    appState.session.currentPeriod = 1;
    appState.session.isPaused = true;
    appState.session.matchRunning = false;
    
    // Reset match time
    _backgroundService.setMatchTime(0);
    
    // Update UI
    setState(() {
      _matchTime = 0;
      widget.matchTimeNotifier.value = 0;
      _isPaused = true;
    });
    
    // Notify parent of timer state change
    widget.onTimerStateChange?.call();
  }

  /// Toggle play/pause with identical behavior to original
  void togglePlayPause() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // CRITICAL FIX: Handle transition from setup mode to match running mode
    if (appState.session.isSetup) {
      // Transition from setup to match running
      appState.session.isSetup = false;
      appState.session.matchRunning = true;
      appState.session.isPaused = false;
      
      // Start the match timer
      startTimer();
      
      // Haptic feedback
      _hapticService.matchStart(context);
      
      setState(() {
        _isPaused = false;
      });
      
      return;
    }

    // Normal play/pause toggle (not in setup mode)
    if (_isPaused) {
      // Resume the timer
      _backgroundService.resumeTimer();
      
      // Notify background service that match has resumed
      _backgroundService.onMatchResume();
      
      startTimer(); // This starts the UI refresh timer
      
      // Haptic feedback
      _hapticService.resumeButton(context);
      
      setState(() {
        _isPaused = false;
      });
      
      // Update app state
      appState.session.matchRunning = true;
      appState.session.isPaused = false;
    } else {
      // Pause the timer
      stopTimer();
      _backgroundService.pauseTimer(); // Make sure background timer is paused
      
      // Haptic feedback
      _hapticService.matchPause(context);
      
      setState(() {
        _isPaused = true;
      });
      
      // Update app state
      appState.session.isPaused = true;
      appState.session.matchRunning = false; // Ensure match running flag is set to false
      
      // Notify background service that match has ended
      _backgroundService.onMatchEnd();
    }
    
    // Notify parent of timer state change
    widget.onTimerStateChange?.call();
  }

  /// Check for period end with identical behavior to original
  void _checkPeriodEnd() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Check if we've reached the end of the current period
    if (appState.session.enableTargetDuration && 
        _matchTime >= appState.session.targetPlayDuration &&
        appState.session.currentPeriod < appState.session.matchSegments) {
      
      print("\n\n🔔🔔🔔 PERIOD END DETECTED IN UI THREAD! 🔔🔔🔔\n\n");
      
      // Stop checking immediately
      _matchTimer?.cancel();
      
      // End the current period through app state
      appState.endPeriod();
      
      // Play whistle sound for period end
      _audioService.playWhistle();
      
      // Provide haptic feedback
      _hapticService.periodEnd(context);
      
      // Show the period end dialog
      _dialogService.showPeriodEndDialog(context, appState.session.currentPeriod);
    }
  }

  /// Check for match end with identical behavior to original
  void _checkMatchEnd() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Check if we've reached the end of all periods
    if (appState.session.enableTargetDuration && 
        appState.session.currentPeriod >= appState.session.matchSegments) {
      
      // Check if we've reached match end time
      if (_matchTime >= appState.session.matchDuration) {
        print("\n\n🏆🏆🏆 MATCH COMPLETION DETECTED IN UI THREAD! 🏆🏆🏆\n\n");
        
        // Stop checking immediately
        _matchTimer?.cancel();
        
        // End the match through app state
        appState.endMatch();
        
        // Play whistle sound for match end
        _audioService.playWhistle();
        
        // Provide haptic feedback
        _hapticService.matchEnd(context);
        
        // Show the match end dialog
        _dialogService.showPeriodEndDialog(
          context,
          0, // period number doesn't matter for match end
          isMatchEnd: true,
        );
      }
    }
  }

  /// Add method to efficiently update match time
  void _updateMatchTime(int newTime, {bool forceUpdate = false}) {
    if (_matchTime != newTime || forceUpdate) {
      _matchTime = newTime;
      widget.matchTimeNotifier.value = newTime;  // Always update the ValueNotifier
      
      // Only trigger full UI update if enough time has passed or force update
      final now = DateTime.now();
      if (forceUpdate || now.difference(_lastUIUpdate) > Duration(milliseconds: 1000)) {
        _lastUIUpdate = now;
        
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  /// Method to restart match time after period transitions
  void restartMatchTimer() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Cancel any existing timer first
    _matchTimer?.cancel();
    
    // Make sure match is properly marked as running if there are active players
    if (appState.session.players.values.any((p) => p.active)) {
      appState.session.matchRunning = true;
      
      // Start the timer again
      startTimer();
    }
  }

  /// Reset all timer state
  void resetAll() async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Provide haptic feedback for reset button press
    await _hapticService.resetButton(context);
    
    // Cancel existing timer
    _matchTimer?.cancel();
    
    // CRITICAL FIX: Stop the background timer to prevent it from continuing after reset
    print("Stopping background timer due to session reset");
    _backgroundService.stopBackgroundTimer();
    
    if (mounted) {
      setState(() {
        // Reset UI state
        _isPaused = false;
        _matchTime = 0;
        widget.matchTimeNotifier.value = 0;
      });
    }
    
    // Reset app state
    appState.resetSession();
    
    // Notify parent of timer state change
    widget.onTimerStateChange?.call();
  }

  /// Getter to check if match is running
  bool get isMatchRunning => _matchTimer != null && !Provider.of<AppState>(context, listen: false).session.isMatchComplete;

  /// Getter for current match time
  int get matchTime => _matchTime;

  /// Getter for paused state
  bool get isPaused => _isPaused;

  @override
  Widget build(BuildContext context) {
    // This widget doesn't render anything itself - it's a controller widget
    // The actual UI rendering is handled by the parent component
    return SizedBox.shrink();
  }
}
