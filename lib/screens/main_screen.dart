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
  final AudioService _audioService = AudioService();
  final HapticService _hapticService = HapticService();
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

  @override
  void initState() {
    super.initState();
    
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
    });
    
    // Use Future.microtask instead of post-frame callback for safer initialization
    Future.microtask(() {
      if (mounted) {
        _loadInitialState();
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - refresh state
      if (mounted && _isInitialized) {
        final appState = Provider.of<AppState>(context, listen: false);
        
        print("App resumed, current match time: ${appState.session.matchTime}, running: ${appState.session.matchRunning}, paused: ${appState.session.isPaused}");
        
        // If the background service is running, stop the background timer and sync the time
        if (_backgroundService.isRunning) {
          print("App resumed from background, syncing time...");
          
          // Check if period/match end events were detected in background
          final periodEndOccurred = _backgroundService.periodEndDetected;
          final matchEndOccurred = _backgroundService.matchEndDetected;
          
          // First sync the time that passed in the background
          _backgroundService.syncTimeOnResume(appState);
          
          // Wait a short moment to ensure sync is completed
          Future.delayed(Duration(milliseconds: 300), () {
            // Then stop the background timer
            _backgroundService.stopBackgroundTimer();
            
            // Get updated match time after sync
            final updatedMatchTime = appState.session.matchTime;
            print("After sync, match time is now: $updatedMatchTime");
            
            // Properly restore the match time from saved state
            _safeSetState(() {
              // Make sure the local match time is in sync with the saved session match time
              _matchTime = updatedMatchTime; 
              _matchTimeNotifier.value = updatedMatchTime;
              
              // Make sure pause state is in sync with session state
              _isPaused = appState.session.isPaused;
              
              // Special handling for final period transition
              // If we're in the final period and just came from transition, ensure clean timer state
              final isInFinalPeriod = appState.session.currentPeriod == appState.session.matchSegments;
              if (isInFinalPeriod && appState.session.matchRunning && !appState.session.isPaused) {
                print("Detected resumed in final period - ensuring clean timer state");
                // Cancel timer first if it exists
                _matchTimer?.cancel();
                _matchTimer = null;
                
                // Force session state to be running and not paused
                appState.session.matchRunning = true;
                appState.session.isPaused = false;
                _isPaused = false;
              }
            });
            
            // Check if a period ended while in background first
            // Do this BEFORE showing notifications to ensure proper UI state
            _checkPeriodEnd();
            
            // Only show period end notification if it occurred in background
            // AND the dialog was not shown (periodsTransitioning should be false after checkPeriodEnd if dialog was shown)
            if (periodEndOccurred && !appState.periodsTransitioning && !appState.session.hasWhistlePlayed) {
              _showPeriodEndNotification(appState.session.currentPeriod);
            }
            
            // Only show match end notification if it occurred in background 
            // AND dialog was not shown
            if (matchEndOccurred && !appState.session.isMatchComplete) {
              _showMatchEndNotification();
            }
            
            // Reset event flags after handling them
            _backgroundService.resetEventFlags();
            
            // Restart the UI timer if the match is still running
            if (appState.session.matchRunning && !appState.session.isPaused) {
              _startMatchTimer();
            }
            
            // Force UI refresh
            setState(() {});
          });
        } else {
          // Properly restore the match time from saved state
          _safeSetState(() {
            // Make sure the local match time is in sync with the saved session match time
            _matchTime = appState.session.matchTime;
            _matchTimeNotifier.value = _matchTime;
            
            // Make sure pause state is in sync with session state
            _isPaused = appState.session.isPaused;
          });
          
          // Check if a period ended while in background
          _checkPeriodEnd();
          
          // Restart the UI timer if the match is still running
          if (appState.session.matchRunning && !appState.session.isPaused) {
            _startMatchTimer();
          }
          
          // Force UI refresh
          setState(() {});
        }
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App went to background - save state but don't pause timers
      if (mounted && _isInitialized) {
        final appState = Provider.of<AppState>(context, listen: false);
        
        // Make sure the session match time is updated before saving
        appState.session.matchTime = _matchTime;
        
        // Update the lastUpdateTime to the current time before going to background
        appState.session.lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        
        // Save the current state to persist it
        appState.saveSession();
        
        // Start background service if the match is running and not paused
        if (appState.session.matchRunning && !appState.session.isPaused) {
          // Start the background service to keep timers running
          print("Starting background service for match...");
          _backgroundService.startBackgroundService().then((success) {
            if (success) {
              print("Background service started successfully, starting timer...");
              // Start the background timer to continue updating match time
              _backgroundService.startBackgroundTimer(appState);
            } else {
              print("Failed to start background service");
            }
          });
        }
      }
    }
  }
  
  void _loadInitialState() async {
    if (!mounted) return;
    
    try {
      print('Loading initial state...');
      final appState = Provider.of<AppState>(context, listen: false);
      
      // Ensure our UI displays the correct time
      _safeSetState(() {
        _matchTime = appState.session.matchTime;
        _matchTimeNotifier.value = _matchTime; // Update notifier as well
        _isPaused = appState.session.isPaused;
        
        // Determine the session name to display in the UI
        String nameToDisplay = '';
        
        // First priority: Use currentSessionPassword if available
        if (appState.currentSessionPassword != null && appState.currentSessionPassword!.isNotEmpty) {
          nameToDisplay = appState.currentSessionPassword!;
        } 
        // Second priority: Use session object name
        else if (appState.session.sessionName.isNotEmpty) {
          nameToDisplay = appState.session.sessionName;
        }
        // Last resort: Use a default with the session ID
        else if (appState.currentSessionId != null) {
          // Check in sessions list for a better name
          final sessionInfo = appState.sessions.firstWhere(
            (s) => s['id'] == appState.currentSessionId,
            orElse: () => {'name': 'Session ${appState.currentSessionId}'}
          );
          nameToDisplay = sessionInfo['name'] ?? 'Session ${appState.currentSessionId}';
        } else {
          nameToDisplay = 'New Session';
        }
        
        // Set the session name for display
        _sessionName = nameToDisplay;
        
        // If we have active players but a timestamp mismatch, update timestamps
        if (appState.session.matchRunning && !appState.session.isPaused) {
          // Update the session's lastUpdateTime to now to prevent jumps
          appState.session.lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        }
        
        // Start pulsing animation if there are no players
        if (appState.players.isEmpty) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
        }
      });
      
      // Set initialized flag
      _isInitialized = true;
      
      // Start timer only after state is updated
      Future.microtask(() {
        if (mounted && appState.session.matchRunning && !appState.session.isPaused) {
          _startMatchTimer();
        }
      });
    } catch (e) {
      if (mounted) {
        _safeSetState(() {
          _isInitialized = true;
        });
        
        // Show a snackbar with the error
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading session data: ${e.toString()}'),
                duration: Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Return',
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/');
                  },
                ),
              ),
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    // Unregister observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel timer before disposing
    if (_matchTimer != null) {
      _matchTimer!.cancel();
      _matchTimer = null;
    }
    _addPlayerFocusNode.dispose();
    
    // Dispose the animation controller
    _pulseController.dispose();
    
    // Dispose the audio service
    _audioService.dispose();
    
    // Dispose the background service
    _backgroundService.dispose();
    
    _lastUpdateTimestamp = null;
    
    _matchTimeNotifier.dispose();
    
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

  void _startMatchTimer() {
    _matchTimer?.cancel();
    final appState = Provider.of<AppState>(context, listen: false);

    // Ensure initial timestamp is set correctly when timer starts/resumes
    _lastUpdateTimestamp = DateTime.now().millisecondsSinceEpoch;
    _lastRealTimeCheck = _lastUpdateTimestamp; // Initialize real time check
    appState.session.lastUpdateTime = _lastUpdateTimestamp! ~/ 1000; // Update AppState timestamp

    print('UI Timer Started/Resumed at: $_lastUpdateTimestamp ms (${appState.session.lastUpdateTime} s)'); // Log start time

    // Change the Duration here from milliseconds: 200 to seconds: 1
    _matchTimer = Timer.periodic(Duration(seconds: 1), (timer) { // NOW 1 SECOND INTERVAL
      if (!_isPaused && mounted) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Use _lastUpdateTimestamp for UI timer calculation
        final lastUpdate = _lastUpdateTimestamp ?? now;
        final elapsedMillis = now - lastUpdate;

        // Process only if roughly a second or more has passed (or clock jumped back)
        if (elapsedMillis >= 950 || elapsedMillis < 0) { // Allow a small threshold < 1000ms
          if (elapsedMillis < 0) {
            // Handle potential clock adjustments
            print("Warning: UI Timer clock adjustment detected (elapsed time negative: $elapsedMillis). Resetting last update time.");
            _lastUpdateTimestamp = now;
            appState.session.lastUpdateTime = now ~/ 1000;
            // Skip the rest of the update for this tick to avoid bad calculations
            return;
          }

          // Use floating point seconds for calculations
          final elapsedSeconds = elapsedMillis / 1000.0;
          final oldMatchTime = _matchTime; // Capture time before update
          final appStateTime = appState.session.matchTime; // Capture AppState time for comparison

          // --- START Detailed Logging ---
          print('--- UI Timer Tick ---');
          print('  Now         : $now ms');
          print('  LastUpdate  : $lastUpdate ms');
          print('  ElapsedMs   : $elapsedMillis ms');
          print('  OldMatchTime: $oldMatchTime (UI)');
          print('  AppStateTime: $appStateTime (State)');
          // --- END Detailed Logging ---

          // --- Drift Correction ---
          double driftAdjustmentSeconds = 0;
          if (_lastRealTimeCheck != null) {
             final realElapsed = now - _lastRealTimeCheck!;
             // Expected elapsed should be around 1000ms now
             final timerElapsed = elapsedMillis;
             final driftMillis = realElapsed - timerElapsed;
             driftAdjustmentSeconds = driftMillis / 1000.0;
             _accumulatedDrift += driftAdjustmentSeconds;
             // Log only significant drift adjustments
             if (driftMillis.abs() > 100) { // Log if drift > 100ms (adjust threshold as needed)
                print('  DriftCheck  : Real=${realElapsed}ms, Timer=${timerElapsed}ms, Adjust=${driftAdjustmentSeconds.toStringAsFixed(3)}s, Accum=${_accumulatedDrift.toStringAsFixed(3)}s');
             }
          }
          _lastRealTimeCheck = now;
          // --- End Drift Correction ---


          // Calculate new time carefully
          final newMatchTimeDouble = oldMatchTime + elapsedSeconds + driftAdjustmentSeconds; // Apply adjustment
          final newMatchTime = newMatchTimeDouble.round(); // Round back to int

          // --- More Logging ---
          print('  NewMatchTime: $newMatchTime (Raw: ${newMatchTimeDouble.toStringAsFixed(3)})');
          if (newMatchTime < oldMatchTime) {
             print('  *** WARNING: UI Timer decreased! Old: $oldMatchTime, New: $newMatchTime ***');
          }
          // Check against AppState time as well
           if (newMatchTime < appStateTime) {
             print('  *** WARNING: UI Timer behind AppState! UI: $newMatchTime, State: $appStateTime ***');
          }
          // --- End More Logging ---


          _safeSetState(() {
            _matchTime = newMatchTime;
            _matchTimeNotifier.value = _matchTime;
            // Pass precise elapsed time in seconds (including drift) converted to milliseconds
            appState.updateMatchTimer(elapsedMillis: (elapsedSeconds + driftAdjustmentSeconds) * 1000);
          });

          // Update timestamp *after* all calculations and state updates
          _lastUpdateTimestamp = now;
          // Ensure AppState's lastUpdateTime is also updated consistently
          appState.session.lastUpdateTime = now ~/ 1000;

        }
        // If elapsedMillis is positive but less than ~950ms, just wait for the next tick
      } else if (!mounted) {
        timer.cancel();
      }
    });
  }

  // Check if the period has ended or needs to end
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
        !session.isMatchComplete) {
      
      print("PERIOD UI CHECK: Match end condition met in final period, ending match");
      
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
            builder: (context) => PeriodEndDialog(),
          );
        }
      });
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
            builder: (context) => PeriodEndDialog(),
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
  
  // New method to show match end notification
  void _showMatchEndNotification() {
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
  
  // Helper method for ordinal numbers (1st, 2nd, 3rd, etc.)
  String _getOrdinalNumber(int number) {
    if (number == 1) return '1st';
    if (number == 2) return '2nd';
    if (number == 3) return '3rd';
    return '${number}th';
  }

  void _showStartNextPeriodDialog() {
    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    // Play period end haptic feedback
    _hapticService.periodEnd(context);
    
    // Get the period that just ended (current period - 1) and the next period number
    final justEndedPeriod = appState.session.currentPeriod - 1;  // The period that just ended
    final nextPeriod = appState.session.currentPeriod;  // The next period (already incremented by endPeriod)
    final isQuarters = appState.session.matchSegments == 4;
    
    // Helper function to get period suffix (1st, 2nd, 3rd, 4th)
    String getPeriodSuffix(int period) {
      if (period == 1) return '1st';
      if (period == 2) return '2nd';
      if (period == 3) return '3rd';
      return '${period}th';
    }
    
    // Get the period names based on whether it's halves or quarters
    final endedPeriodText = isQuarters 
        ? '${getPeriodSuffix(justEndedPeriod)} Quarter'
        : '${getPeriodSuffix(justEndedPeriod)} Half';
    
    final nextPeriodText = isQuarters 
        ? '${getPeriodSuffix(nextPeriod)} Quarter'
        : '${getPeriodSuffix(nextPeriod)} Half';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          '$endedPeriodText ended',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Start $nextPeriodText?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () async {
              await appState.startNextPeriod();
              Navigator.of(context).pop();
              // Restart the timer after the period transition
              _startMatchTimer();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            child: Text('Start'),
          ),
        ],
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

    // Toggle player state without awaiting
    appState.togglePlayer(playerName);

    // Only start the match timer if we're not paused
    if (!_isPaused && !appState.session.isPaused) {
      if (appState.session.players[playerName]?.active ?? false) {
        _safeSetState(() {
          appState.session.matchRunning = true;
        });
      }
    }
  }

  // Modify _pauseAll to handle timestamps
  void _pauseAll() async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // If in setup mode and there are active players, start the match
    if (appState.session.isSetup && _hasActivePlayer()) {
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
      
      // Stop background service if it's running
      if (_backgroundService.isRunning) {
        _backgroundService.stopBackgroundTimer();
        _backgroundService.stopBackgroundService();
      }
      
      await _hapticService.matchPause(context);
      
      // Show pause notification
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
    
    // Save the session state
    await appState.saveSession();
  }

  void _resetAll() async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Provide haptic feedback for reset button press
    await _hapticService.resetButton(context);
    
    // Cancel existing timer
    _matchTimer?.cancel();
    
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
    final textController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Request focus after the dialog is built using a post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _addPlayerFocusNode.canRequestFocus) {
        _addPlayerFocusNode.requestFocus();
      }
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // Use a UniqueKey to ensure the dialog rebuilds properly if reopened quickly
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
          focusNode: _addPlayerFocusNode,
          // Keep autofocus true as a fallback
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Player Name'),
          onSubmitted: (value) async {
            if (value.trim().isNotEmpty) {
              try {
                // Add player and wait for the operation to complete
                final appState = Provider.of<AppState>(context, listen: false);
                await appState.addPlayer(value.trim());

                // Close dialog and update state
                if (context.mounted) {
                  Navigator.pop(context);
                  // Reopen dialog for quick adding of multiple players - keep this for now
                  Future.delayed(Duration(milliseconds: 100), () {
                    if (mounted) _showAddPlayerDialog(context);
                  });
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
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (textController.text.trim().isNotEmpty) {
                try {
                  // Add player and wait for the operation to complete
                  final appState = Provider.of<AppState>(context, listen: false);
                  await appState.addPlayer(textController.text.trim());

                  // Close dialog and update state
                  if (context.mounted) {
                    Navigator.pop(context);
                    // Don't need the WidgetsBinding here, handled by Provider
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
      ),
    ).then((_) {
      // Ensure focus is released when the dialog is dismissed.
      // This prevents potential issues if the screen rebuilds or the node is reused.
      _addPlayerFocusNode.unfocus();
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Player name cannot be empty'))
                );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset time for $playerName')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkTheme;
    
    // Ensure local pause state stays in sync with session state
    if (_isPaused != appState.session.isPaused) {
      // Don't call setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeSetState(() {
          _isPaused = appState.session.isPaused;
        });
      });
    }
    
    // Update animation state based on player count
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hasPlayers = appState.players.isNotEmpty;
      if (hasPlayers && _pulseController.isAnimating) {
        _pulseController.stop();
      } else if (!hasPlayers && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    });
    
    // Ensure session name is always displayed - fix blank session name
    if (_sessionName.isEmpty && appState.currentSessionPassword != null) {
      // Don't call setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeSetState(() {
          _sessionName = appState.currentSessionPassword ?? "Unnamed Session";
          print('Fixed blank session name to: "$_sessionName"');
        });
      });
    }
    
    // If app state isn't ready yet, show a loading screen
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading session data...',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // If there was an error loading the session, show a simple error screen
    if (appState.currentSessionId == null) {
      return Scaffold(
        backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
        appBar: AppBar(
          title: Text('Session Error'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'There was an error loading the session',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'The session may be in read-only mode or the data might be corrupted',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: Text('Return to Sessions'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Wrap the build code in try-catch to make it more resilient
    try {
      return Scaffold(
        backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
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
                                                       Navigator.of(context).pop();
                                                       Navigator.of(context).pushReplacementNamed('/');
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
          ],
        ),
        
        floatingActionButton: Stack(
          alignment: Alignment.topRight,
          children: [
            // Hint text for empty player list
            if (appState.players.isEmpty)
              Positioned(
                top: 85,  // Adjusted down from 45
                right: 0,
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
            Positioned(  // Added Positioned widget to control exact placement
              top: 40,  // Position it 40 pixels from the top
              right: 0,  // Keep it aligned to the right
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
                            boxShadow: shouldPulse ? [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.6),
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ] : null,
                          ),
                          child: Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 23,
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
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      );
    } catch (e) {
      // Return a simple error widget if build fails
      print('Error in MainScreen build: $e');
      return Scaffold(
        body: Center(
          child: Text('Error loading match screen. Please restart the app.'),
        ),
      );
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
  final bool isSetup;  // Add isSetup parameter
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
    required this.isSetup,  // Add isSetup parameter
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
    final statusBarBackgroundColor = Colors.black38;
    final statusTextColor = Colors.white70;

    return Container(
      margin: EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // Always use the dark theme background color
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
                  // Always use the dark theme text color
                  color: statusTextColor,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.person_outline, color: Colors.red.shade400, size: 14),
              Text(
                ' $inactivePlayerCount',
                style: TextStyle(
                  fontSize: 12,
                  // Always use the dark theme text color
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
                      // Always use the dark theme text color
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
                        // Always use the dark theme text color
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
                        // Always use the dark theme text color
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