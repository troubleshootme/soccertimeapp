import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'package:flutter/material.dart';

class AudioService {
  final AudioPlayer player = AudioPlayer();
  bool _isInitialized = false;
  BuildContext? _context;
  
  AudioService() {
    _init();
  }
  
  void setContext(BuildContext context) {
    _context = context;
  }
  
  Future<void> _init() async {
    try {
      // Pre-load the sound for faster playback
      await player.setSource(AssetSource('whistle.mp3'));
      _isInitialized = true;
    } catch (e) {
      print('Error initializing audio player: $e');
      _isInitialized = false;
    }
  }
  
  Future<void> playWhistle() async {
    if (_context == null) {
      print('Cannot play whistle: no context set');
      return;
    }
    
    // Get sound setting from AppState
    final appState = Provider.of<AppState>(_context!, listen: false);
    final soundEnabled = appState.session.enableSound;
    
    print('Attempting to play whistle. Sound enabled: $soundEnabled');
    
    if (!soundEnabled) {
      print('Whistle sound not played: sound is disabled in settings');
      return;
    }
    
    if (!_isInitialized) {
      // Try to initialize again if it failed before
      await _init();
    }
    
    try {
      // Using the newer syntax for audioplayers 5.x.x
      if (_isInitialized) {
        await player.stop(); // Stop any currently playing sound
        await player.play(AssetSource('whistle.mp3'));
      } else {
        // Fallback: we couldn't play the sound, but we'll log it
        print('Whistle sound was requested but audio is not available');
      }
    } catch (e) {
      // Catch and log any errors, but don't crash the app
      print('Error playing whistle sound: $e');
    }
  }
  
  void dispose() {
    player.dispose();
  }
}
