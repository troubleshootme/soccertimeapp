import 'package:flutter/material.dart';
import '../models/session.dart' as models;
import '../models/player.dart';
import '../hive_database.dart';
import '../services/translation_service.dart';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../models/match_log_entry.dart';
import '../services/background_service.dart';

class AppState with ChangeNotifier {
  bool _isDarkTheme = true;
  int? _currentSessionId;
  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _sessions = [];
  String? _currentSessionPassword;
  models.Session _session = models.Session();
  bool _isReadOnlyMode = false;
  bool _periodsTransitioning = false;

  int? get currentSessionId => _currentSessionId;
  List<Map<String, dynamic>> get players => _players;
  List<Map<String, dynamic>> get sessions => _sessions;
  String? get currentSessionPassword => _currentSessionPassword;
  models.Session get session => _session;
  bool get isDarkTheme => _isDarkTheme;
  bool get isReadOnlyMode => _isReadOnlyMode;
  bool get periodsTransitioning => _periodsTransitioning;

  set session(models.Session newSession) {
    _session = newSession;
    notifyListeners();
  }

  Future<void> loadSessions() async {
    try {
      // Load sessions ONLY from Hive
      final hiveSessions = await HiveSessionDatabase.instance.getAllSessions();
      print('AppState: Loaded ${hiveSessions.length} sessions from Hive database');
      _sessions = hiveSessions;
      notifyListeners();
    } catch (e) {
      print('AppState: Error loading sessions from Hive: $e');
      // If error occurs, provide empty sessions list
      _sessions = [];
      notifyListeners();
    }
  }

  Future<void> createSession(String name) async {
    try {
      // Ensure name is not empty
      final sessionName = name.trim().isEmpty ? "New Session" : name.trim();
      print('AppState: Creating new session with name: "$sessionName"');
      
      // Store ONLY in Hive
      final sessionId = await HiveSessionDatabase.instance.insertSession(sessionName);
      
      _currentSessionId = sessionId;
      _currentSessionPassword = sessionName;
      
      // Clear players list
      _players = [];
      
      // Create new session model with default settings
      _session = models.Session(
        sessionName: sessionName,
        enableMatchDuration: false,
        matchDuration: 90 * 60,
        matchSegments: 2,
        enableTargetDuration: false,
        targetPlayDuration: 16 * 60,
        enableSound: false,
        enableVibration: true,
      );
      
      // Log new session creation
      logMatchEvent("New session '$sessionName' created");
      
      // Store session settings in Hive
      await saveSession();
      
      // Reload sessions list to include the new one
      await loadSessions();
      
      notifyListeners();
    } catch (e) {
      print('AppState: Error creating session: $e');
      throw Exception('Could not create session: $e');
    }
  }

  Future<void> loadSession(int sessionId) async {
    print('AppState.loadSession called with sessionId: $sessionId');
    
    if (sessionId <= 0) {
      print('Invalid session ID: $sessionId');
      throw Exception('Invalid session ID');
    }
    
    try {
      // Ensure database is initialized
      await HiveSessionDatabase.instance.init();
      
      // CRITICAL STEP: First, get the exact session name from the database
      final sessionData = await HiveSessionDatabase.instance.getSession(sessionId);
      if (sessionData == null) {
        print('Session not found in database: $sessionId');
        throw Exception('Session not found');
      }
      
      final correctSessionName = sessionData['name'] ?? '';
      print('Found session name from direct lookup: "$correctSessionName"');
      
      // Now set the current session ID and load players
      _currentSessionId = sessionId;
      _players = await HiveSessionDatabase.instance.getPlayersForSession(sessionId);
      print('Loaded ${_players.length} players for session');
      _players.sort((a, b) => a['name'].compareTo(b['name']));
      
      // CRITICAL: Set the current session password to the correct name
      _currentSessionPassword = correctSessionName;
      print('Set currentSessionPassword to: "$_currentSessionPassword"');
      
      // Create the session with the correct name
      _session = models.Session(sessionName: correctSessionName);
      print('Created new Session with sessionName: "${_session.sessionName}"');
      
      // Load session settings if they exist
      try {
        final settings = await HiveSessionDatabase.instance.getSessionSettings(sessionId);
        print('Session settings: ${settings != null ? 'Found' : 'Not found'}');
        if (settings != null) {
          // Create a new session with settings but preserve the correct name
          _session = models.Session(
            sessionName: correctSessionName,  // Make sure we keep the session name
            enableMatchDuration: settings['enableMatchDuration'] ?? false,
            matchDuration: settings['matchDuration'] ?? (90 * 60),
            matchSegments: settings['matchSegments'] ?? 2,
            enableTargetDuration: settings['enableTargetDuration'] ?? false,
            targetPlayDuration: settings['targetPlayDuration'] ?? (16 * 60),
            enableSound: settings['enableSound'] ?? false,
            enableVibration: settings.containsKey('enableVibration') ? settings['enableVibration'] : true,
            matchRunning: settings['matchRunning'] ?? false,
          );
          print('Loaded session settings with name: "${_session.sessionName}"');
        }
      } catch (e) {
        print('Error loading session settings, using defaults: $e');
        // Continue with default settings if we can't load settings
      }
      
      // Initialize players from database
      try {
        print('Initializing ${_players.length} players from database');
        for (var player in _players) {
          final playerName = player['name'] as String;
          _session.addPlayer(playerName);
          _session.updatePlayerTime(playerName, player['timer_seconds'] ?? 0);
          print('Added player: $playerName');
        }
      } catch (e) {
        print('Error initializing players: $e');
        // Continue with the session even if player initialization fails
      }
      
      print('Session loaded successfully, currentSessionId: $_currentSessionId');
      print('Final session name in AppState: "${_session.sessionName}"');
      print('Final currentSessionPassword: "$_currentSessionPassword"');
      
      _isReadOnlyMode = false;
      notifyListeners();

      // CRITICAL FIX: Reset player times after loading a session
      for (var player in _session.players.values) {
        player.totalTime = 0;
        player.lastActiveMatchTime = null; // Ensure last active time is cleared
        // player.active = false; // Optionally deactivate all players on load?
      }
      print('  Player times reset for loaded session.');

    } catch (e) {
      print('Error during session load: $e');
      _currentSessionId = null;
      _currentSessionPassword = null;
      _isReadOnlyMode = false;
      throw e;  // Re-throw to allow proper error handling
    }
  }

