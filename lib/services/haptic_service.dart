import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  bool _isVibrationEnabled(BuildContext context) {
    return Provider.of<AppState>(context, listen: false).session.enableVibration;
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
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Double vibration pattern for period end
      Vibration.vibrate(pattern: [0, 150, 100, 150], intensities: [0, 192, 0, 192]);
    }
  }

  Future<void> matchEnd(BuildContext context) async {
    if (!_isVibrationEnabled(context)) return;
    
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Triple vibration pattern for match end
      Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 200], intensities: [0, 255, 0, 255, 0, 255]);
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