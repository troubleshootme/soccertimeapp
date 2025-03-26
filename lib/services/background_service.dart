import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isWakelockEnabled = false;
  Timer? _backgroundTimer;

  Future<void> initialize() async {
    // Request necessary permissions
    await Permission.notification.request();
    
    // Enable wakelock to keep screen on
    await enableWakelock();
  }

  Future<void> enableWakelock() async {
    if (!_isWakelockEnabled) {
      await WakelockPlus.enable();
      _isWakelockEnabled = true;
    }
  }

  Future<void> disableWakelock() async {
    if (_isWakelockEnabled) {
      await WakelockPlus.disable();
      _isWakelockEnabled = false;
    }
  }

  void startBackgroundTimer(AppState appState) {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (appState.session.isMatchRunning) {
        // Update match time and check for period changes
        appState.updateMatchTimer();
        
        // Check for period end
        if (appState.shouldEndPeriod()) {
          appState.endPeriod();
        }
        
        // Check for match end
        if (appState.shouldEndMatch()) {
          appState.endMatch();
        }
      }
    });
  }

  void stopBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> dispose() async {
    stopBackgroundTimer();
    await disableWakelock();
  }
} 