  Future<void> updatePlayerTimer(int playerId, int timerSeconds) async {
    if (_currentSessionId != null) {
      try {
        await HiveSessionDatabase.instance.updatePlayerTimer(playerId, timerSeconds);
        _players = await HiveSessionDatabase.instance.getPlayersForSession(_currentSessionId!);
      
        final playerIndex = _players.indexWhere((p) => p['id'] == playerId);
        if (playerIndex != -1) {
          final playerName = _players[playerIndex]['name'];
          _session.updatePlayerTime(playerName, timerSeconds);
        }
      } catch (e) {
        print('Error updating player timer in Hive: $e');
      }
    }
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkTheme = !_isDarkTheme;
    notifyListeners();
  }

  Future<void> addPlayer(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    
    print('Attempting to add player: $trimmedName');
    
    // Check if player already exists (case insensitive)
    final playerExists = _session.players.keys.any(
      (key) => key.toLowerCase() == trimmedName.toLowerCase()
    );
    
    // Early exit if player already exists
    if (playerExists) {
      print('Player already exists: $trimmedName');
      return;
    }
    
    try {
      // Bail out if we don't have a current session
      if (_currentSessionId == null) {
        print('Cannot add player: No active session');
        return;
      }
      
      // Ensure database is initialized
      await HiveSessionDatabase.instance.init();
      
      // Add to the session model first
      _session.addPlayer(trimmedName);
      print('Added player to session model: $trimmedName');
      
      // Store in Hive database
      final playerId = await HiveSessionDatabase.instance.insertPlayer(
        _currentSessionId!,
        trimmedName,
        0,
      );
      print('Added player to database with ID: $playerId');
      
      // Create player object for UI list
      final newPlayer = {
        'id': playerId,
        'name': trimmedName,
        'timer_seconds': 0,
        'session_id': _currentSessionId!,
      };
      
      // Safely add to the players list
      _players = List<Map<String, dynamic>>.from(_players)..add(newPlayer);
      
      // Sort alphabetically
      _players.sort((a, b) => a['name'].compareTo(b['name']));
      
      // Log player addition
      logMatchEvent("$trimmedName added to roster");
      
      // Save session changes
      await saveSession();
      print('Successfully added player: $trimmedName');
    } catch (e) {
      print('Error adding player: $e');
      // Remove from session model if database operation failed
      _session.players.remove(trimmedName);
      throw Exception('Could not add player: $e');
    }
    
    // Notify listeners to update UI
    notifyListeners();
  }
  
