import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'dart:async';

class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  // Add this variable to track last period end feedback time
  DateTime? _lastPeriodEndTime;
  final _periodEndDebounceMillis = 1500; // 1.5 seconds

  // Add match end debounce
  DateTime? _lastMatchEndTime;
  final _matchEndDebounceMillis = 1500; // 1.5 seconds
  
  // Countdown vibration timers
  Timer? _periodCountdownTimer;
  Timer? _matchCountdownTimer;
  
  // Constants for countdown
  static const int countdownDurationSeconds = 5;
  
  bool _isVibrationEnabled(BuildContext context) {
    return Provider.of<AppState>(context, listen: false).session.enableVibration;
  }
  
  // New method to handle countdown vibrations before period end
  Future<void> startPeriodEndCountdown(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    // Cancel any existing countdown timer
    _periodCountdownTimer?.cancel();
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    
    // Track remaining seconds
    int remainingSeconds = countdownDurationSeconds;
    
    // Immediately vibrate for the first time
    _singleCountdownVibration();
    
    // Create a timer that fires every second
    _periodCountdownTimer = Timer.periodic(
      Duration(seconds: 1), 
      (timer) async {
        remainingSeconds--;
        
        if (remainingSeconds <= 0) {
          // Time's up - cancel timer
          timer.cancel();
          _periodCountdownTimer = null;
        } else {
          // Vibrate with an intensity that increases as we get closer to 0
          _singleCountdownVibration();
        }
      }
    );
  }
  
  // New method to handle countdown vibrations before match end
  Future<void> startMatchEndCountdown(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    // Cancel any existing countdown timer
    _matchCountdownTimer?.cancel();
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    
    // Track remaining seconds
    int remainingSeconds = countdownDurationSeconds;
    
    // Immediately vibrate for the first time
    _singleCountdownVibration();
    
    // Create a timer that fires every second
    _matchCountdownTimer = Timer.periodic(
      Duration(seconds: 1), 
      (timer) async {
        remainingSeconds--;
        
        if (remainingSeconds <= 0) {
          // Time's up - cancel timer
          timer.cancel();
          _matchCountdownTimer = null;
        } else {
          // Vibrate with an intensity that increases as we get closer to 0
          _singleCountdownVibration();
        }
      }
    );
  }
  
  // Helper method for single countdown vibration
  Future<void> _singleCountdownVibration() async {
    // Short, distinct vibration for countdown
    await Vibration.vibrate(duration: 80, amplitude: 150);
  }
  
  // Method to stop all countdown timers
  void stopAllCountdowns() {
    _periodCountdownTimer?.cancel();
    _periodCountdownTimer = null;
    
    _matchCountdownTimer?.cancel();
    _matchCountdownTimer = null;
  }

  Future<void> playerToggle(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 50, amplitude: 128);
    }
  }

  Future<void> matchPause(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100, amplitude: 192);
    }
  }

  Future<void> periodEnd(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    // Stop any countdown timers
    _periodCountdownTimer?.cancel();
    _periodCountdownTimer = null;
    
    // Add debounce check
    final now = DateTime.now();
    if (_lastPeriodEndTime != null && 
        now.difference(_lastPeriodEndTime!).inMilliseconds < _periodEndDebounceMillis) {
      print("Skipping period end haptic feedback - too soon after last one");
      return;
    }
    
    _lastPeriodEndTime = now;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Enhanced vibration pattern for period end - more noticeable
      // Pattern: medium, pause, medium, pause, long
      Vibration.vibrate(
        pattern: [0, 150, 150, 150, 150, 300], 
        intensities: [0, 192, 0, 192, 0, 255]
      );
    }
  }

  Future<void> matchEnd(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    // Stop any countdown timers
    _matchCountdownTimer?.cancel();
    _matchCountdownTimer = null;
    
    // Add debounce check
    final now = DateTime.now();
    if (_lastMatchEndTime != null && 
        now.difference(_lastMatchEndTime!).inMilliseconds < _matchEndDebounceMillis) {
      print("Skipping match end haptic feedback - too soon after last one");
      return;
    }
    
    _lastMatchEndTime = now;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Enhanced vibration pattern for match end - very distinctive
      // Pattern: short, pause, medium, pause, medium, pause, long, pause, very long
      Vibration.vibrate(
        pattern: [0, 100, 100, 200, 100, 200, 100, 300, 150, 400], 
        intensities: [0, 200, 0, 225, 0, 225, 0, 250, 0, 255]
      );
    }
  }

  Future<void> matchStart(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.session.enableVibration) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Double vibration pattern for match start
        await Vibration.vibrate(duration: 100);
        await Future.delayed(Duration(milliseconds: 150));
        await Vibration.vibrate(duration: 200);
      }
    }
  }
  
  Future<void> resumeButton(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Strong vibration for resume button
      Vibration.vibrate(duration: 80, amplitude: 200);
    }
  }
  
  Future<void> resetButton(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Double vibration pattern with same intensity as pause button
      Vibration.vibrate(pattern: [0, 100, 150, 100], intensities: [0, 192, 0, 192]);
    }
  }
  
  Future<void> soccerBallButton(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Gentle vibration for soccer ball button
      Vibration.vibrate(duration: 40, amplitude: 100);
    }
  }
} 