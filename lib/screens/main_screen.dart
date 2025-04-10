import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';
import '../screens/settings_screen.dart';
import '../models/player.dart';
import 'dart:async';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../services/background_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/period_end_dialog.dart';
import '../services/translation_service.dart';
import 'package:flutter/services.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  String _sessionName = "Loading..."; // Default session name
  int _matchTime = 0;
  // Add ValueNotifier for match time
  late final ValueNotifier<int> _matchTimeNotifier;
  bool _isPaused = false;
  Timer? _matchTimer;
  bool _isTableExpanded = true;
  final FocusNode _addPlayerFocusNode = FocusNode();
  bool _isInitialized = false;
  late AudioService _audioService;
  late HapticService _hapticService;
  final BackgroundService _backgroundService = BackgroundService();
  
  // Animation controller for pulsing add button
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Add this variable to store the action timestamp
  int? _actionTimestamp;

  // Add these variables at the class level
  int? _lastUpdateTimestamp;
  bool _isUpdatingTime = false;

  // Add class variables for drift compensation
  int? _initialStartTime;
  int? _lastRealTimeCheck;
  double _accumulatedDrift = 0.0;  // Change to double
  
  // Add this variable to track if UI needs update
  bool _needsUIUpdate = false;
  DateTime _lastUIUpdate = DateTime.now();

  // Track exact timestamps for background transitions
  int? _backgroundEntryTime;
  int? _lastKnownMatchTime;

  // Getter to check if match is running
  bool get _isMatchRunning => _matchTimer != null && !Provider.of<AppState>(context, listen: false).session.isMatchComplete;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _hapticService = HapticService();
    _initializeScreen();
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
        _startMatchTimer();
      }
    }
    
    // Check if we should reset background timers when session is reset
    _checkBackgroundTimersAfterReset(appState);
  }
  
  // CRITICAL FIX: New method to detect session resets and ensure timers are stopped
  void _checkBackgroundTimersAfterReset(AppState appState) {
    // Check for conditions that indicate a session reset
    if (!appState.session.matchRunning && 
        appState.session.matchTime == 0 &&
        appState.session.isSetup) {
      
      // Double-check that background timer is stopped
      if (_backgroundService != null && _backgroundService.isTimerActive()) {
        print("Detected session reset state: stopping background timer");
        _backgroundService.stopBackgroundTimer();
        
        // Cancel UI refresh timer as well
        _matchTimer?.cancel();
        _matchTimer = null;
        
        // Reset UI state
        _safeSetState(() {
          _matchTime = 0;
          _matchTimeNotifier.value = 0;
          _isPaused = false;
        });
      }
    }
  }
  
  void _initializeScreen() {
    // Initialize the ValueNotifier
    _matchTimeNotifier = ValueNotifier<int>(0);
    
    // Register as an observer to handle app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize animation controller for pulsing
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Initialize with defaults first
    _sessionName = "Loading...";
    _isPaused = false;
    _matchTime = 0;
    
    // Initialize the background service
    _backgroundService.initialize().then((_) {
      // Restore the background service if it was previously running
      _backgroundService.restorePreviousState();
      
      // Register for time updates from the background service
      _backgroundService.addTimeUpdateListener(_onTimeUpdate);
      _backgroundService.addPeriodEndListener(_onPeriodEnd);
      _backgroundService.addMatchEndListener(_onMatchEnd);
    });
    
    // Use Future.microtask instead of post-frame callback for safer initialization
    Future.microtask(() {
      if (mounted) {
        _loadInitialState();
        // Mark initialization as complete
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }
  
  // Load initial state from app state
  void _loadInitialState() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Get session name
    setState(() {
      _sessionName = appState.session.sessionName;
            _matchTime = appState.session.matchTime;
            _matchTimeNotifier.value = _matchTime;
            _isPaused = appState.session.isPaused;
          });
          
    print("Initial match time loaded: $_matchTime");
  }
  
  // Handler for time updates from the BackgroundService
  void _onTimeUpdate(int newMatchTime) {
    if (mounted) {
      setState(() {
        _matchTime = newMatchTime;
        _matchTimeNotifier.value = newMatchTime;
      });
    }
  }
  
  // Handler for period end events from BackgroundService
  void _onPeriodEnd() {
    print("\n\n🔔🔔🔔 _onPeriodEnd handler called in MainScreen! 🔔🔔🔔\n\n");
    
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
        // Show period end dialog directly using our dedicated method
        _showPeriodEndDialog(context, appState.session.currentPeriod);
      } else {
        print("CRITICAL ERROR: Widget no longer mounted in post-frame callback!");
      }
    });
  }
  
  // Handler for match end events from BackgroundService
  void _onMatchEnd() {
      if (mounted) {
      // Show match end dialog
      _showMatchEndDialog(context);
    }
  }

  @override
  void dispose() {
    // Cleanup
    _matchTimer?.cancel();
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    
    // Remove listeners from background service
    _backgroundService.removeTimeUpdateListener(_onTimeUpdate);
    _backgroundService.removePeriodEndListener(_onPeriodEnd);
    _backgroundService.removeMatchEndListener(_onMatchEnd);
    
    // Note: We don't stop the background service on dispose
    // as it might still be needed for background operation
    
    super.dispose();
  }

  // Add method to efficiently update match time
  void _updateMatchTime(int newTime, {bool forceUpdate = false}) {
    if (_matchTime != newTime || forceUpdate) {
      _matchTime = newTime;
      _matchTimeNotifier.value = newTime;  // Always update the ValueNotifier
      
      // Only trigger full UI update if enough time has passed or force update
      final now = DateTime.now();
      if (forceUpdate || now.difference(_lastUIUpdate) > Duration(milliseconds: 1000)) {
        _needsUIUpdate = true;
        _lastUIUpdate = now;
        
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _startMatchTimer({int initialDelay = 500}) {
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
        final bgIsActive = _backgroundService.isTimerActive();
        final bgCurrentTime = _backgroundService.getCurrentMatchTime();
        
        // CRITICAL FIX: Check if values differ significantly, which would indicate a sync problem
        if (_matchTime != bgCurrentTime) {
          // Update app state too, to ensure consistency
          appState.session.matchTime = bgCurrentTime;
          
          // Update UI
          setState(() {
            _matchTime = bgCurrentTime;
            _matchTimeNotifier.value = bgCurrentTime;
          });
        }
        
        // CRITICAL ADDITION: Direct period end check in UI thread
        // This ensures we detect period end even if background notification fails
        if (appState.session.enableMatchDuration && 
            appState.session.matchRunning && 
            !appState.session.isPaused && 
            !appState.session.hasWhistlePlayed &&
            appState.session.currentPeriod < appState.session.matchSegments) {
          
          // Calculate period end time
            final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
          final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
          
          // Check if we've reached period end
          if (_matchTime >= currentPeriodEndTime) {
            print("\n\n🚨🚨🚨 PERIOD END DETECTED IN UI THREAD! 🚨🚨🚨\n\n");
            
            // Stop checking immediately
            timer.cancel();
            
            // End the period through app state
            appState.endPeriod();
            
            // Play whistle sound for period end
            _audioService.playWhistle();
            
            // Provide haptic feedback
            _hapticService.periodEnd(context);
            
            // Show the period end dialog
            _showPeriodEndDialog(context, appState.session.currentPeriod);
          }
        }
        
        // CRITICAL ADDITION: Direct match completion check in UI thread
        // This ensures we detect match completion even if background notification fails
        if (appState.session.enableMatchDuration && 
            appState.session.matchRunning && 
            !appState.session.isPaused && 
            !appState.session.isMatchComplete &&
            appState.session.currentPeriod >= appState.session.matchSegments) {
          
          // Check if we've reached match end time
          if (_matchTime >= appState.session.matchDuration) {
            print("\n\n🏆🏆🏆 MATCH COMPLETION DETECTED IN UI THREAD! 🏆🏆🏆\n\n");
            
            // Stop checking immediately
            timer.cancel();
            
            // End the match through app state
            appState.endMatch();
            
            // Play whistle sound for match end
            _audioService.playWhistle();
            
            // Provide haptic feedback
            _hapticService.matchEnd(context);
            
            // Show the match end dialog
            _showMatchEndDialog(context);
          }
        }
      });
      
      print("UI refresh timer started after match start");
    });
  }
  
  void _stopMatchTimer() {
    // Cancel UI refresh timer
            _matchTimer?.cancel();
            _matchTimer = null;

    // Pause the background timer
    _backgroundService.pauseTimer();
    
    // Update UI state
    setState(() {
      _isPaused = true;
    });
    
    // Update app state
                      final appState = Provider.of<AppState>(context, listen: false);
    appState.session.isPaused = true;
  }
  
  void _resetMatch() {
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
      _matchTimeNotifier.value = 0;
      _isPaused = true;
    });
  }
  
  void _togglePlayPause() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // CRITICAL FIX: Handle transition from setup mode to match running mode
    if (appState.session.isSetup) {
      // First check if we have any active players
      if (!_hasActivePlayer()) {
        // Show warning snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded( // Wrap Text with Expanded to prevent overflow
                  child: Text('Select at least one player to start the match'),
                ),
              ],
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return; // Exit early without starting the match
      }
      
      // We're transitioning from setup to match running
      print("Starting match - transitioning from setup mode to match running");
      appState.session.isSetup = false;
      appState.session.matchRunning = true;
      appState.session.isPaused = false;
      
      // Add a match log entry for start
      appState.logMatchEvent("Match Started", entryType: 'period_transition');
      
      // Restart the timer with current state (ensures isSetup=false is seen by timer)
      _backgroundService.stopBackgroundTimer();
      _startMatchTimer();
      
      // Haptic feedback for match start
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
      _startMatchTimer(); // This starts the UI refresh timer
      
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
      _stopMatchTimer();
      _backgroundService.pauseTimer(); // Make sure background timer is paused
      
      // Haptic feedback
      _hapticService.matchPause(context);
      
      setState(() {
        _isPaused = true;
      });
      
      // Update app state
      appState.session.isPaused = true;
      appState.session.matchRunning = false; // Ensure match running flag is set to false
    }
  }

  void _checkPeriodEnd() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    final session = appState.session;
    
    // Detailed debugging information about periods
    final periodDuration = session.matchDuration ~/ session.matchSegments;
    final currentPeriodEndTime = periodDuration * session.currentPeriod;
    final isFinalPeriod = session.currentPeriod >= session.matchSegments;
    
    print("PERIOD UI CHECK: Period=${session.currentPeriod}/${session.matchSegments}, Final=$isFinalPeriod");
    print("PERIOD UI CHECK: Time=${session.matchTime}, PeriodEnd=$currentPeriodEndTime, MatchEnd=${session.matchDuration}");
    print("PERIOD UI CHECK: Running=${session.matchRunning}, Paused=${session.isPaused}");
    print("PERIOD UI CHECK: HasWhistle=${session.hasWhistlePlayed}, Complete=${session.isMatchComplete}");
    print("PERIOD UI CHECK: PeriodsTransitioning=${appState.periodsTransitioning}");
    
    // Check if periodsTransitioning is true - this has highest priority
    // This is the state set by endPeriod when period end is triggered
    if (appState.periodsTransitioning) {
      print("PERIOD UI CHECK: Period transitioning flag detected, showing dialog");
      
      // Immediately clear any existing snackbars to prevent both snackbar and dialog
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Sound and haptic feedback
      _audioService.playWhistle();
      _hapticService.periodEnd(context);
      
      // Make sure the match time is exactly at the period end
      if (session.matchRunning || session.isPaused) {
        final periodDuration = session.matchDuration ~/ session.matchSegments;
        final exactPeriodEndTime = periodDuration * session.currentPeriod;
        
        // Set the UI match time to match exactly the period end time
        _safeSetState(() {
          _matchTime = exactPeriodEndTime;
          _matchTimeNotifier.value = exactPeriodEndTime;
        });
      }
      
      // Show period end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Verify we haven't already shown a dialog for this event
          // Look for existing dialogs to avoid duplicates
          if (ModalRoute.of(context)?.isCurrent ?? true) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => PeriodEndDialog(
                onNextPeriod: () {
                  print("PERIOD UI CHECK: Starting next period via dialog");
                  
                  // Special handling for transition to final period
                  final isTransitioningToFinalPeriod = 
                    appState.session.currentPeriod == appState.session.matchSegments - 1;
                    
                  if (isTransitioningToFinalPeriod) {
                    print("PERIOD UI CHECK: Transition to FINAL period detected!");
                  }
                  
                  // Start the next period
                  appState.startNextPeriod();
                  
                  // Update the background service with the new match time
                  _backgroundService.setMatchTime(appState.session.matchTime);
                  
                  // Resume the background timer
                  _backgroundService.resumeTimer();
                  
                  // Start the UI timer
                        _startMatchTimer();
                  
                  // Update UI state
                  _safeSetState(() {
                    _isPaused = false;
                  });
                  
                  // Close the dialog
                  Navigator.of(context).pop();
                },
              ),
            );
          }
        }
      });
      
      return; // Exit early after handling period end
    }
    
    // Case 1: Check if current period should end now
    if (!appState.periodsTransitioning && 
        session.enableMatchDuration && 
        session.matchRunning && 
        session.matchTime >= currentPeriodEndTime && 
        !session.hasWhistlePlayed) {
      
      print("PERIOD UI CHECK: Period ${session.currentPeriod} end condition met, ending period");
      
      // End the period
      appState.endPeriod();
      
      // Sound and haptic feedback
      _audioService.playWhistle();
      _hapticService.periodEnd(context);
      
      // Immediately update UI match time to exact period end time
      _safeSetState(() {
        _matchTime = currentPeriodEndTime;
        _matchTimeNotifier.value = currentPeriodEndTime;
      });
      
      // Show period end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PeriodEndDialog(
              onNextPeriod: () {
                print("PERIOD UI CHECK: Starting next period via dialog");
                
                // Special handling for transition to final period
                final isTransitioningToFinalPeriod = 
                  appState.session.currentPeriod == appState.session.matchSegments - 1;
                
                if (isTransitioningToFinalPeriod) {
                  print("PERIOD UI CHECK: Transition to FINAL period detected!");
                }
                
                appState.startNextPeriod();
                
                // IMPORTANT: Use a small delay to ensure state is fully updated
                Future.delayed(Duration(milliseconds: 50), () {
                  _safeSetState(() {
                    _isPaused = false;
                    // Use the latest value from app state to ensure correct time
                    _matchTime = appState.session.matchTime;
                    _matchTimeNotifier.value = _matchTime;
                    
                    // Force extra state sync for final period transition
                    if (isTransitioningToFinalPeriod) {
                      // Cancel any existing timer first to ensure clean start
                      _matchTimer?.cancel();
                      _matchTimer = null;
                      print("PERIOD UI CHECK: Special handling for final period, forcing fresh timer start");
                    }
                    
                    print("PERIOD UI CHECK: Updated UI match time to ${_matchTime}");
                  });
                  
                  // For final period, add a small extra delay to ensure fresh timer start
                  if (isTransitioningToFinalPeriod) {
                    Future.delayed(Duration(milliseconds: 50), () {
                      _startMatchTimer();
                    });
                  } else {
                    _startMatchTimer();
                  }
                });
                
                Navigator.of(context).pop();
              },
            ),
          );
        }
      });
      
      return; // Exit early after handling period end
    }
    
    // Case 2: Check for match end (only in final period)
    if (isFinalPeriod && 
        session.enableMatchDuration && 
        session.matchTime >= session.matchDuration && 
        !session.isMatchComplete &&
        session.matchRunning) {
      
      // Set match time to exactly the match duration for consistency
      _safeSetState(() {
        _matchTime = session.matchDuration;
        _matchTimeNotifier.value = session.matchDuration;
      });
      
      // End the match
      appState.endMatch();
      
      // Sound and haptic feedback
      _audioService.playWhistle();
      _hapticService.matchEnd(context);
      
      // Show match end notification
      _showMatchEndNotification();
      
      // Show match end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PeriodEndDialog(
              // Add isMatchEnd parameter to indicate match completion
              isMatchEnd: true,
              onOk: () {
                final appState = Provider.of<AppState>(context, listen: false);
                
                // Use the dedicated method to ensure match end is logged
                appState.ensureMatchEndLogged();
                
                // Close the dialog
                Navigator.of(context).pop();
              },
            ),
          );
        }
      });
      
      return; // Add early return to prevent further checks
    }
    
    // Check for resumed state after period end in background
    if (session.isPaused && 
        session.hasWhistlePlayed && 
        !session.isMatchComplete && 
        !appState.periodsTransitioning &&
        session.currentPeriod < session.matchSegments) {
      
      print("PERIOD DEBUG: Period transition detected during background resume");
      
      // Show period end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PeriodEndDialog(
              onNextPeriod: () {
                print("PERIOD DEBUG: Starting next period via dialog after background");
                appState.startNextPeriod();
                _safeSetState(() {
                  _isPaused = false;
                });
                _startMatchTimer();
                Navigator.of(context).pop();
              },
            ),
          );
        }
      });
    }
    
    // Check for match end in background
    if (session.isMatchComplete) {
      print("PERIOD DEBUG: Match completion detected during background resume");
      
      // Show match end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PeriodEndDialog(
              // Add isMatchEnd parameter to indicate match completion
              isMatchEnd: true,
              onOk: () {
                print("MATCH END DIALOG: Processing OK button click for match end");
                final appState = Provider.of<AppState>(context, listen: false);
                
                // Use the dedicated method to ensure match end is logged
                appState.ensureMatchEndLogged();
                
                // Close the dialog
                Navigator.of(context).pop();
              },
            ),
          );
        }
      });
    }
    
    // Special case: Check if we are at the final period and reached match end time but not yet marked complete
    // This handles the edge case where final period ended but match wasn't marked complete
    if (isFinalPeriod && 
        session.enableMatchDuration && 
        session.matchTime >= session.matchDuration && 
        !session.isMatchComplete) {
      
      print("PERIOD UI CHECK: Match end condition detected during UI check");
      
      // Set match time to exactly the match duration for consistency
      _safeSetState(() {
        _matchTime = session.matchDuration;
        _matchTimeNotifier.value = session.matchDuration;
      });
      
      // Debug the state before ending the match
      print("MATCH END DEBUG: Before endMatch (from check) - Time=${session.matchTime}, Duration=${session.matchDuration}, Period=${session.currentPeriod}/${session.matchSegments}, Complete=${session.isMatchComplete}");
      
      // End the match
      appState.endMatch();
      
      // Debug to verify the match end was processed
      print("MATCH END DEBUG: Match end processed. isMatchComplete=${session.isMatchComplete}");
      
      // Debug the match log entries
      print("MATCH LOG DEBUG: Current log entries: ${session.matchLog.length}");
      for (int i = 0; i < session.matchLog.length; i++) {
        final entry = session.matchLog[i];
        print("MATCH LOG ENTRY $i: Time=${entry.matchTime}, Details=${entry.details}, Type=${entry.entryType}");
      }
      
      // Sound and haptic feedback
      _audioService.playWhistle();
      _hapticService.matchEnd(context);
      
      // Show match end notification
      _showMatchEndNotification();
      
      // Show match end dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PeriodEndDialog(
              // Add isMatchEnd parameter to indicate match completion
              isMatchEnd: true,
              onOk: () {
                print("MATCH END DIALOG: Processing OK button click for match end");
                final appState = Provider.of<AppState>(context, listen: false);
                
                // Use the dedicated method to ensure match end is logged
                appState.ensureMatchEndLogged();
                
                // Close the dialog
                Navigator.of(context).pop();
              },
            ),
          );
        }
      });
    }
  }
  
  // New method to show period end notification
  void _showPeriodEndNotification(int periodNumber) {
    final isQuarters = Provider.of<AppState>(context, listen: false).session.matchSegments == 4;
    final periodText = isQuarters ? 'Quarter' : 'Half';
    final ordinalPeriod = _getOrdinalNumber(periodNumber);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.sports_soccer, color: Colors.white),
              SizedBox(width: 8),
              Text('End of $ordinalPeriod $periodText!'),
            ],
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.amber.shade700,
          action: SnackBarAction(
            label: 'Next',
            textColor: Colors.white,
            onPressed: () {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.startNextPeriod();
              _safeSetState(() {
                _isPaused = false;
              });
              _startMatchTimer();
            },
          ),
        ),
      );
    }
  }
  
  // New method to show match end notification
  void _showMatchEndNotification() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.sports_score, color: Colors.white),
              SizedBox(width: 8),
              Text('Match Complete!'),
            ],
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }
  }
  
  // Helper method for ordinal numbers (1st, 2nd, 3rd, etc.)
  String _getOrdinalNumber(int number) {
    if (number == 1) return '1st';
    if (number == 2) return '2nd';
    if (number == 3) return '3rd';
    return '${number}th';
  }

  void _showStartNextPeriodDialog() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Play period end haptic feedback
    _hapticService.periodEnd(context);
    
    // This was a duplicate period end dialog implementation
    // We should use the PeriodEndDialog widget instead
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PeriodEndDialog(
        onNextPeriod: () {
          // Start the next period
          appState.startNextPeriod();
          
          // Update background service with new match time
          _backgroundService.setMatchTime(appState.session.matchTime);
          
          // Resume the background timer
          _backgroundService.resumeTimer();
          
          // Start the UI timer
          _startMatchTimer();
          
          // Update UI state
          setState(() {
            _isPaused = false;
            appState.session.isPaused = false;
          });
          
          // Close the dialog
              Navigator.of(context).pop();
        },
      ),
    );
  }

  // Add this method to handle period transitions
  void _handlePeriodTransition() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Cancel any existing timer
    _matchTimer?.cancel();
    _matchTimer = null;
    
    // Start a new timer
    _startMatchTimer();
  }

  bool _hasActivePlayer() {
    final appState = Provider.of<AppState>(context, listen: false);
    for (var playerName in appState.session.players.keys) {
      if (appState.session.players[playerName]!.active) {
        return true;
      }
    }
    return false;
  }

  void _toggleTimer(int index) async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.currentSessionId == null) return;

    // Get the player name from the index, using a safety check
    if (index < 0 || index >= appState.players.length) return;
    final playerName = appState.players[index]['name'];
    
    // Toggle this specific player
    await appState.togglePlayer(playerName);
  }

  // Modify _togglePlayerByName to handle player toggling during pause
  void _togglePlayerByName(String playerName) async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.currentSessionId == null) return;

    // Provide haptic feedback without awaiting
    _hapticService.playerToggle(context);

    // CRITICAL FIX: Check if match is already running but not in setup mode
    final isMatchRunning = appState.session.matchRunning && !appState.session.isPaused && !appState.session.isSetup;
    final wasPlayerActive = appState.session.players[playerName]?.active ?? false;
    
    // Toggle player state
    appState.togglePlayer(playerName);

    // If we activated a player during a running match, make sure the UI knows the match is running
    if (isMatchRunning && !wasPlayerActive) {
      // Force UI refresh to show active time immediately
      setState(() {});
      
      // Ensure background service is aware of player change
      if (_backgroundService.isRunning) {
        _backgroundService.syncAppState(appState);
      }
    }

    // Only start the match timer if we're not paused and not in setup mode
    if (!_isPaused && !appState.session.isPaused && !appState.session.isSetup) {
      if (appState.session.players[playerName]?.active ?? false) {
        // Start match timer if it's not already running
        if (!appState.session.matchRunning) {
        _safeSetState(() {
          appState.session.matchRunning = true;
        });
          
          // If match timer isn't running, start it
          if (_matchTimer == null) {
            _startMatchTimer();
          }
        }
      }
    }
  }

  // Modify _pauseAll to handle timestamps
  void _pauseAll() async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // If match is complete, prevent any actions
    if (appState.session.isMatchComplete) {
      print("Match is complete, ignoring pause/resume actions");
      return;
    }
    
    // If in setup mode and there are active players, start the match
    if (appState.session.isSetup) {
      // Check if there are any active players
      if (!_hasActivePlayer()) {
        // Show warning snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded( // Wrap Text with Expanded to prevent overflow
                  child: Text('Select at least one player to start the match'),
                ),
              ],
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return; // Exit early without starting the match
      }

      await _hapticService.matchStart(context);
      
      // First, start the match (this will set isSetup to false)
      await appState.startMatch();
      
      // Initialize match state
      _safeSetState(() {
        _isPaused = false;
        _matchTime = 0;
        _matchTimeNotifier.value = 0;
        appState.session.isPaused = false;
        appState.session.matchRunning = true;
        
        // Reset all timestamps to ensure a fresh start
        _lastUpdateTimestamp = null;
        _lastRealTimeCheck = null;
        _initialStartTime = null;
        _accumulatedDrift = 0;
        
        // Initialize all active players with zero time
        for (var playerName in appState.session.players.keys) {
          final player = appState.session.players[playerName]!;
          if (player.active) {
            player.totalTime = 0;
            player.lastActiveMatchTime = 0;
          }
        }
      });
      
      // Save the initial state
      await appState.saveSession();
      
      // Get the exact start time
      final startTime = DateTime.now().millisecondsSinceEpoch;
      
      // Start the match timer after a short delay to ensure state is properly initialized
      Future.delayed(Duration(milliseconds: 50), () {
        if (mounted) {
          _safeSetState(() {
            // Reset the match time and timestamps again just before starting
            _matchTime = 0;
            _matchTimeNotifier.value = 0;
            _lastUpdateTimestamp = startTime;
            _initialStartTime = startTime;
          });
          _startMatchTimer();
        }
      });
      
      // Show a snackbar indicating match start
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.sports_soccer, color: Colors.white),
                SizedBox(width: 8),
                Text('Match Started!'),
              ],
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
      return;  // Exit early since we've handled the setup mode case
    }
    
    // Handle normal pause/resume logic
    if (!_isPaused) {
      // Pausing the match
      _safeSetState(() {
        _isPaused = true;
        appState.session.isPaused = true;
        
        // Store active players and update their times
        appState.session.activeBeforePause.clear();
        for (var playerName in appState.session.players.keys) {
          final player = appState.session.players[playerName]!;
          if (player.active) {
            appState.session.activeBeforePause.add(playerName);
            if (player.lastActiveMatchTime != null) {
              player.totalTime += _matchTime - player.lastActiveMatchTime!;
            }
            player.lastActiveMatchTime = null;
            player.active = false;
          }
        }
      });
      
      // Reset all timestamps when pausing
      _lastUpdateTimestamp = null;
      _lastRealTimeCheck = null;
      _initialStartTime = null;
      _accumulatedDrift = 0;
      
      // Pause the background timer service (don't stop it completely)
      if (_backgroundService.isRunning) {
        // Don't call stopBackgroundTimer or stopBackgroundService - these stop too much
        // Instead, just pause the timer which keeps the service running
        _backgroundService.pauseTimer();
      }
      
      await _hapticService.matchPause(context);
      
      // Show pause notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.pause_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Match Paused - Timers Stopped'),
              ],
            ),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.deepOrangeAccent,
          ),
        );
      }
    } else {
      // Resuming the match
      // Provide haptic feedback for resume button press
      await _hapticService.resumeButton(context);
      
      _safeSetState(() {
        _isPaused = false;
        appState.session.isPaused = false;
        appState.session.matchRunning = true;
        
        // Reactivate players that were active before pause
        for (var playerName in appState.session.activeBeforePause) {
          if (appState.session.players.containsKey(playerName)) {
            final player = appState.session.players[playerName]!;
            player.active = true;
            player.lastActiveMatchTime = _matchTime;
          }
        }
        appState.session.activeBeforePause.clear();
      });
      
      // Start the timer with fresh timestamps
      _startMatchTimer();
      
      // Show resume notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.play_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Match Resumed - Timers Running'),
              ],
            ),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
    
    // Save the session state
    await appState.saveSession();
  }

  void _resetAll() async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Provide haptic feedback for reset button press
    await _hapticService.resetButton(context);
    
    // Cancel existing timer
    _matchTimer?.cancel();
    
    // CRITICAL FIX: Stop the background timer to prevent it from continuing after reset
    if (_backgroundService != null) {
      print("Stopping background timer due to session reset");
      _backgroundService.stopBackgroundTimer();
    }
    
    _safeSetState(() {
      // Reset UI state
      _isPaused = false;
      _matchTime = 0;
      _matchTimeNotifier.value = 0;
      
      // Reset all timer-related variables
      _lastUpdateTimestamp = null;
      _lastRealTimeCheck = null;
      _initialStartTime = null;
      _accumulatedDrift = 0;
      _isUpdatingTime = false;
    });
    
    // Reset app state
    appState.resetSession();
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _showAddPlayerDialog(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if match is running and not paused
    if (appState.session.matchRunning && !appState.session.isPaused) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Warning',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppThemes.darkText : AppThemes.lightText,
            ),
          ),
          content: Text('Adding a player to a running match will pause the match.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showActualAddPlayerDialog(context);
              },
              child: Text('Continue'),
            ),
          ],
          actionsAlignment: MainAxisAlignment.spaceBetween,
        ),
      );
      return;
    }

    // If match is not running or already paused, show add player dialog directly
    _showActualAddPlayerDialog(context);
  }

  void _showActualAddPlayerDialog(BuildContext context) {
    final textController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final focusNode = FocusNode();  // Create a local focus node

    // Pause the timer while dialog is open to prevent state updates
    final wasRunning = !_isPaused;
    if (wasRunning) {
      _pauseAll();
    }

    showDialog(
      context: context,
      barrierDismissible: true,  // Allow dismissing by tapping outside
      builder: (dialogContext) => StatefulBuilder(  // Use StatefulBuilder to manage dialog state
        builder: (context, setState) {
          // Request focus when dialog is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusNode.canRequestFocus) {
              focusNode.requestFocus();
            }
          });

          return AlertDialog(
            key: UniqueKey(),
            title: Text(
              'Add Player',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                letterSpacing: 1.0,
              ),
            ),
            content: TextField(
              controller: textController,
              focusNode: focusNode,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: 'Player Name'),
              onSubmitted: (value) async {
                if (value.trim().isNotEmpty) {
                  try {
                    final appState = Provider.of<AppState>(context, listen: false);
                    await appState.addPlayer(value.trim());
                    
                    if (context.mounted) {
                      Navigator.pop(context, true); // Close current dialog
                      // Reopen the dialog immediately for next player
                      _showActualAddPlayerDialog(context);
                    }
                  } catch (e) {
                    print('Error adding player: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not add player: $e'))
                      );
                    }
                  }
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false); // Return false on cancel
                },
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (textController.text.trim().isNotEmpty) {
                    try {
                      final appState = Provider.of<AppState>(context, listen: false);
                      await appState.addPlayer(textController.text.trim());
                      
                      if (context.mounted) {
                        Navigator.pop(context, true); // Close dialog, don't reopen
                      }
                    } catch (e) {
                      print('Error adding player: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not add player: $e'))
                        );
                      }
                    }
                  }
                },
                child: Text('Add'),
              ),
            ],
          );
        },
      ),
    ).then((result) { // Dialog returns true (added) or false (cancelled)
      // Clean up the controller AFTER the dialog is closed, with a slight delay
      Future.delayed(Duration(milliseconds: 50), () {
        textController.dispose();
      });
      
      // Resume the timer ONLY if the dialog was cancelled (user explicitly stopped adding)
      // and the timer was running initially.
      if (result == false && wasRunning) {
        _pauseAll(); // This toggles the pause state back
      }
    });
  }

  // Toggle expansion state of the player table
  void _toggleTableExpansion() {
    setState(() {
      _isTableExpanded = !_isTableExpanded;
    });
  }

  // Add this helper method to calculate player time
  int _calculatePlayerTime(Player? player) {
    if (player == null) return 0;
    final appState = Provider.of<AppState>(context, listen: false);
    return appState.calculatePlayerTime(player);
  }

  // Method to restart match time after period transitions
  void _restartMatchTimer() {
    if (!mounted) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Cancel any existing timer first
    _matchTimer?.cancel();
    
    // Make sure match is properly marked as running if there are active players
    if (appState.session.players.values.any((p) => p.active)) {
      appState.session.matchRunning = true;
      
      // Start the timer again
      _startMatchTimer();
    }
  }

  // Add this method to safely update state
  void _safeSetState(Function updateState) {
    if (mounted) {
      setState(() {
        updateState();
      });
    }
  }

  // Add helper method for player button colors
  List<Color> _getPlayerButtonColors({
    required bool isActive,
    required bool isPaused,
    required bool wasActiveDuringPause,
    required bool isDark,
  }) {
    if (isPaused) {
      if (isActive) {
        // Active during pause - Muted green with blue tint
        return [
          Color.fromARGB(255, 94, 141, 117), // Muted green
          Color(0xFF2E7D5F), // Darker muted green
        ];
      } else if (wasActiveDuringPause) {
        // Was active before pause - Muted orange
        return [
          Color.fromARGB(255, 94, 141, 117), // Muted orange
          Color.fromARGB(255, 94, 141, 117), // Darker muted orange
        ];
      } else {
        // Inactive during pause - Muted red
        return [
          isDark ? Color(0xFF8B4343) : Color(0xFFB45757), // Muted red
          isDark ? Color(0xFF6B3232) : Color(0xFF8B4343), // Darker muted red
        ];
      }
    } else {
      if (isActive) {
        // Active - Vibrant green
        return [
          Colors.green,
          Colors.green.shade800,
        ];
      } else {
        // Inactive - Vibrant red
        return [
          isDark ? Colors.red.shade700 : Colors.red.shade600,
          isDark ? Colors.red.shade900 : Colors.red.shade800,
        ];
      }
    }
  }

  // Modify the action selection dialog to use the stored timestamp
  void _showActionSelectionDialog(BuildContext context) async {
    // Store the current match time when the soccer ball is first clicked
    _actionTimestamp = _matchTime;
    
    // Provide subtle haptic feedback for soccer ball button press
    await _hapticService.soccerBallButton(context);
    
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    final matchDurationDisabled = !appState.session.enableMatchDuration;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Row(
          children: [
            Text(
              'Match Action',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/soccerball.svg',
                height: 24,
                width: 24,
              ),
              title: Text(
                'Goal',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context); // Close action selection dialog
                _showGoalActionDialog(context, _actionTimestamp!); // Pass the stored timestamp
              },
            ),
            // Add End Match option when match duration is disabled
            if (matchDurationDisabled && !appState.session.isMatchComplete && !appState.session.isSetup)
              ListTile(
                leading: SvgPicture.asset(
                  'assets/images/white_whistle.svg',
                  height: 24,
                  width: 24,
                  colorFilter: ColorFilter.mode(
                    Colors.red,
                    BlendMode.srcIn
                  ),
                ),
                title: Text(
                  'End the Match',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context); // Close action selection dialog
                  _showEndMatchConfirmationDialog(context); // Show confirmation dialog
              },
            ),
            // Add more actions here in the future
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  // Add a new method for the end match confirmation dialog
  Future<bool?> _showEndMatchConfirmationDialog(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    final score = "${appState.session.teamGoals}-${appState.session.opponentGoals}";
    
    // Create a ValueNotifier for live updates of time
    final ValueNotifier<int> dialogMatchTime = ValueNotifier<int>(_matchTime);
    
    // Create a timer to update the dialog's time display
    Timer? dialogTimer;
    if (appState.session.matchRunning && !appState.session.isPaused) {
      dialogTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
        // Update the ValueNotifier with the latest time from background service
        dialogMatchTime.value = _backgroundService.getCurrentMatchTime();
      });
    }
    
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Row(
          children: [
            Icon(
              Icons.sports_soccer,
              color: Colors.red,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'End Match?',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to end the match?',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Current Score: $score',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            // Use ValueListenableBuilder to show live updating match time
            ValueListenableBuilder<int>(
              valueListenable: dialogMatchTime,
              builder: (context, time, child) {
                return Text(
                  'Match Time: ${_formatTime(time)}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 16,
                  ),
                );
              },
            ),
            SizedBox(height: 12),
            Text(
              'This will save the match to session history.',
              style: TextStyle(
                color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          // Cancel button
          TextButton(
            onPressed: () {
              // Cancel the timer when dialog is dismissed
              dialogTimer?.cancel();
              Navigator.pop(context, false);
            },
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : Colors.black54,
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
          ),
          // End Match button
          ElevatedButton(
            onPressed: () {
              // Cancel the timer when dialog is dismissed
              dialogTimer?.cancel();
              // End the match
              _endMatchManually(context);
              // Return true to allow exit
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              'End Match',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).then((value) {
      // Ensure the timer is cleaned up if the dialog is dismissed unexpectedly
      dialogTimer?.cancel();
      return value;
    });
  }
  
  // Add a method to handle manual match ending
  void _endMatchManually(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Debug logging
    print("MANUAL MATCH END: Ending match at time=${_matchTime}");
    
    // Ensure all player times are updated
    for (var playerName in appState.session.players.keys) {
      final player = appState.session.players[playerName]!;
      if (player.active && player.lastActiveMatchTime != null) {
        // Update total time for active players
        player.totalTime += (_matchTime - player.lastActiveMatchTime!);
        player.lastActiveMatchTime = null;
        player.active = false;
      }
    }
    
    // Stop and cancel the timer
    _matchTimer?.cancel();
    _matchTimer = null;
    
    // End the match through app state
    appState.endMatch();
    
    // Make sure all background timers and vibrations are stopped
    _backgroundService.stopReminderVibrations();
    
    // Sound and haptic feedback
    _audioService.playWhistle();
    _hapticService.matchEnd(context);
    
    // Show match end dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PeriodEndDialog(
            isMatchEnd: true,
            onOk: () {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.ensureMatchEndLogged();
              Navigator.of(context).pop();
            },
          ),
        );
      }
    });
    
    // Update UI state
    _safeSetState(() {
      _isPaused = true;
      _matchTimeNotifier.value = _matchTime;
    });
  }

  // Modify the goal action dialog to accept the timestamp
  void _showGoalActionDialog(BuildContext context, int timestamp) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/images/soccerball.svg',
              height: 24,
              width: 24,
            ),
            SizedBox(width: 8),
            Text(
              'Goal!',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Who scored the goal?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 18,
          ),
        ),
        actions: [
          // Team button
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close first dialog
              _showTeamScorerDialog(context, timestamp);
            },
            child: Text(
              appState.session.sessionName,
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Opponent button
          TextButton(
            onPressed: () {
              appState.addOpponentGoal(timestamp: timestamp);
              Navigator.pop(context);
            },
            child: Text(
              'Opponent',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Modify the team scorer dialog to accept and use the timestamp
  void _showTeamScorerDialog(BuildContext context, int timestamp) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    // Sort players alphabetically
    final players = appState.session.players.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Who Scored?',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players[index];
              return ListTile(
                title: Text(
                  player.key,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  appState.addPlayerGoal(player.key, timestamp: timestamp);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _reconcileMatchAndPlayerTimes() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Only proceed if the session is initialized and not paused
    if (!_isInitialized || _isPaused) return;
    
    // Get the sum of all player times
    int totalPlayerSeconds = 0;
    int maxPlayerSeconds = 0;
    int activePlayerCount = 0;
    
    for (var playerName in appState.session.players.keys) {
      final player = appState.session.players[playerName];
      if (player != null) {
        final playerTime = _calculatePlayerTime(player);
        totalPlayerSeconds += playerTime;
        
        // Track the maximum player time as a reference
        if (playerTime > maxPlayerSeconds) {
          maxPlayerSeconds = playerTime;
        }
        
        // Count active players
        if (player.active) {
          activePlayerCount++;
        }
      }
    }
    
    // Calculate average player time
    final avgPlayerSeconds = appState.session.players.isNotEmpty 
        ? totalPlayerSeconds / appState.session.players.length
        : 0;
    
    // Get current match time in seconds
    final currentMatchSeconds = _matchTime;
    
    // If there's a significant discrepancy between match time and max player time
    // and we have at least one player, adjust the match time
    if (appState.session.players.isNotEmpty && 
        (maxPlayerSeconds > currentMatchSeconds + 60 || maxPlayerSeconds < currentMatchSeconds - 60)) {
      
      // Adjust match time to be at least as high as the maximum player time
      _safeSetState(() {
        _matchTime = maxPlayerSeconds;
        appState.session.matchTime = maxPlayerSeconds;
      });
      
      // Save the session with the updated time
      appState.saveSession();
    }
  }

  void _showPlayerActionsDialog(String playerName) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Player Actions: $playerName',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: Colors.blue),
              title: Text(
                'Edit Player',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context); // Close dialog
                _showEditPlayerDialog(context, '', playerName);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text(
                'Remove Player',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context); // Close dialog
                _showRemovePlayerConfirmation(playerName);
              },
            ),
            ListTile(
              leading: Icon(Icons.timer_off, color: Colors.orange),
              title: Text(
                'Reset Time',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context); // Close dialog
                _resetPlayerTime(playerName);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showEditPlayerDialog(BuildContext context, String playerId, String playerName) {
    final textController = TextEditingController(text: playerName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Edit Player',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            letterSpacing: 1.0,
          ),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Player Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = textController.text.trim();
              if (newName.isNotEmpty && newName != playerName) {
                final appState = Provider.of<AppState>(context, listen: false);
                appState.renamePlayer(playerName, newName);
                Navigator.pop(context);
              } else if (newName.isEmpty) {
                // Show error for empty name
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Player name cannot be empty'))
                  );
                }
              } else if (newName == playerName) {
                // No change, just close the dialog
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRemovePlayerConfirmation(String playerName) {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove Player',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            letterSpacing: 0.5,
          ),
        ),
        content: Text('Are you sure you want to remove $playerName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.removePlayer(playerName);
              Navigator.pop(context);
            },
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _resetPlayerTime(String playerName) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Deactivate player if active
    if (appState.session.players[playerName]?.active ?? false) {
      appState.togglePlayer(playerName);
    }
    
    // Reset player time
    appState.resetPlayerTime(playerName);
    
    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset time for $playerName')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkTheme;
    
    return PopScope(
      canPop: !_isMatchRunning,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        if (_isMatchRunning) {
          final shouldPop = await _showExitConfirmationDialog(context);
          if (shouldPop == true) {
            // Use our method to show session dialog
            _exitToSessionDialog();
          }
        } else {
          // Use our method to show session dialog
          _exitToSessionDialog();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Add a semi-transparent overlay when paused
            if (_isPaused && !appState.session.isMatchComplete)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.15), // Subtle dim effect
                  ),
                ),
              ),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
                child: Column(
                  children: [
                    // Status bar with player counts and match settings
                    StatusBar(
                      isDark: isDark,
                      activePlayerCount: appState.session.players.values.where((p) => p.active).length,
                      inactivePlayerCount: appState.session.players.values.where((p) => !p.active).length,
                      teamGoals: appState.session.teamGoals,
                      opponentGoals: appState.session.opponentGoals,
                      isPaused: _isPaused,
                      isMatchComplete: appState.session.isMatchComplete,
                      isSetup: appState.session.isSetup,  // Add isSetup parameter
                      enableTargetDuration: appState.session.enableTargetDuration,
                      enableMatchDuration: appState.session.enableMatchDuration,
                      targetPlayDuration: appState.session.targetPlayDuration,
                      matchDuration: appState.session.matchDuration,
                    ),
                    
                    // Match Time container with pause indicator
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                          // Dark theme colors (keep existing logic)
                          ? (appState.session.isSetup
                              ? Colors.blueGrey.shade900.withOpacity(0.5)
                              : (appState.session.isMatchComplete
                                  ? Colors.red.shade900.withOpacity(0.5)
                                  : (_isPaused
                                      ? Colors.orange.shade900.withOpacity(0.5)
                                      : Colors.black38)))
                          // Light theme: Use eggshell color
                          : const Color(0xFFFAF0E6), // Eggshell color for light theme
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                            // Dark theme border colors (keep existing logic)
                            ? (appState.session.isSetup
                                ? Colors.blueGrey.shade600
                                : (appState.session.isMatchComplete
                                    ? Colors.red.shade600
                                    : (_isPaused
                                        ? Colors.orange.shade600
                                        : Colors.grey.shade700)))
                            // Light theme border colors (keep existing logic)
                            : (appState.session.isSetup
                                ? Colors.blueGrey.shade300
                                : (appState.session.isMatchComplete
                                    ? Colors.red.shade300
                                    : (_isPaused
                                        ? Colors.orange.shade300
                                        : Colors.grey.shade400))),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Session Name display
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              _sessionName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.lightBlue,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          if (appState.isReadOnlyMode)
                            Padding(
                              padding: const EdgeInsets.only(left: 3.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 9,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 1),
                                  Text(
                                    'Read-Only',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          // Stack to separate timer centering and period positioning
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Center the match timer independently
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 0, bottom: 0),
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: _matchTimeNotifier,
                                    builder: (context, time, child) {
                                      return Text(
                                        _formatTime(time),
                                        style: TextStyle(
                                          fontSize: 46,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'RobotoMono',
                                          color: appState.session.isSetup
                                            ? Colors.blue  // Blue in setup mode
                                            : (_isPaused 
                                                ? Colors.orange.shade600  // Orange when paused
                                                : (_hasActivePlayer() 
                                                    ? Colors.green  // Green when running
                                                    : Colors.red)),  // Red when stopped
                                            letterSpacing: 2.0,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              // Position the period indicator to the right of the timer
                              Positioned(
                                left: MediaQuery.of(context).size.width / 2 + 64,
                                top: 4,
                                child: appState.session.enableMatchDuration ? Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.lightBlue,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      appState.session.matchSegments == 2 
                                        ? 'H${appState.session.currentPeriod}' 
                                        : 'Q${appState.session.currentPeriod}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ) : SizedBox.shrink(),
                              ),
                            ],
                          ),
                          // Match duration progress bar
                          if (appState.session.enableMatchDuration)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Container(
                                height: 6,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: isDark ? Colors.black38 : Colors.grey.shade300,
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: ((_matchTime) / appState.session.matchDuration).clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      gradient: LinearGradient(
                                        colors: [Colors.lightBlueAccent, Colors.blueAccent],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Container for both player buttons and table
                    Expanded(
                      child: Column(
                        children: [
                          // Player buttons pane
                          Expanded(
                            flex: 2,
                            child: Container(
                              margin: EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isDark 
                                  ? Colors.black.withOpacity(0.3) 
                                  : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                  width: 1,
                                ),
                              ),
                              child: appState.players.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.people_outline,
                                          size: 48,
                                          color: Colors.white54,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No Players Added',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white54,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Tap the + button to add players',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    itemCount: appState.players.length,
                                    addAutomaticKeepAlives: false,
                                    addRepaintBoundaries: true,
                                    cacheExtent: 500,
                                    itemBuilder: (context, index) {
                                      final player = appState.players[index];
                                      final playerName = player['name'] as String;
                                      final playerId = player['id'].toString();
                                      final playerObj = appState.session.players[playerName];
                                      final isActive = playerObj?.active ?? false;
                                      final playerTime = _calculatePlayerTime(playerObj);
                                      
                                      return PlayerListItem(
                                        playerName: playerName,
                                        playerId: playerId,
                                        isActive: isActive,
                                        playerTime: playerTime,
                                        isPaused: _isPaused,
                                        isSetup: appState.session.isSetup,
                                        wasActiveDuringPause: appState.session.activeBeforePause.contains(playerName),
                                        isDark: isDark,
                                        targetPlayDuration: appState.session.enableTargetDuration ? appState.session.targetPlayDuration : 0,
                                        goals: playerObj?.goals,
                                        isReadOnlyMode: appState.isReadOnlyMode,
                                        onToggle: _togglePlayerByName,
                                        onLongPress: _showPlayerActionsDialog,
                                      );
                                    },
                                  ),
                            ),
                          ),
                          
                          // Table header with toggle button
                          GestureDetector(
                            onTap: _toggleTableExpansion,
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.black, // Match the dark header from the image
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                  bottomLeft: _isTableExpanded ? Radius.zero : Radius.circular(8),
                                  bottomRight: _isTableExpanded ? Radius.zero : Radius.circular(8),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Player header - left aligned
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Player',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                        fontSize: 12,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                  // Time header - right aligned
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Time',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey,
                                            fontSize: 12,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        // Chevron icon
                                        Icon(
                                          _isTableExpanded 
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_up,
                                          color: Colors.white,
                                          size: 13,
                                          weight: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // Player table pane (collapsible)
                          AnimatedContainer(
                            duration: Duration(milliseconds: 300),
                            height: _isTableExpanded ? 150 : 0,
                            margin: EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: _isTableExpanded 
                              ? SingleChildScrollView(
                                  child: Builder(
                                    builder: (context) {
                                      // Get all players with their times
                                      List<Map<String, dynamic>> sortedPlayers = [];
                                      
                                      // Handle empty player list case
                                      if (appState.players.isEmpty) {
                                        return Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'No players yet',
                                              style: TextStyle(
                                                color: isDark ? Colors.white70 : Colors.black54,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      
                                      // Create the sorted players list
                                      sortedPlayers = appState.players.map((player) {
                                        final playerName = player['name'];
                                        final playerObj = appState.session.players[playerName];
                                        final isActive = playerObj?.active ?? false;
                                        final playerTime = _calculatePlayerTime(playerObj);
                                        final index = appState.players.indexOf(player);
                                        
                                        return {
                                          'player': player,
                                          'name': playerName as String,
                                          'time': playerTime,
                                          'active': isActive,
                                          'index': index,
                                        };
                                      }).toList();
                                      
                                      // Sort by time descending
                                      sortedPlayers.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
                                      
                                      // Use ListView instead of Table for more reliable rendering
                                      return ListView.builder(
                                        shrinkWrap: true,
                                        physics: NeverScrollableScrollPhysics(), // Disable scrolling as we're in a SingleChildScrollView
                                        itemCount: sortedPlayers.length,
                                        itemBuilder: (context, i) {
                                          final item = sortedPlayers[i];
                                          final playerName = item['name'] as String;
                                          final playerTime = item['time'] as int;
                                          final isActive = item['active'] as bool;
                                          final player = item['player'] as Map<String, dynamic>;
                                          final playerId = player['id'];
                                          
                                          // Create a stable key
                                          final stableKey = ValueKey('table-${playerId ?? playerName}');
                                          
                                          // Use simplified widget structure
                                          return Container(
                                            key: stableKey,
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? (isDark ? AppThemes.darkGreen.withOpacity(0.7) : AppThemes.lightGreen.withOpacity(0.7)) // Using withOpacity temporarily
                                                  : (isDark ? AppThemes.darkRed.withOpacity(0.7) : AppThemes.lightRed.withOpacity(0.7)), // Using withOpacity temporarily
                                              border: playerTime >= appState.session.targetPlayDuration
                                                  ? Border.all(
                                                      color: Colors.amber.shade200.withOpacity(0.5), // Using withOpacity temporarily
                                                      width: 1.0,
                                                    )
                                                  : null,
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 2,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                                    child: Text(
                                                      playerName,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 1,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                                    child: Text(
                                                      _formatTime(playerTime),
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    }
                                  ),
                                )
                              : SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    
                    // Action buttons in 2x2 grid with soccer ball
                    Container(
                      height: 120, // Fixed height for button container
                      child: Stack(
                         alignment: Alignment.center,
                         children: [
                           // Bottom action buttons with space for soccer ball
                           Column(
                             mainAxisAlignment: MainAxisAlignment.end, // Changed from spaceBetween to end
                             children: [
                               // Top row buttons
                               Row(
                                 children: [
                                   // Pause button
                                   Expanded(
                                     child: Padding(
                                       padding: const EdgeInsets.only(right: 2, bottom: 4), // Added bottom padding
                                       child: ElevatedButton(
                                         onPressed: _pauseAll,
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: appState.session.isSetup
                                             ? Colors.blue.shade600
                                             : (_isPaused 
                                                 ? Colors.green.shade600
                                                 : (isDark ? AppThemes.darkPauseButton : AppThemes.lightPauseButton)),
                                           padding: EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.white,
                                           textStyle: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             fontSize: _isPaused ? 16 : 15,
                                             letterSpacing: 2.0,
                                           ),
                                           elevation: _isPaused ? 8 : 2,
                                           shadowColor: _isPaused ? Colors.green.shade900 : Colors.black38,
                                         ),
                                         child: Row(
                                           mainAxisAlignment: MainAxisAlignment.center,
                                           children: [
                                             Icon(
                                               appState.session.isSetup
                                                 ? Icons.play_arrow
                                                 : (_isPaused ? Icons.play_circle : Icons.pause_circle),
                                               size: 20
                                             ),
                                             SizedBox(width: 8),
                                             Text(
                                               appState.session.isSetup
                                                 ? 'Start Match'
                                                 : (_isPaused ? 'Resume' : 'Pause')
                                             ),
                                           ],
                                         ),
                                       ),
                                     ),
                                   ),
                                   // Settings button
                                   Expanded(
                                     child: Padding(
                                       padding: const EdgeInsets.only(left: 2, bottom: 4), // Added bottom padding
                                       child: ElevatedButton(
                                         onPressed: () {
                                           Navigator.push(
                                             context,
                                             MaterialPageRoute(builder: (context) => SettingsScreen()),
                                           );
                                         },
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: isDark ? AppThemes.darkSettingsButton : AppThemes.lightSettingsButton,
                                           padding: EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.white,
                                           textStyle: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             fontSize: 15,
                                             letterSpacing: 2.0,
                                           ),
                                         ),
                                         child: Text('Settings'),
                                       ),
                                     ),
                                   ),
                                 ],
                               ),
                               // Reset button with confirmation
                               Row(
                                 children: [
                                   Expanded(
                                     child: Padding(
                                       padding: const EdgeInsets.only(right: 2, bottom: 4), // Added bottom padding
                                       child: ElevatedButton(
                                         onPressed: () async {
                                           // Add vibration pattern with the same intensity as the pause button
                                           // Use pattern for double vibration effect
                                           await _hapticService.resetButton(context);
                                           
                                           showDialog(
                                             context: context,
                                             builder: (BuildContext context) {
                                               return AlertDialog(
                                                 title: Text(
                                                   'Reset Match',
                                                   style: TextStyle(
                                                     fontSize: 20,
                                                     fontWeight: FontWeight.bold,
                                                     color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                                     letterSpacing: 0.5,
                                                   ),
                                                 ),
                                                 content: Text('Are you sure you want to reset all timers?'),
                                                 actions: [
                                                   TextButton(
                                                     child: Text('Cancel'),
                                                     onPressed: () {
                                                       Navigator.of(context).pop();
                                                     },
                                                   ),
                                                   TextButton(
                                                     child: Text('Reset'),
                                                     onPressed: () {
                                                       Navigator.of(context).pop();
                                                       _resetAll();
                                                     },
                                                   ),
                                                 ],
                                               );
                                             },
                                           );
                                         },
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: isDark ? AppThemes.darkExitButton : AppThemes.lightExitButton,
                                           padding: EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.white,
                                           textStyle: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             fontSize: 15,
                                             letterSpacing: 2.0,
                                           ),
                                         ),
                                         child: Text('Reset'),
                                       ),
                                     ),
                                   ),
                                   // Exit button
                                   Expanded(
                                     child: Padding(
                                       padding: const EdgeInsets.only(left: 2, bottom: 4), // Added bottom padding
                                       child: ElevatedButton(
                                         onPressed: () {
                                           showDialog(
                                             context: context,
                                             builder: (BuildContext context) {
                                               return AlertDialog(
                                                 title: Text(
                                                   'Exit Match',
                                                   style: TextStyle(
                                                     fontSize: 20,
                                                     fontWeight: FontWeight.bold,
                                                     color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                                     letterSpacing: 0.5,
                                                   ),
                                                 ),
                                                 content: Text('Are you sure you want to exit this match?'),
                                                 actions: [
                                                   TextButton(
                                                     child: Text('Cancel'),
                                                     onPressed: () {
                                                       Navigator.of(context).pop();
                                                     },
                                                   ),
                                                   TextButton(
                                                     child: Text('Exit'),
                                                     onPressed: () {
                                                       Provider.of<AppState>(context, listen: false).clearCurrentSession();
                                                       
                                                       // Cancel any active timers
                                                       _matchTimer?.cancel();
                                                       
                                                       Navigator.of(context).pop();
                                                       _exitToSessionDialog(); // Show session dialog after exiting
                                                     },
                                                   ),
                                                 ],
                                               );
                                             },
                                           );
                                         },
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: Colors.red.shade700,
                                           padding: EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.white,
                                           textStyle: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             fontSize: 15,
                                             letterSpacing: 2.0,
                                           ),
                                         ),
                                         child: Text('Exit'),
                                       ),
                                     ),
                                   ),
                                 ],
                               ),
                             ],
                           ),
                           // Centered soccer ball button
                           Center(
                             child: GestureDetector(
                               onTap: () => _showActionSelectionDialog(context),
                               child: Container(
                                 width: 50,
                                 height: 50,
                                 decoration: BoxDecoration(
                                   shape: BoxShape.circle,
                                   color: isDark ? Colors.grey[800] : Colors.white,
                                   boxShadow: [
                                     BoxShadow(
                                       color: Colors.blue.withOpacity(0.3),
                                       spreadRadius: 5,
                                       blurRadius: 15,
                                       offset: Offset(0, 0),
                                     ),
                                     BoxShadow(
                                       color: Colors.white.withOpacity(0.2),
                                       spreadRadius: 2,
                                       blurRadius: 8,
                                       offset: Offset(0, 0),
                                     ),
                                     BoxShadow(
                                       color: Colors.black.withOpacity(0.2),
                                       spreadRadius: 2,
                                       blurRadius: 8,
                                       offset: Offset(0, 2),
                                     ),
                                   ],
                                 ),
                                 child: Center(
                                   child: SvgPicture.asset(
                                     'assets/images/soccerball.svg',
                                     width: 46,
                                     height: 46,
                                   ),
                                 ),
                               ),
                             ),
                           ),
                         ],
                       ),
                     ),
                  ],
                ),
              ),
            ),
            
            // Whistle button
            if (appState.session.enableSound)  // Only show button if sound is enabled
              Positioned(
                top: MediaQuery.of(context).padding.top + 40,  // Match add player button height
                left: 16,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _audioService.playWhistle();
                      _hapticService.periodEnd(context);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 37,
                      height: 37,
                      decoration: BoxDecoration(
                        color: Color(0xFF555555).withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SvgPicture.asset(
                          'assets/images/white_whistle.svg',
                          colorFilter: ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        
        floatingActionButton: Stack(
          alignment: Alignment.topRight,
          children: [
            // Hint text for empty player list
            if (appState.players.isEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 130, // Lowered another 20px to match button
                right: 16,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Add Players',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              
            // The FAB with pulse animation
            Positioned(
              top: MediaQuery.of(context).padding.top + 85,  // Lowered another 20px
              right: 16,  // Match whistle button's edge distance
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  // Only pulse if there are no players
                  final shouldPulse = appState.players.isEmpty;
                  final scale = shouldPulse ? _pulseAnimation.value : 1.0;
                  
                  return Transform.scale(
                    scale: scale,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showAddPlayerDialog(context),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 37,
                          height: 37,
                          decoration: BoxDecoration(
                            color: shouldPulse 
                                ? Colors.amber.withOpacity(0.9)
                                : Color(0xFF555555).withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 23,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat, // Change from endTop
        
        // Add whistle button on the left side
        floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
      ),
    );
  }
  
  Future<bool?> _showExitConfirmationDialog(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    // If match is running, show end match dialog
    if (!appState.session.isMatchComplete && !appState.session.isSetup) {
      return _showEndMatchConfirmationDialog(context);
    }
    
    // Default exit dialog for non-match scenarios
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Return to Sessions',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Do you want to return to the session selection screen?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 16,
          ),
        ),
        actions: [
          // Cancel button
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : Colors.black54,
            ),
            child: Text('Cancel'),
          ),
          // Exit button
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              _exitToSessionDialog();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            ),
            child: Text('Return to Sessions'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("App lifecycle state changed to: $state");
    
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      final resumeTime = DateTime.now().millisecondsSinceEpoch;
      print("App resumed at $resumeTime");
      
      if (_isInitialized) {
      final appState = Provider.of<AppState>(context, listen: false);
      
        // CRITICAL FIX: Immediately start UI timer to prevent stalling
        if (appState.session.matchRunning && !appState.session.isPaused) {
          print("Immediately starting UI refresh timer to prevent stalling");
          _startMatchTimer(initialDelay: 0); // Start with zero delay
        }
        
        // Sync the match time using the authoritative method in the background service
      _backgroundService.syncTimeOnResume(appState);
      
        // Update UI to reflect the synced time from the service
        setState(() {
          _matchTime = _backgroundService.getCurrentMatchTime();
          _matchTimeNotifier.value = _matchTime;
        });
        
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
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Handle both inactive and paused states as potential background transitions
      final transitionState = state == AppLifecycleState.paused ? "paused" : "inactive";
      print("App potentially going to background (state: $transitionState)");
      
      // Record background time only ONCE per transition sequence
      if (_backgroundEntryTime == null) { // Check if not already set
        final backgroundTime = DateTime.now().millisecondsSinceEpoch;
        print("Recording background entry time at $backgroundTime (state: $transitionState)");
        _backgroundEntryTime = backgroundTime;
        _lastKnownMatchTime = _matchTime; // Use the UI's current time
      } else {
        print("Background entry time already recorded, skipping (state: $transitionState)");
      }
      
      if (_isInitialized) {
        final appState = Provider.of<AppState>(context, listen: false);
        
        // Cancel UI refresh timer ONLY when paused (inactive might just be temporary)
        if (state == AppLifecycleState.paused) {
          print("Cancelling UI refresh timer due to paused state.");
          _matchTimer?.cancel();
          _matchTimer = null;
        }
        
        // Sync state and notify service ONCE per transition
        // Check if _backgroundEntryTime was just set to avoid double calls
        if (_backgroundEntryTime != null && _lastKnownMatchTime != null) { 
            print("Ensuring background service state is synced (state: $transitionState)");
            _backgroundService.syncAppState(appState);
            print("!!! main_screen: Calling _backgroundService.onAppBackground() (state: $transitionState) !!!"); 
            _backgroundService.onAppBackground();
        } else {
             print("!!! main_screen: Skipping call to onAppBackground - background time not set yet (state: $transitionState)");
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
        print("!!! main_screen: Lifecycle change ($transitionState) but _isInitialized is FALSE !!!");
      }
    }
  }
  
  // Helper method to show dialogs with timer management
  void _showManagedDialog(BuildContext context, Widget dialog) {
    // Ensure timers aren't destroyed when showing a dialog
    final wasRunning = _backgroundService.isTimerActive();
    
    // Create a new temporary timer to keep checking time updates
    // even when a dialog is shown
    Timer? dialogTimer;
    if (wasRunning) {
      dialogTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
        setState(() {
          // Keep UI in sync with background timer
          _matchTime = _backgroundService.getCurrentMatchTime();
          _matchTimeNotifier.value = _matchTime;
        });
      });
    }
    
            showDialog(
              context: context,
              barrierDismissible: false,
      builder: (context) => dialog,
    ).then((_) {
      // Clean up temporary timer
      dialogTimer?.cancel();
    });
  }
  
  // Modify the existing dialog method to track focus changes
  void _showDialogWithFocusTracking(Widget dialog) {
    // Notify background service that screen is losing focus due to dialog
    //_backgroundService.onScreenFocusChange(false);
    
            showDialog(
              context: context,
              barrierDismissible: false,
      builder: (context) => dialog,
    ).then((_) {
      // Notify background service that screen regained focus after dialog closed
      //_backgroundService.onScreenFocusChange(true);
    });
  }
  
  // Updated implementation of _showPeriodEndDialog
  void _showPeriodEndDialog(BuildContext context, int periodNumber) {
    print("\n\n🔔🔔🔔 _showPeriodEndDialog called for period $periodNumber 🔔🔔🔔\n\n");
    
    // Ensure all timers are paused when period end dialog shows
    _matchTimer?.cancel();
    _matchTimer = null;
    
    // Make sure background timer is paused too
    print("Pausing background timer before showing dialog");
    _backgroundService.pauseTimer();
    
    // Update app state to reflect paused state
                  final appState = Provider.of<AppState>(context, listen: false);
    appState.session.isPaused = true;
    
    // Update UI state to reflect paused state
    setState(() {
      _isPaused = true;
    });
    
    // Show dialog with error handling
    try {
      print("Attempting to show period end dialog");
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          print("Dialog builder called");
          return PeriodEndDialog(
            onNextPeriod: () {
              print("Period End Dialog: Next Period button pressed");
              final appState = Provider.of<AppState>(dialogContext, listen: false);
              
              // Start the next period
              appState.startNextPeriod();
              
              // Update background service with new match time
              _backgroundService.setMatchTime(appState.session.matchTime);
              
              // Resume the background timer
              _backgroundService.resumeTimer();
              
              // Start the UI timer
              _startMatchTimer();
              
              // Update UI state
              setState(() {
                _isPaused = false;
                appState.session.isPaused = false;
              });
                  
                  // Close the dialog
              Navigator.of(dialogContext).pop();
            },
          );
        },
      ).then((_) {
        print("Period end dialog closed");
      }).catchError((error) {
        print("ERROR showing period end dialog: $error");
      });
    } catch (e) {
      print("CRITICAL ERROR trying to show period end dialog: $e");
    }
  }

  // Add this new method to safely exit to home screen
  void _safeExitToHomeScreen() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // First make sure timers are stopped
    _matchTimer?.cancel();
    
    // Then clear the session
    appState.clearCurrentSession();
    appState.saveSession();
    
    // Navigate safely back to home screen, where the session dialog will be shown
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
  
  // Add this method to exit to session dialog
  void _exitToSessionDialog() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // First make sure timers are stopped
    _matchTimer?.cancel();
    
    // Save current session before exiting
    appState.saveSession();
    
    // Navigate back to home screen but immediately show session dialog
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false).then((_) {
      // After navigation is complete, show the session dialog
      // Use a short delay to ensure the screen is fully loaded
      Future.delayed(Duration(milliseconds: 100), () {
        if (context.mounted) {
          // Access the SessionPromptScreen's method to show the dialog
          // This requires changes to session_prompt_screen.dart too
          Navigator.of(context).pushNamed('/show_session_dialog');
        }
      });
    });
  }

  void _startNextPeriod() {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Call the app state method to handle period transition
    appState.startNextPeriod();
    
    // Update the background service with the new match time
    _backgroundService.setMatchTime(appState.session.matchTime);
    
    // Auto-start new period by default
    // Note: We're using a simple check since the session model doesn't have
    // an enableAutoStartPeriods property
    _backgroundService.resumeTimer();
    _startMatchTimer(); // This starts the UI refresh timer
    
    setState(() {
      _isPaused = false;
    });
    
    // Update app state
    appState.session.matchRunning = true;
    appState.session.isPaused = false;
  }

  // Helper for ordinal numbers (1st, 2nd, 3rd, etc.)
  String _getOrdinal(int number) {
    if (number == 1) return '1st';
    if (number == 2) return '2nd';
    if (number == 3) return '3rd';
    return '${number}th';
  }
  
  void _showMatchEndDialog(BuildContext context) {
    print("\n\n🏆🏆🏆 _showMatchEndDialog called - showing match end dialog 🏆🏆🏆\n\n");
    
    // Stop the UI refresh timer
    _matchTimer?.cancel();
    _matchTimer = null;
    
    // Ensure background timer is completely stopped, not just paused
    print("Stopping background timer for match end");
    _backgroundService.stopBackgroundTimer();
    
    // Explicitly stop any vibration reminders
    print("Stopping vibration reminders");
    _backgroundService.stopReminderVibrations();
    
    // Update app state
    final appState = Provider.of<AppState>(context, listen: false);
    appState.session.isPaused = true;
    appState.session.matchRunning = false;
    appState.session.isMatchComplete = true;
    print("Updated app state: isPaused=${appState.session.isPaused}, isMatchComplete=${appState.session.isMatchComplete}");
    
    // Update UI state
    setState(() {
      _isPaused = true;
    });
    
    // Now show the match end dialog with error handling
    try {
      print("Attempting to show match end dialog");
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          print("Match end dialog builder called");
          return PeriodEndDialog(
            isMatchEnd: true,
            onOk: () {
              print("Match End Dialog: OK button pressed");
              final appState = Provider.of<AppState>(dialogContext, listen: false);
              
              // Use the dedicated method to ensure match end is logged
              appState.ensureMatchEndLogged();
              print("Match end logged in app state");
              
              // One more check to stop any vibrations
              _backgroundService.stopReminderVibrations();
              
              // Close the dialog
              Navigator.of(dialogContext).pop();
            },
          );
        },
      ).then((_) {
        print("Match end dialog closed");
      }).catchError((error) {
        print("ERROR showing match end dialog: $error");
      });
    } catch (e) {
      print("CRITICAL ERROR trying to show match end dialog: $e");
    }
  }
}