  Future<void> toggleMatchDuration(bool value) async {
    _session.enableMatchDuration = value;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> updateMatchDuration(int minutes) async {
    _session.matchDuration = minutes * 60;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> updateMatchSegments(int segments) async {
    _session.matchSegments = segments;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> toggleTargetDuration(bool value) async {
    _session.enableTargetDuration = value;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> updateTargetDuration(int minutes) async {
    _session.targetPlayDuration = minutes * 60;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> toggleSound(bool value) async {
    _session.enableSound = value;
    await saveSession();
    notifyListeners();
  }
  
  Future<void> toggleVibration() async {
    final hasVibrator = await Vibration.hasVibrator() || false;
    if (hasVibrator) {
      _session = _session.copyWith(enableVibration: !_session.enableVibration);
      notifyListeners();
      
      // Fix the error by passing session properties to updateSettings
      await HiveSessionDatabase.instance.saveSessionSettings(_currentSessionId!, {
        'enableMatchDuration': _session.enableMatchDuration,
        'matchDuration': _session.matchDuration,
        'matchSegments': _session.matchSegments,
        'enableTargetDuration': _session.enableTargetDuration,
        'targetPlayDuration': _session.targetPlayDuration,
        'enableSound': _session.enableSound,
        'enableVibration': _session.enableVibration,
        'matchRunning': _session.matchRunning,
      });
    }
  }
  
  // Toggle player active state with proper logging
  Future<void> togglePlayer(String name) async {
    if (_session.players.containsKey(name)) {
      final player = _session.players[name]!;
      final currentMatchTime = _session.matchTime;
      
      // Determine the true current state, considering activeBeforePause
      final wasActive = _session.isPaused ? 
        _session.activeBeforePause.contains(name) : 
        player.active;
      
      // If player is currently active and not in setup mode, calculate their elapsed time before deactivating
      if (wasActive && !_session.isSetup && player.lastActiveMatchTime != null) {
        player.totalTime += currentMatchTime - player.lastActiveMatchTime!;
        player.lastActiveMatchTime = null;
      }
      
      // Toggle the player's state based on the true current state
      final shouldBeActive = !wasActive;
      player.active = shouldBeActive;
      
      // Handle paused state management
      if (_session.isPaused) {
        if (shouldBeActive) {
          // Add to activeBeforePause if not already there
          if (!_session.activeBeforePause.contains(name)) {
            _session.activeBeforePause.add(name);
          }
        } else {
          // Remove from activeBeforePause
          _session.activeBeforePause.remove(name);
        }
      } else if (shouldBeActive && !_session.isSetup) {
        // If activating during match, just record current match time as start point
        player.lastActiveMatchTime = currentMatchTime;
        // Don't reset totalTime - it accumulates across active periods
        _session.matchRunning = true;
      }
      
      // Log the event based on the new state (only if not in setup mode)
      if (!_session.isSetup) {
        if (shouldBeActive) {
          logMatchEvent("$name ${TranslationService().get('match.entered_game')}", entryType: 'player_enter');
        } else {
          logMatchEvent("$name ${TranslationService().get('match.left_game')}", entryType: 'player_exit');
        }
      }
      
      await saveSession();
      notifyListeners();
    }
  }
  
  // Helper method to calculate player time
  int calculatePlayerTime(Player player) {
    if (!player.active || _session.isPaused) {
      return player.totalTime;
    }
    
    // For active players, add current active duration to total time
    if (player.lastActiveMatchTime != null) {
      return player.totalTime + (_session.matchTime - player.lastActiveMatchTime!);
    }
    
    return player.totalTime;
  }
  
  Future<void> saveSession() async {
    if (_currentSessionId == null) return;
    
    try {
      // Update player times in Hive database
      for (var playerName in _session.players.keys) {
        final playerIndex = _players.indexWhere((p) => p['name'] == playerName);
        final playerTime = _session.players[playerName]!.totalTime;
        
        if (playerIndex != -1) {
          final playerId = _players[playerIndex]['id'] as int;
          await HiveSessionDatabase.instance.updatePlayerTimer(playerId, playerTime);
          
          // Update local list
          _players[playerIndex]['timer_seconds'] = playerTime;
        }
      }
      
      // Save session settings to Hive
      await HiveSessionDatabase.instance.saveSessionSettings(_currentSessionId!, {
        'enableMatchDuration': _session.enableMatchDuration,
        'matchDuration': _session.matchDuration,
        'matchSegments': _session.matchSegments,
        'enableTargetDuration': _session.enableTargetDuration,
        'targetPlayDuration': _session.targetPlayDuration,
        'enableSound': _session.enableSound,
        'enableVibration': _session.enableVibration,
        'matchRunning': _session.matchRunning,
      });
    } catch (e) {
      print('Error saving to Hive database: $e');
    }
    
    // No need to notify listeners here as the caller should do it if needed
  }

  Future<void> setCurrentSession(int sessionId) async {
    try {
      _currentSessionId = sessionId;
      
      _players = await HiveSessionDatabase.instance.getPlayersForSession(sessionId);
      _players.sort((a, b) => a['name'].compareTo(b['name']));
      
      // Get session directly from database to ensure we have the correct name
      final sessionData = await HiveSessionDatabase.instance.getSession(sessionId);
      if (sessionData == null) {
        print('Session not found: $sessionId');
        throw Exception('Session not found');
      }
      
      final sessionName = sessionData['name'] ?? '';
      print('Loaded session name: "$sessionName"');
      _currentSessionPassword = sessionName;
      
      // Initialize session with correct name and default settings
      _session = models.Session(
        sessionName: sessionName,
        enableMatchDuration: false,
        matchDuration: 90 * 60,
        matchSegments: 2,
        enableTargetDuration: false,
        targetPlayDuration: 16 * 60,
        enableSound: false,
        enableVibration: true, // Enable vibration by default
      );
      
      // Load session settings from Hive
      final settings = await HiveSessionDatabase.instance.getSessionSettings(sessionId);
      if (settings != null) {
        _session = models.Session(
          sessionName: sessionName, // Make sure we preserve the correct name
          enableMatchDuration: settings['enableMatchDuration'] ?? false,
          matchDuration: settings['matchDuration'] ?? (90 * 60),
          matchSegments: settings['matchSegments'] ?? 2,
          enableTargetDuration: settings['enableTargetDuration'] ?? false,
          targetPlayDuration: settings['targetPlayDuration'] ?? (16 * 60),
          enableSound: settings['enableSound'] ?? false,
          enableVibration: settings.containsKey('enableVibration') ? settings['enableVibration'] : true, // Respect existing setting
        );
      }
      
      // Initialize players
      for (var player in _players) {
        final name = player['name'];
        // Always set player times to zero when loading a session to ensure consistency
        _session.players[name] = Player(name: name, totalTime: 0);
      }
      
      // Match time is also reset to zero for consistency
      _session.matchTime = 0;
      
      // Log session loading
      logMatchEvent("Session '$sessionName' loaded with all times reset to zero");
      
      print('Session loaded with name: "${_session.sessionName}", ID: $sessionId');
      notifyListeners();
    } catch (e) {
      print('AppState: Error loading session: $e');
      throw Exception('Could not load session: $e');
    }
  }

  Future<void> resetAllPlayers() async {
    // Reset player states in the session model
    _session.resetAllPlayers();
    
    // If in read-only mode, just update the UI without trying to persist changes
    if (_isReadOnlyMode) {
      print('In read-only mode, resetting all players without persisting to database');
      notifyListeners();
      return;
    }
    
    // If we're not in read-only mode, try to update the database
    try {
      // Update all player timers in Hive database
      if (_currentSessionId != null) {
        for (final entry in _session.players.entries) {
          // Find player ID from the players list
          final playerIndex = _players.indexWhere((p) => p['name'] == entry.key);
          if (playerIndex != -1) {
            final playerId = _players[playerIndex]['id'] as int;
            await HiveSessionDatabase.instance.updatePlayerTimer(playerId, entry.value.totalTime);
            
            // Update local list
            _players[playerIndex]['timer_seconds'] = 0;
          }
        }
      }
    } catch (e) {
      print('Error resetting players in Hive: $e');
    }
    
    notifyListeners();
  }

  Future<void> resetSession() async {
    // Reset all session state
    _session.resetSessionState();
    
    // Ensure period-related flags are properly reset
    _session.currentPeriod = 1;
    _session.hasWhistlePlayed = false;
    _session.isMatchComplete = false;
    _session.matchRunning = false;
    _session.isPaused = false;
    _periodsTransitioning = false;
    
    // Notify background service that match has been stopped/reset
    BackgroundService().onMatchStop();
    
    // Save the reset state
    await saveSession();
    
    // Notify listeners of the reset
    notifyListeners();
  }

  Future<void> endPeriod() async {
    print("endPeriod called - current period: ${_session.currentPeriod}");
    
    // Only proceed if match duration is enabled
    if (!_session.enableMatchDuration) return;
    
    // Guard against multiple calls
    if (_session.hasWhistlePlayed) {
      print("Period end already processed (whistle played)");
      return;
    }
    
    // Calculate period information
    final isFinalPeriod = _session.currentPeriod == _session.matchSegments;
    final periodDuration = _session.matchDuration ~/ _session.matchSegments;
    final exactPeriodEndTime = periodDuration * _session.currentPeriod;
    
    // If we're in the final period and this is also the match end time, end the match
    if (isFinalPeriod && exactPeriodEndTime == _session.matchDuration) {
      print("Final period has ended, ending match instead");
      
      // Set the match time exactly to match duration for consistency
      _session.matchTime = _session.matchDuration;
      
      // End the match instead of just the period
      endMatch();
      
      // Save session state
      await saveSession();
      
      // Notify listeners
      notifyListeners();
      return;
    }
    
    // Mark that the whistle has played
    _session.hasWhistlePlayed = true;

    // Set the match time to exactly the end time of the current period for accuracy
    _session.matchTime = exactPeriodEndTime; 
    print("Set match time EXACTLY to period end time: ${_session.matchTime}");

    // *** Force UI update for the exact time FIRST ***
    notifyListeners(); 
    // Short delay to allow UI thread to potentially process the time update
    await Future.delayed(Duration(milliseconds: 50)); 

    // Pause the match (if running) AFTER setting the final time
    if (_session.matchRunning) {
      // Pass the exact end time to pauseMatch if it needs it
      await pauseMatch(exactEndTime: exactPeriodEndTime); 
    }
    
    // We no longer log the period end event - only log period starts
    print("Period ${_session.currentPeriod} ended at match time ${_session.matchTime}");
    
    // Flag that we're in a period transition (if not at match end)
    // Do this *after* the initial time update notification
    if (_session.currentPeriod < _session.matchSegments) {
      _periodsTransitioning = true;
      print("Set periodsTransitioning to true for period ${_session.currentPeriod}");
    }
    
    // Save the session state AFTER all state changes are done
    await saveSession();
    
    // Log state just before final notification
    print("State before final notify in endPeriod: periodsTransitioning=$_periodsTransitioning, matchTime=${_session.matchTime}");
    
    // *** Final notification to trigger dialog logic (if needed) ***
    // This ensures the UI has already received the exact time update
    notifyListeners(); 
  }

  Future<void> startNextPeriod() async {
    print("startNextPeriod called - from period: ${_session.currentPeriod}");
    
    // Turn off periods transitioning flag
    _periodsTransitioning = false;
    
    // Make sure we're starting from the exact period end time
    // Calculate the exact end time of the current period
    final periodDuration = _session.matchDuration ~/ _session.matchSegments;
    final exactCurrentPeriodEndTime = periodDuration * _session.currentPeriod;
    
    // If the match time is not exactly at the period end (off by 1 second),
    // adjust it to ensure we start the next period from the correct time point
    if (_session.matchTime != exactCurrentPeriodEndTime) {
      print("Adjusting match time from ${_session.matchTime} to exact period end time: $exactCurrentPeriodEndTime");
      _session.matchTime = exactCurrentPeriodEndTime;
    }
    
    // Increment to the next period
    _session.currentPeriod++;
    
    // Reset the whistle played flag for the new period
    _session.hasWhistlePlayed = false;
    
    // Log the start of the new period
    final periodName = _session.matchSegments == 2 ? 'Half' : 'Quarter';
    final ordinal = getOrdinal(_session.currentPeriod);
    logMatchEvent("Start of $ordinal $periodName", entryType: 'period_transition');
    
    // Ensure proper match state regardless of which period we're entering
    // These settings should apply to ALL periods including the final one
    _session.matchRunning = true;
    _session.isPaused = false;
    
    // Print detailed state information
    print("Starting period ${_session.currentPeriod}/${_session.matchSegments}");
    print("Match state - running: ${_session.matchRunning}, paused: ${_session.isPaused}");
    
    // Reset the active players list
    for (var playerName in _session.activeBeforePause) {
      if (_session.players.containsKey(playerName)) {
        final player = _session.players[playerName]!;
        player.active = true;
        player.lastActiveMatchTime = _session.matchTime;
        print("Reactivated player: $playerName at time: ${player.lastActiveMatchTime}");
      }
    }
    
    // Clear the active before pause list
    _session.activeBeforePause = [];
    
    // Set lastUpdateTime to prevent time jumps
    _session.lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    print("Started period ${_session.currentPeriod} at match time ${_session.matchTime}");
    
    // Save the session state
    await saveSession();
    
    // Force a UI update
    notifyListeners();
  }

  // Helper for ordinal suffixes (st, nd, rd, th)
  String getOrdinalSuffix(int number) {
    if (number % 10 == 1 && number % 100 != 11) return "st";
    if (number % 10 == 2 && number % 100 != 12) return "nd";
    if (number % 10 == 3 && number % 100 != 13) return "rd";
    return "th";
  }
  
  void pauseAll() {
    // This is a proxy to the pauseAll function in MainScreen
    // In this implementation, we just update the session state
    _session.isPaused = !_session.isPaused;
    
    if (_session.isPaused) {
      // Store active players and deactivate them
      _session.activeBeforePause = [];
      final currentMatchTime = _session.matchTime;
      
      for (var playerName in _session.players.keys) {
        final player = _session.players[playerName]!;
        if (player.active) {
          // Calculate elapsed time for active players
          if (player.lastActiveMatchTime != null) {
            player.totalTime += currentMatchTime - player.lastActiveMatchTime!;
          }
          // Reset last active time and deactivate
          player.lastActiveMatchTime = null;
          player.active = false;
          // Only add to activeBeforePause if successfully deactivated
          if (!player.active) {
            _session.activeBeforePause.add(playerName);
          }
        }
      }
    } else {
      // Reactivate players that were active before pause
      final currentMatchTime = _session.matchTime;
      final playersToReactivate = List<String>.from(_session.activeBeforePause);
      _session.activeBeforePause = [];  // Clear list first
      
      for (var playerName in playersToReactivate) {
        if (_session.players.containsKey(playerName)) {
          final player = _session.players[playerName]!;
          player.active = true;
          player.lastActiveMatchTime = currentMatchTime;
          // Only add back to activeBeforePause if activation failed
          if (!player.active) {
            _session.activeBeforePause.add(playerName);
          }
        }
      }
    }
    
    saveSession();
    notifyListeners();
  }

  // Store active players and handle state changes for period transitions
  void storeActivePlayersForPeriodChange() {
    _session.activeBeforePause.clear();
    final currentMatchTime = _session.matchTime;
    
    for (var playerName in _session.players.keys) {
      final player = _session.players[playerName]!;
      if (player.active) {
        _session.activeBeforePause.add(playerName);
        if (player.lastActiveMatchTime != null) {
          player.totalTime += currentMatchTime - player.lastActiveMatchTime!;
        }
        player.lastActiveMatchTime = null;
        player.active = false;
      }
    }
  }

  // Rename a player
  Future<void> renamePlayer(String oldName, String newName) async {
    if (_currentSessionId == null) return;
    
    final trimmedNewName = newName.trim();
    if (!_session.players.containsKey(oldName) || trimmedNewName.isEmpty) return;
    
    // Don't rename if new name already exists
    if (_session.players.containsKey(trimmedNewName)) return;
    
    // Get the player data
    final player = _session.players[oldName]!;
    
    // Create a new player with the new name but same data
    _session.players[trimmedNewName] = Player(
      name: trimmedNewName,
      totalTime: player.totalTime,
      active: player.active,
      lastActiveMatchTime: player.lastActiveMatchTime,
    );
    
    // Remove the old player
    _session.players.remove(oldName);
    
    // Update the database
    if (_currentSessionId != null) {
      final playerIndex = _players.indexWhere((p) => p['name'] == oldName);
      if (playerIndex != -1) {
        // Use the player's ID to update the name
        final playerId = _players[playerIndex]['id'] as int;
        // We should have a renamePlayer method in database, but for now
        // just update the local list
        _players[playerIndex]['name'] = trimmedNewName;
      }
    }
    
    notifyListeners();
  }

  // Add missing resetPlayerTime method
  Future<void> resetPlayerTime(String playerName) async {
    if (_session.players.containsKey(playerName)) {
      final player = _session.players[playerName]!;
      player.totalTime = 0;
      player.active = false;
      player.lastActiveMatchTime = null;
      await saveSession();
      notifyListeners();
    }
  }
  
  Future<void> removePlayer(String name) async {
    if (_session.players.containsKey(name)) {
      // Remove from session
      _session.players.remove(name);
      
      // Log player removal
      logMatchEvent("$name removed from roster");
      
      // Remove from DB if needed
      if (_currentSessionId != null) {
        final playerIndex = _players.indexWhere((p) => p['name'] == name);
        if (playerIndex != -1) {
          final id = _players[playerIndex]['id'];
          
          // Delete from Hive database
          try {
            await HiveSessionDatabase.instance.deletePlayer(id);
            print('Deleted player $name (ID: $id) from database');
          } catch (e) {
            print('Error deleting player from database: $e');
          }
          
          // Also remove from our local list
          _players.removeAt(playerIndex);
        }
      } else {
        _players.removeWhere((p) => p['name'] == name);
      }
      
      // Save the session to make changes persistent
      saveSession();
      
      notifyListeners();
    }
  }

  void clearCurrentSession() {
    _currentSessionId = null;
    _currentSessionPassword = null;
    _players = [];
    _session = models.Session(); // Reset to a new blank session
    notifyListeners();
  }

  Future<void> togglePlayerActive(String name) async {
    // Get the current active state before toggling
    final wasActive = _session.players[name]?.active ?? false;
    
    // Toggle the player's active state in the session model
    _session.togglePlayerActive(name);
    
    // Get the new active state
    final isActive = _session.players[name]?.active ?? false;
    
    // Log player entry/exit
    if (isActive && !wasActive) {
      final enteredGame = TranslationService().get('match.entered_game');
      logMatchEvent("$name $enteredGame");
    } else if (!isActive && wasActive) {
      final leftGame = TranslationService().get('match.left_game');
      logMatchEvent("$name $leftGame");
    }
    
    // If in read-only mode, just update the UI without trying to persist changes
    if (_isReadOnlyMode) {
      print('In read-only mode, toggling player $name without persisting to database');
      notifyListeners();
      return;
    }
    
    // If we're not in read-only mode, try to update the database
    try {
      // Update player timer in Hive database
      if (_currentSessionId != null) {
        final player = _session.players[name];
        if (player != null) {
          // Find player ID from the players list
          final playerIndex = _players.indexWhere((p) => p['name'] == name);
          if (playerIndex != -1) {
            final playerId = _players[playerIndex]['id'] as int;
            await HiveSessionDatabase.instance.updatePlayerTimer(playerId, player.totalTime);
          }
        }
      }
    } catch (e) {
      print('Error updating player active state in Hive: $e');
    }
    
    notifyListeners();
  }

  // Reset the session state with proper logging
  Future<void> resetSessionState() async {
    // Reset all match state flags
    _session.matchTime = 0;
    _session.currentPeriod = 1;
    _session.hasWhistlePlayed = false;
    _session.matchRunning = false;
    _session.isPaused = false;
    
    // Notify background service that match has been stopped/reset
    BackgroundService().onMatchStop();
    _session.isMatchComplete = false;
    _session.isSetup = true;  // Reset to setup mode
    _session.activeBeforePause = [];
    
    // Clear the match log
    _session.clearMatchLog();
    
    // Reset all player states but keep them active/inactive as they were
    final activeStates = Map<String, bool>.fromEntries(
      _session.players.entries.map((e) => MapEntry(e.key, e.value.active))
    );
    
    for (var playerName in _session.players.keys) {
      final player = _session.players[playerName]!;
      player.totalTime = 0;
      player.lastActiveMatchTime = null;
      // Preserve active state in setup mode
      player.active = activeStates[playerName] ?? false;
    }
    
    // If in read-only mode, just update the UI without trying to persist changes
    if (_isReadOnlyMode) {
      print('In read-only mode, resetting session state without persisting to database');
      notifyListeners();
      return;
    }
    
    // Save the reset state
    try {
      await saveSession();
    } catch (e) {
      print('Error resetting session in Hive: $e');
    }
    
    notifyListeners();
  }

  // Start a new match
  Future<void> startMatch() async {
    if (_session.isSetup) {
      // Transitioning from setup to active
      _session.isSetup = false;
      _session.matchRunning = true;
      _session.isPaused = false;
      
      // Notify background service that match has started
      BackgroundService().onMatchStart();
      
      // Log match start as the first entry
      _session.addMatchLogEntry('Match Started', entryType: 'match_start');
      
      // Set initial active times for any players that were toggled during setup
      final currentMatchTime = _session.matchTime;
      for (var playerName in _session.players.keys) {
        final player = _session.players[playerName]!;
        if (player.active) {
          player.lastActiveMatchTime = currentMatchTime;
          // Log each active player at match start
          final enteredGame = TranslationService().get('match.entered_game');
          _session.addMatchLogEntry("$playerName $enteredGame", entryType: 'player_entry');
        }
      }
      
      await saveSession();
      notifyListeners();
    } else if (!_session.matchRunning) {
      // Normal match start (after pause)
      _session.matchRunning = true;
      _session.isPaused = false;
      
      await saveSession();
      notifyListeners();
    }
  }

  Future<void> deleteSession(int sessionId) async {
    try {
      // First delete all history entries
      await HiveSessionDatabase.instance.deleteSessionHistory(sessionId);
      
      // Then delete the session itself
      await HiveSessionDatabase.instance.deleteSession(sessionId);
      
      // Reload the sessions list
      await loadSessions();
      
      // If the current session was deleted, clear it
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
        _currentSessionPassword = null;
        _session = models.Session();
        _players = [];
        notifyListeners();
      }
    } catch (e) {
      print('Error deleting session from Hive: $e');
      throw Exception('Could not delete session: $e');
    }
  }

  // Add an entry to the match log
  void logMatchEvent(String details, {String entryType = 'standard', int? timestamp}) {
    // Process the details to ensure all translation keys are resolved
    String processedDetails = details;
    
    // Special handling for match.match_ended to ensure it's replaced with Match Complete!
    if (details.contains('match.match_ended')) {
      processedDetails = details.replaceAll('match.match_ended', 'Match Complete!');
    }
    // Check if the details contain any unresolved translation keys
    else if (details.contains('match.')) {
      // If it's a direct translation key, resolve it
      if (details.startsWith('match.')) {
        processedDetails = TranslationService().get(details);
      } else {
        // For text containing translation keys like "2 entered the match.match"
        // Replace each occurrence of a translation key with its translated value
        final regex = RegExp(r'match\.[a-z_]+');
        processedDetails = details.replaceAllMapped(regex, (match) {
          return TranslationService().get(match.group(0)!);
        });
      }
    }
    
    // Add the timestamp to goal entries
    if (timestamp != null) {
      final timeStr = _formatTime(timestamp);
      processedDetails = '$processedDetails at $timeStr';
    }
    
    // Now add the processed details to the log with the custom timestamp if provided
    _session.addMatchLogEntry(
      processedDetails,
      entryType: entryType,
      customMatchTime: timestamp,
    );
    
    // Debug logging
    print("Adding match log entry: $processedDetails (type: $entryType)");
    
    // No need to save to database here - will be saved with other session changes
    notifyListeners();
  }

  // Export match log to a string for sharing
  String exportMatchLogToText() {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('MM/dd/yyyy h:mm a'); // US format with AM/PM
    
    // Add session name as header
    buffer.writeln('MATCH LOG: ${_session.sessionName}');
    
    // Find the match start entry to get the start time
    final matchStartEntry = _session.matchLog.firstWhere(
      (entry) => entry.entryType == 'match_start',
      orElse: () => MatchLogEntry(
        matchTime: '00:00',
        seconds: 0,
        timestamp: DateTime.now().toIso8601String(),
        details: 'Match Started',
        entryType: 'match_start'
      ),
    );
    
    // Parse the timestamp and format it
    final startTime = DateTime.parse(matchStartEntry.timestamp);
    buffer.writeln(dateFormat.format(startTime)); // Use match start time
    buffer.writeln('----------------------------------------');
    
    // Add current score
    buffer.writeln('SCORE: ${_session.teamGoals} - ${_session.opponentGoals}');
    buffer.writeln('----------------------------------------');
    buffer.writeln();
    
    // Add log entries in chronological order (oldest first)
    final entries = _session.getSortedMatchLogAscending();
    
    for (var entry in entries) {
      // Format: [Time] Event details
      if (entry.entryType?.toLowerCase() == 'period_transition') {
        // Simple emphasis for period transitions
        buffer.writeln('[${entry.matchTime}] * ${entry.details} *');
      } else {
        buffer.writeln('[${entry.matchTime}] ${entry.details}');
      }
    }
    
    return buffer.toString();
  }

  // Modified version of existing methods that add logging
  
  // Log match pause/resume
  Future<void> toggleMatchRunning() async {
    if (_session.matchRunning) {
      // If running, pause the match
      await pauseMatch();
    } else {
      // If paused, resume or start the match
      _session.matchRunning = true;
      _session.isPaused = false;
      
      // Notify background service that match has been resumed
      BackgroundService().onMatchResume();
      
      // Reactivate players that were active before pause
      final currentMatchTime = _session.matchTime;
      for (var playerName in _session.activeBeforePause) {
        if (_session.players.containsKey(playerName)) {
          final player = _session.players[playerName]!;
          player.active = true;
          player.lastActiveMatchTime = currentMatchTime;
        }
      }
      
      // Clear the active before pause list
      _session.activeBeforePause = [];

      // Check if this is the first start (match time is 0)
      if (_session.matchTime == 0) {
        logMatchEvent(TranslationService().get('match.match_started'), entryType: 'match_start');
      } else {
        logMatchEvent(TranslationService().get('match.match_resumed'));
      }
      
      await saveSession();
      notifyListeners();
    }
  }
  
  // Helper for ordinal numbers (1st, 2nd, 3rd, etc.)
  String getOrdinal(int number) {
    if (number == 1) return '1st';
    if (number == 2) return '2nd';
    if (number == 3) return '3rd';
    return '${number}th';
  }
  
  // Update match time and check for period changes
  void updateMatchTimer({int? elapsedSeconds, double? elapsedMillis}) {
    if (session.matchRunning && !session.isPaused) {
      final oldMatchTime = session.matchTime;
      double deltaSeconds = 0;

      if (elapsedSeconds != null) {
        deltaSeconds = elapsedSeconds.toDouble();
      } else if (elapsedMillis != null) {
        deltaSeconds = elapsedMillis / 1000.0;
      } else {
         // Default to 1 second if no specific elapsed time provided
         deltaSeconds = 1.0;
      }

      if (deltaSeconds <= 0) return; // Don't process zero or negative delta

      // Calculate new match time
      final newMatchTime = oldMatchTime + deltaSeconds.round();
      session.matchTime = newMatchTime;

      // Update active players
      for (var playerName in session.players.keys) {
        final player = session.players[playerName]!;
        if (player.active && player.lastActiveMatchTime != null) {
          // Calculate exact time since last update for this player
          final timeToAdd = newMatchTime - player.lastActiveMatchTime!;
          if (timeToAdd > 0) {
            player.totalTime += timeToAdd;
            player.lastActiveMatchTime = newMatchTime;
          }
        }
      }

      // Only notify if time actually changed
      if (session.matchTime != oldMatchTime) {
        notifyListeners();
      }
    }
  }

  // Pause when all players are inactive
  Future<void> checkForAutoPause() async {
    // No longer auto-pause when all players are inactive
    // Match will continue running until explicitly paused or reset

    // *** However, we should still update the timestamp if the timer is running ***
    // This prevents large jumps if the app is backgrounded/resumed without state changes
    if (session.matchRunning && !session.isPaused) {
       final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
       session.lastUpdateTime = now;
    }
    return;
  }

  void verifyActiveSwitch(String name) {
    if (session.players.containsKey(name)) {
      final player = session.players[name]!;
      if (player.active) {
        // Log the player entering - use the fully translated string
        final enteredGame = TranslationService().get('match.entered_game');
        logMatchEvent("$name $enteredGame");
      } else {
        // Log the player leaving - use the fully translated string
        final leftGame = TranslationService().get('match.left_game');
        logMatchEvent("$name $leftGame");
      }
    }
  }

  Future<void> pauseMatch({int? exactEndTime}) async {
    print('pauseMatch called');
    // Use exactEndTime if provided, otherwise use current session time
    final timeToUse = exactEndTime ?? session.matchTime;

    // Check if already paused or not running
    if (!session.matchRunning || session.isPaused) {
        print('Match is already paused or not running. Current state: running=${session.matchRunning}, paused=${session.isPaused}');
        // Ensure state is consistent if called redundantly
        session.matchRunning = false;
        session.isPaused = true;
        // Update timestamp even if paused redundantly
        session.lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return;
    }

    session.matchRunning = false;
    session.isPaused = true;
    // Update timestamp when pausing
    session.lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Notify background service that match has been paused
    BackgroundService().onMatchPause();


    // Store currently active players for resuming later
    session.activeBeforePause = [];

    // Calculate final times for all players using the determined time
    final currentMatchTime = timeToUse;

    for (var playerName in session.players.keys) {
      final player = session.players[playerName]!;

      if (player.active) {
        // Store active players for resuming later
        session.activeBeforePause.add(playerName);

        // Calculate elapsed time since last activation
        if (player.lastActiveMatchTime != null) {
          // Ensure we don't calculate negative time if lastActiveMatchTime > currentMatchTime
          final timeToAdd = currentMatchTime - player.lastActiveMatchTime!;
          if (timeToAdd > 0) {
              player.totalTime += timeToAdd;
          } else if (timeToAdd < 0) {
              print("Warning: Negative timeToAdd ($timeToAdd) for player $playerName during pause. TimeToUse=$timeToUse, LastActive=$player.lastActiveMatchTime");
          }
        }

        // Reset last active time and deactivate
        player.lastActiveMatchTime = null;
        player.active = false;
      }
    }

    // Don't log match paused event if we're doing a period transition
    // Check if this is a period end pause or a regular pause
    if (!session.hasWhistlePlayed) {
      logMatchEvent(TranslationService().get('match.match_paused'));
    }
  }

  // Update match time with a specific value (used by UI timer)
  void updateMatchTime(int newMatchTime) {
    if (session.matchTime != newMatchTime) {
      final timeDiff = newMatchTime - session.matchTime;
      session.matchTime = newMatchTime;
      
      // Update active player times
      if (timeDiff > 0 && !session.isPaused) {
        for (var playerName in session.players.keys) {
          final player = session.players[playerName]!;
          if (player.active && player.lastActiveMatchTime != null) {
            // Calculate exact time since last update for this player
            final timeToAdd = newMatchTime - player.lastActiveMatchTime!;
            if (timeToAdd > 0) {
              player.totalTime += timeToAdd;
              player.lastActiveMatchTime = newMatchTime;
            }
          }
        }
      }
      
      notifyListeners();
    }
  }

  bool shouldEndPeriod() {
    if (!session.enableMatchDuration) return false;
    
    // Calculate period duration
    final periodDuration = session.matchDuration ~/ session.matchSegments;
    
    // Calculate END time for the CURRENT period
    final currentPeriodEndTime = periodDuration * session.currentPeriod;
    
    // Period ends when we reach or exceed the end time for current period
    // and the whistle hasn't played yet
    final shouldEnd = session.matchTime >= currentPeriodEndTime && !session.hasWhistlePlayed;
    
    return shouldEnd;
  }

  // Add goal for a player
  Future<void> addPlayerGoal(String playerName, {int? timestamp}) async {
    if (session.players.containsKey(playerName)) {
      session.players[playerName]!.goals++;
      session.teamGoals++;
      
      // Log the goal with timestamp if provided
      logMatchEvent('Goal scored by $playerName', timestamp: timestamp);
      
      notifyListeners();
      await saveSession();
    }
  }

  // Add goal for opponent team
  Future<void> addOpponentGoal({int? timestamp}) async {
    session.opponentGoals++;
    
    // Log the goal with timestamp if provided
    logMatchEvent('Opponent goal', timestamp: timestamp);
    
    notifyListeners();
    await saveSession();
  }

  // Helper method to format time
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Get current score as a formatted string
  String getScoreDisplay() {
    return "${session.sessionName}: ${session.teamGoals} - Opp: ${session.opponentGoals}";
  }

  // Add the missing endMatch method definition correctly
  Future<void> endMatch() async {
    if (_session.isMatchComplete) return; // Already ended
    
    // Set match time to exactly match the match duration for consistency
    if (_session.enableMatchDuration) {
      _session.matchTime = _session.matchDuration;
    }
    
    // Stop the match
    _session.matchRunning = false;
    _session.isPaused = true;
    
    // Store currently active players and calculate final time
    _session.activeBeforePause = [];
    for (var playerName in _session.players.keys) {
      final player = _session.players[playerName]!;
      if (player.active) {
        _session.activeBeforePause.add(playerName);
        
        // Calculate final time for active players
        if (player.lastActiveMatchTime != null) {
          player.totalTime += (_session.matchTime - player.lastActiveMatchTime!);
        }
        
        // Reset active flags and last active time
        player.lastActiveMatchTime = null;
        player.active = false;
      }
    }
    
    // Mark the match as complete
    _session.isMatchComplete = true;
    
    // Get the final score
    final score = "${_session.teamGoals}-${_session.opponentGoals}";
    
    // Add match end entry to log
    logMatchEvent("${TranslationService().get('match.match_complete')} ($score)", entryType: 'match_end');
    
    // Set match end logged flag to true
    _session.matchEndLogged = true;
    
    // Save session state
    await saveSession();
    
    // Save to history
    await saveCurrentSessionToHistory();
    
    notifyListeners();
  }

  // Add the missing shouldEndMatch method definition correctly
  bool shouldEndMatch() {
    if (!session.enableMatchDuration) return false;
    
    // Match should end if time reaches duration AND we are in the final period
    final isFinalPeriod = session.currentPeriod == session.matchSegments;
    final shouldEnd = isFinalPeriod && session.matchTime >= session.matchDuration && !session.isMatchComplete;
    
    return shouldEnd;
  }

  // New method specifically for background sync adjustment
  void updatePlayerTimesForBackgroundSync(int elapsedInBackgroundSeconds) {
    if (elapsedInBackgroundSeconds <= 0) return;

    bool changed = false;
    
    // Calculate new match time
    final newMatchTime = session.matchTime + elapsedInBackgroundSeconds;
    
    for (var playerName in session.players.keys) {
      final player = session.players[playerName]!;
      // Update players who were marked as active *before* the app went to background
      // OR who are currently marked active (if sync happens before UI fully restores state)
      if ((player.active || session.activeBeforePause.contains(playerName)) && player.lastActiveMatchTime != null) {
         final oldTime = player.totalTime;
         final timeToAdd = newMatchTime - player.lastActiveMatchTime!;
         if (timeToAdd > 0) {
           player.totalTime += timeToAdd;
           player.lastActiveMatchTime = newMatchTime;
           changed = true;
         }
      }
    }
    
    // Update match time after player times are updated
    session.matchTime = newMatchTime;
    
    if (changed) {
        notifyListeners(); // Notify if any player times were updated
    }
  }

  // New method to ensure match completion is properly logged
  void ensureMatchEndLogged() {
    // Only proceed if match is already marked as complete but not yet logged
    if (session.isMatchComplete && !session.matchEndLogged) {
      // Get the final score
      final score = "${session.teamGoals}-${session.opponentGoals}";
      
      // Log match end with proper translation and score
      logMatchEvent("${TranslationService().get('match.match_complete')} ($score)", entryType: 'match_end');
      
      // Mark that we've properly logged the match end
      session.matchEndLogged = true;
      
      // Save the session to persist the log entry
      saveSession();
      notifyListeners();
    }
  }

  // Add these methods for session history
  
  // Save the current session to history
  Future<bool> saveCurrentSessionToHistory() async {
    try {
      if (_currentSessionId == null) {
        print('Cannot save to history: No current session');
        return false;
      }
      
      // First save the current session state
      await saveSession();
      
      // Get the current session data
      final sessionData = await HiveSessionDatabase.instance.getSession(_currentSessionId!);
      if (sessionData == null) {
        print('Cannot save to history: Failed to retrieve session data');
        return false;
      }
      
      // Convert session object fields to maps for storage
      final Map<String, dynamic> enhancedSessionData = Map.from(sessionData);
      
      // Add players data
      final Map<String, dynamic> playersMap = {};
      _session.players.forEach((name, player) {
        playersMap[name] = {
          'name': player.name,
          'totalTime': player.totalTime,
          'active': player.active,
          'lastActiveMatchTime': player.lastActiveMatchTime,
          'goals': player.goals,
        };
      });
      
      // Add enhanced data to session data
      enhancedSessionData['players'] = playersMap;
      enhancedSessionData['teamGoals'] = _session.teamGoals;
      enhancedSessionData['opponentGoals'] = _session.opponentGoals;
      enhancedSessionData['matchTime'] = _session.matchTime;
      
      // Convert match log entries to maps
      final List<Map<String, dynamic>> matchLogMaps = [];
      for (var entry in _session.matchLog) {
        matchLogMaps.add(entry.toJson());
      }
      
      // Save to history
      final result = await HiveSessionDatabase.instance.saveSessionToHistory(
        enhancedSessionData, 
        matchLogMaps
      );
      
      print('Session saved to history: $result');
      return result;
    } catch (e) {
      print('Error saving session to history: $e');
      return false;
    }
  }
  
  // Get history entries for a session
  Future<List<Map<String, dynamic>>> getSessionHistory(int sessionId) async {
    try {
      final historyEntries = await HiveSessionDatabase.instance.getSessionHistory(sessionId);
      
      // Fix any old match end entries with the wrong translation
      for (var entry in historyEntries) {
        if (entry.containsKey('match_log') && entry['match_log'] is List) {
          final matchLog = entry['match_log'] as List;
          for (var i = 0; i < matchLog.length; i++) {
            if (matchLog[i] is Map && 
                matchLog[i]['entryType'] == 'match_end' && 
                matchLog[i]['details'] != null && 
                matchLog[i]['details'].toString().contains('match.match_ended')) {
                  
              // Extract the score from the original text
              final originalText = matchLog[i]['details'].toString();
              final scoreRegex = RegExp(r'\((\d+)-(\d+)\)');
              final match = scoreRegex.firstMatch(originalText);
              
              if (match != null) {
                final score = "${match.group(1)}-${match.group(2)}";
                // Replace with the correct text
                matchLog[i]['details'] = "Match Complete! ($score)";
                
                // Update the entry in the database
                await HiveSessionDatabase.instance.updateHistoryEntry(entry);
              }
            }
          }
        }
      }
      
      return historyEntries;
    } catch (e) {
      print('Error getting session history: $e');
      return [];
    }
  }
  
  // Get history entries for the current session
  Future<List<Map<String, dynamic>>> getCurrentSessionHistory() async {
    if (_currentSessionId == null) {
      return [];
    }
    return getSessionHistory(_currentSessionId!);
  }
  
  // Delete a history entry
  Future<bool> deleteHistoryEntry(String historyId) async {
    try {
      return await HiveSessionDatabase.instance.deleteHistoryEntry(historyId);
    } catch (e) {
      print('Error deleting history entry: $e');
      return false;
    }
  }
  
  // Delete all history for a session
  Future<bool> deleteSessionHistory(int sessionId) async {
    try {
      return await HiveSessionDatabase.instance.deleteSessionHistory(sessionId);
    } catch (e) {
      print('Error deleting session history: $e');
      return false;
    }
  }
  
  // Update a history entry
  Future<bool> updateHistoryEntry(Map<String, dynamic> historyEntry) async {
    try {
      return await HiveSessionDatabase.instance.updateHistoryEntry(historyEntry);
    } catch (e) {
      print('Error updating history entry: $e');
      return false;
    }
  }

}