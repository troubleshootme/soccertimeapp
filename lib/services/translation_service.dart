import 'package:flutter/material.dart';

// Simple TranslationService class to handle translations
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  
  // Singleton pattern
  factory TranslationService() {
    return _instance;
  }
  
  TranslationService._internal();
  
  // Initialize the service
  Future<void> init() async {
    // No actual initialization needed for this implementation
    print('TranslationService initialized');
  }
  
  // Translation map
  final Map<String, String> _translations = {
    'match.match': 'game',
    'match.match_started': 'Match started',
    'match.match_paused': 'Match paused',
    'match.match_resumed': 'Match resumed',
    'match.match_complete': 'Match Complete!',
    'match.match_ended': 'Match Complete!',
    'match.no_active_players': 'No active players',
    'match.active_players_moved': 'active players moved to next period',
    'match.half': 'Half',
    'match.quarter': 'Quarter',
    'match.started': 'started',
    'match.ended': 'ended',
    'match.left_game': 'left the game',
    'match.entered_game': 'entered the game',
    
    // Log screen translations
    'log.match_log': 'Match Log',
    'log.sort_oldest': 'Sort by oldest',
    'log.sort_newest': 'Sort by newest',
    'log.no_events': 'No events recorded yet',
    'log.events_appear': 'Events will appear here as the match progresses',
    'log.just_now': 'just now',
    'log.ago': 'ago',
  };
  
  // Get a translation by key
  String get(String key) {
    return _translations[key] ?? key;
  }
}

// Extension method for BuildContext
extension TranslationExtension on BuildContext {
  String tr(String key) {
    return TranslationService().get(key);
  }
} 