// Add these widget classes before the MainScreen class

class StatusBar extends StatelessWidget {
  final bool isDark;
  final int activePlayerCount;
  final int inactivePlayerCount;
  final int teamGoals;
  final int opponentGoals;
  final bool isPaused;
  final bool isMatchComplete;
  final bool isSetup;
  final bool enableTargetDuration;
  final bool enableMatchDuration;
  final int targetPlayDuration;
  final int matchDuration;

  const StatusBar({
    Key? key,
    required this.isDark,
    required this.activePlayerCount,
    required this.inactivePlayerCount,
    required this.teamGoals,
    required this.opponentGoals,
    required this.isPaused,
    required this.isMatchComplete,
    required this.isSetup,
    required this.enableTargetDuration,
    required this.enableMatchDuration,
    required this.targetPlayDuration,
    required this.matchDuration,
  }) : super(key: key);

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Define the colors based on the dark theme settings
    final statusBarBackgroundColor = isDark 
        ? Colors.black38 
        : Colors.grey.shade300; // More opaque light theme background
    final statusTextColor = isDark 
        ? Colors.white70
        : Colors.black87; // Darker text for light theme

    return Container(
      margin: EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: statusBarBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Player statistics
          Row(
            children: [
              Icon(Icons.person, color: Colors.green.shade400, size: 14),
              Text(
                ' $activePlayerCount',
                style: TextStyle(
                  fontSize: 12,
                  color: statusTextColor,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.person_outline, color: Colors.red.shade400, size: 14),
              Text(
                ' $inactivePlayerCount',
                style: TextStyle(
                  fontSize: 12,
                  color: statusTextColor,
                ),
              ),
            ],
          ),
          // Score indicator
          Row(
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/images/soccerball.svg',
                    height: 14,
                    width: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '$teamGoals - $opponentGoals',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Match status and duration indicators
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Match status (setup or paused indicator)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSetup 
                    ? Colors.blue.withOpacity(0.2)
                    : (isPaused ? Colors.orange.withOpacity(0.2) : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                  border: isSetup || (isPaused && !isMatchComplete)
                    ? Border.all(
                        color: isSetup 
                          ? Colors.blue.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5),
                      )
                    : null,
                ),
                child: isSetup
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings, color: Colors.blue, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'SETUP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    )
                  : isPaused && !isMatchComplete
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause, color: Colors.orange, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'PAUSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      )
                    : SizedBox(width: 65),  // Maintain consistent width
              ),
              // Duration indicators - always show but with opacity based on enabled state
              SizedBox(width: 8),
              Opacity(
                opacity: enableTargetDuration ? 1.0 : 0.0,
                child: Row(
                  children: [
                    Icon(Icons.person_pin_circle, color: Colors.amber.shade400, size: 14),
                    SizedBox(width: 2),
                    Text(
                      _formatTime(targetPlayDuration),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Opacity(
                opacity: enableMatchDuration ? 1.0 : 0.0,
                child: Row(
                  children: [
                    Icon(Icons.timer, color: Colors.blue.shade400, size: 14),
                    SizedBox(width: 2),
                    Text(
                      _formatTime(matchDuration),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlayerListItem extends StatelessWidget {
  final String playerName;
  final String playerId;
  final bool isActive;
  final int playerTime;
  final bool isPaused;
  final bool isSetup;  // Add isSetup parameter
  final bool wasActiveDuringPause;
  final bool isDark;
  final int targetPlayDuration;
  final int? goals;
  final bool isReadOnlyMode;
  final Function(String) onToggle;
  final Function(String) onLongPress;

  const PlayerListItem({
    Key? key,
    required this.playerName,
    required this.playerId,
    required this.isActive,
    required this.playerTime,
    required this.isPaused,
    required this.isSetup,  // Add isSetup parameter
    required this.wasActiveDuringPause,
    required this.isDark,
    required this.targetPlayDuration,
    required this.goals,
    required this.isReadOnlyMode,
    required this.onToggle,
    required this.onLongPress,
  }) : super(key: key);

  List<Color> _getPlayerButtonColors() {
    if (isSetup || isPaused) {  // Handle both setup and pause modes
      if (isActive) {
        return [
          Color.fromARGB(255, 94, 141, 117),
          Color(0xFF2E7D5F),
        ];
      } else if (wasActiveDuringPause) {
        return [
          Color.fromARGB(255, 94, 141, 117),
          Color.fromARGB(255, 94, 141, 117),
        ];
      } else {
        return [
          isDark ? Color(0xFF8B4343) : Color(0xFFB45757),
          isDark ? Color(0xFF6B3232) : Color(0xFF8B4343),
        ];
      }
    } else {
      if (isActive) {
        return [
          Colors.green,
          Colors.green.shade800,
        ];
      } else {
        return [
          isDark ? Colors.red.shade700 : Colors.red.shade600,
          isDark ? Colors.red.shade900 : Colors.red.shade800,
        ];
      }
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final buttonColors = _getPlayerButtonColors();
    
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        colors: buttonColors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: (targetPlayDuration > 0 && playerTime >= targetPlayDuration)
        ? [
            const BoxShadow(
              color: Color(0x4DFFD700),
              blurRadius: 10,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Color(0x42000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x42000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
      border: (targetPlayDuration > 0 && playerTime >= targetPlayDuration)
        ? Border.all(
            color: const Color(0x80FFD700),
            width: 1.2,
          )
        : null,
    );

    return Padding(
      key: ValueKey('player-$playerId-$playerName'),
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isReadOnlyMode ? null : () => onToggle(playerName),
            onLongPress: isReadOnlyMode ? null : () => onLongPress(playerName),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          playerName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((goals ?? 0) > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'assets/images/soccerball.svg',
                                height: 20,
                                width: 20,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${goals ?? 0}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        decoration: const BoxDecoration(
                          color: Color(0x61000000),
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Text(
                          _formatTime(playerTime),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (targetPlayDuration > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: SizedBox(
                      height: 3,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(2)),
                        child: LinearProgressIndicator(
                          value: (playerTime / targetPlayDuration).clamp(0.0, 1.0),
                          backgroundColor: const Color(0x61000000),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            playerTime >= targetPlayDuration
                              ? Colors.amber.shade600
                              : Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}