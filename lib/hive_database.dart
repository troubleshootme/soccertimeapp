import 'package:hive_flutter/hive_flutter.dart';
// Create a local Session class with all required properties
class Session {
  final int id;
  final String name;
  final String sessionName;
  final bool enableVibration;
  final bool enableMatchDuration;
  
  Session({
    required this.id,
    required this.name,
    required this.sessionName,
    this.enableVibration = true,
    this.enableMatchDuration = true,
  });
}

class HiveSessionDatabase {
  static const String sessionBoxName = 'sessions';
  static const String playersBoxName = 'players';
  static const String settingsBoxName = 'sessionSettings';
  static const String historyBoxName = 'sessionHistory'; // New box for session history
  
  static HiveSessionDatabase? _instance;
  static HiveSessionDatabase get instance => _instance ??= HiveSessionDatabase._();
  
  bool _initialized = false;
  Box<Map>? _sessionsBox;
  Box<Map>? _playersBox;
  Box<Map>? _settingsBox;
  Box<Map>? _historyBox; // New box for session history
  
  HiveSessionDatabase._();
  
  Future<void> init() async {
    // If already initialized and boxes are still open, just return
    if (_initialized && 
        _sessionsBox != null && _sessionsBox!.isOpen &&
        _playersBox != null && _playersBox!.isOpen &&
        _settingsBox != null && _settingsBox!.isOpen &&
        _historyBox != null && _historyBox!.isOpen) {
      return;
    }
    
    try {
      // Initialize Hive
      await Hive.initFlutter();
      
      // Close any existing boxes first
      await _sessionsBox?.close();
      await _playersBox?.close();
      await _settingsBox?.close();
      await _historyBox?.close();
      
      // Open boxes (or reuse existing ones if they're still open)
      _sessionsBox = await Hive.openBox<Map>(sessionBoxName);
      _playersBox = await Hive.openBox<Map>(playersBoxName);
      _settingsBox = await Hive.openBox<Map>(settingsBoxName);
      _historyBox = await Hive.openBox<Map>(historyBoxName);
      
      _initialized = true;
      print('Hive database initialized successfully');
    } catch (e) {
      print('Error initializing Hive database: $e');
      _initialized = false;
      throw e;
    }
  }
  
  // SESSIONS
  
  Future<int> insertSession(String name) async {
    await init();
    
    // Find the next available ID
    final usedIds = _sessionsBox!.keys.cast<int>().toList();
    usedIds.sort();
    
    // Get the next ID (either max+1 or 1 if empty)
    final sessionId = usedIds.isEmpty ? 1 : usedIds.last + 1;
    
    // Ensure name is not empty
    final sessionName = name.trim().isEmpty ? "Session $sessionId" : name.trim();
    
    // Store session in Hive
    final sessionData = {
      'id': sessionId,
      'name': sessionName, 
      'created_at': DateTime.now().millisecondsSinceEpoch
    };
    
    // Store using the same ID as the key
    await _sessionsBox!.put(sessionId, sessionData);
    print('Inserted session with ID $sessionId into Hive with name "$sessionName"');
    
    return sessionId;
  }
  
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    await init();
    final List<Map<String, dynamic>> sessions = [];
    
    // Get all sessions from the box
    final keys = _sessionsBox!.keys.cast<int>().toList();
    keys.sort(); // Sort keys to maintain order
    
    for (final key in keys) {
      try {
        final rawSession = _sessionsBox!.get(key);
        if (rawSession == null) continue;
        
        // Convert to Map<String, dynamic>
        final Map<dynamic, dynamic> originalMap = Map<dynamic, dynamic>.from(rawSession);
        final Map<String, dynamic> session = {};
        
        // Copy values with string keys
        originalMap.forEach((k, v) {
          session[k.toString()] = v;
        });
        
        // Ensure ID matches the storage key
        session['id'] = key;
        
        // Ensure session has a valid name
        if (session['name'] == null || session['name'].toString().trim().isEmpty) {
          session['name'] = 'Session ${key}';
          // Update the session in storage with the valid name
          await updateSession(session);
        }
        
        sessions.add(session);
        print('Retrieved session: key=$key, id=${session['id']}, name=${session['name']}');
      } catch (e) {
        print('Error processing session with key $key: $e');
      }
    }
    
    // Sort by last_used_at timestamp first (if available), then by created_at (newest first)
    sessions.sort((a, b) {
      // Check if last_used_at timestamp exists on both sessions
      final aLastUsed = a['last_used_at'] as int?;
      final bLastUsed = b['last_used_at'] as int?;
      
      // If both have last_used_at, compare them
      if (aLastUsed != null && bLastUsed != null) {
        return bLastUsed.compareTo(aLastUsed); // Most recently used first
      }
      
      // If only one has last_used_at, prioritize the one with it
      if (aLastUsed != null) return -1;
      if (bLastUsed != null) return 1;
      
      // Fall back to created_at timestamp
      return (b['created_at'] ?? 0).compareTo(a['created_at'] ?? 0);
    });
    
    print('Retrieved ${sessions.length} sessions from Hive');
    return sessions;
  }
  
  Future<Map<String, dynamic>?> getSession(int id) async {
    await init();
    try {
      final sessionMap = _sessionsBox!.get(id);
      if (sessionMap == null) {
        print('HiveSessionDatabase: Session not found with id: $id');
        return null;
      }
      
      try {
        // First convert to Map<dynamic, dynamic> then to Map<String, dynamic>
        final dynamicMap = Map<dynamic, dynamic>.from(sessionMap);
        final session = Map<String, dynamic>.fromEntries(
          dynamicMap.entries.map((entry) => MapEntry(entry.key.toString(), entry.value))
        );
        
        // Ensure session name is not null or empty
        if (session['name'] == null || session['name'] == '') {
          session['name'] = 'Session $id';
          print('Fixed empty session name for session $id when retrieving');
          
          // Save the fixed session back to storage
          await updateSession(session);
        }
        
        // Update last_used_at timestamp
        session['last_used_at'] = DateTime.now().millisecondsSinceEpoch;
        
        // Save the updated timestamp
        await updateSession(session);
        
        print('HiveSessionDatabase: Successfully retrieved session: id=$id, name="${session['name']}"');
        return session;
      } catch (e) {
        print('HiveSessionDatabase: Error casting session data: $e');
        return null;
      }
    } catch (e) {
      print('HiveSessionDatabase: Error retrieving session: $e');
      return null;
    }
  }
  
  Future<bool> updateSession(Map<String, dynamic> session) async {
    await init();
    
    try {
      final sessionId = session['id'];
      if (sessionId == null) {
        print('Cannot update session: No ID provided');
        return false;
      }
      
      // Convert to Map<dynamic, dynamic> for Hive storage
      final Map<dynamic, dynamic> storageMap = {};
      session.forEach((k, v) {
        storageMap[k] = v;
      });
      
      await _sessionsBox!.put(sessionId, storageMap);
      print('Updated session with ID $sessionId');
      return true;
    } catch (e) {
      print('Error updating session: $e');
      return false;
    }
  }
  
  Future<bool> deleteSession(int id) async {
    await init();
    
    await _sessionsBox!.delete(id);
    
    // Also delete all players for this session
    final playersToDelete = await getPlayersForSession(id);
    for (final player in playersToDelete) {
      await deletePlayer(player['id']);
    }
    
    // Delete session settings
    await _settingsBox!.delete(id);
    
    print('Deleted session $id from Hive');
    return true;
  }
  
  // PLAYERS
  
  Future<int> insertPlayer(int sessionId, String name, int timerSeconds) async {
    await init();
    
    // Create player ID
    final playerId = (_playersBox!.length + 1);
    
    // Create player data
    final playerData = {
      'id': playerId,
      'session_id': sessionId,
      'name': name,
      'timer_seconds': timerSeconds
    };
    
    // Store in Hive
    await _playersBox!.put(playerId, playerData);
    print('Inserted player with ID $playerId into Hive');
    
    return playerId;
  }
  
  Future<List<Map<String, dynamic>>> getPlayersForSession(int sessionId) async {
    await init();
    
    final List<Map<String, dynamic>> players = [];
    
    for (var key in _playersBox!.keys) {
      final playerMap = _playersBox!.get(key);
      if (playerMap != null) {
        try {
          final player = Map<String, dynamic>.from(playerMap);
          if (player['session_id'] == sessionId) {
            players.add(player);
          }
        } catch (e) {
          print('Error parsing player $key: $e');
        }
      }
    }
    
    print('Loaded ${players.length} players for session $sessionId from Hive');
    return players;
  }
  
  Future<bool> updatePlayerTimer(int playerId, int timerSeconds) async {
    await init();
    
    final playerMap = _playersBox!.get(playerId);
    if (playerMap != null) {
      try {
        final player = Map<String, dynamic>.from(playerMap);
        player['timer_seconds'] = timerSeconds;
        await _playersBox!.put(playerId, player);
        print('Updated player $playerId timer to $timerSeconds seconds');
        return true;
      } catch (e) {
        print('Error updating player $playerId: $e');
        return false;
      }
    }
    return false;
  }
  
  Future<bool> deletePlayer(int id) async {
    await init();
    
    await _playersBox!.delete(id);
    print('Deleted player $id from Hive');
    return true;
  }
  
  // SESSION SETTINGS
  
  Future<bool> saveSessionSettings(int sessionId, Map<String, dynamic> settings) async {
    await init();
    
    await _settingsBox!.put(sessionId, settings);
    print('Saved settings for session $sessionId to Hive');
    return true;
  }
  
  Future<Map<String, dynamic>?> getSessionSettings(int sessionId) async {
    await init();
    
    final settingsMap = _settingsBox!.get(sessionId);
    if (settingsMap != null) {
      try {
        return Map<String, dynamic>.from(settingsMap);
      } catch (e) {
        print('Error parsing session settings for session $sessionId: $e');
        return null;
      }
    }
    return null;
  }
  
  // SESSION HISTORY METHODS
  
  // Save a session to history
  Future<bool> saveSessionToHistory(Map<String, dynamic> sessionData, List<Map<String, dynamic>> matchLog) async {
    await init();
    
    try {
      final sessionId = sessionData['id'];
      if (sessionId == null) {
        print('Cannot save session to history: No ID provided');
        return false;
      }
      
      // Create a unique key for the history entry (timestamp + session ID to ensure uniqueness)
      final historyKey = '${DateTime.now().millisecondsSinceEpoch}_$sessionId';
      
      // Generate a meaningful default title using date and score
      final now = DateTime.now();
      final dateStr = '${now.month}/${now.day}/${now.year}';
      final sessionName = sessionData['name'] ?? 'Session $sessionId';
      
      // Get score if available
      String scoreStr = '';
      if (sessionData.containsKey('teamGoals') && sessionData.containsKey('opponentGoals')) {
        final teamGoals = sessionData['teamGoals'];
        final opponentGoals = sessionData['opponentGoals'];
        scoreStr = ' ($teamGoals-$opponentGoals)';
      }
      
      // Create title with date and score (e.g. "12/25/2023 (3-1)")
      final title = '$dateStr$scoreStr';
      
      // Create the history entry with session data and match log
      final historyEntry = Map<dynamic, dynamic>.from({
        'id': historyKey,
        'session_id': sessionId,
        'session_data': sessionData,
        'match_log': matchLog,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'title': title,  // More meaningful default title
      });
      
      // Store the history entry
      await _historyBox!.put(historyKey, historyEntry);
      print('Saved session $sessionId to history with key $historyKey');
      return true;
    } catch (e) {
      print('Error saving session to history: $e');
      return false;
    }
  }
  
  // Get all history entries for a session
  Future<List<Map<String, dynamic>>> getSessionHistory(int sessionId) async {
    await init();
    final List<Map<String, dynamic>> historyEntries = [];
    
    for (final key in _historyBox!.keys) {
      try {
        final rawEntry = _historyBox!.get(key);
        if (rawEntry == null) continue;
        
        // Convert to Map<String, dynamic>
        final Map<dynamic, dynamic> originalMap = Map<dynamic, dynamic>.from(rawEntry);
        final Map<String, dynamic> entry = {};
        
        // Copy values with string keys
        originalMap.forEach((k, v) {
          entry[k.toString()] = v;
        });
        
        // Check if this entry belongs to the requested session
        if (entry['session_id'] == sessionId) {
          historyEntries.add(entry);
        }
      } catch (e) {
        print('Error processing history entry with key $key: $e');
      }
    }
    
    // Sort by created_at timestamp (newest first)
    historyEntries.sort((a, b) => 
      (b['created_at'] ?? 0).compareTo(a['created_at'] ?? 0)
    );
    
    print('Retrieved ${historyEntries.length} history entries for session $sessionId');
    return historyEntries;
  }
  
  // Get a specific history entry by its ID
  Future<Map<String, dynamic>?> getHistoryEntry(String historyId) async {
    await init();
    
    try {
      final rawEntry = _historyBox!.get(historyId);
      if (rawEntry == null) {
        print('History entry not found with id: $historyId');
        return null;
      }
      
      // Convert to Map<String, dynamic>
      final Map<dynamic, dynamic> originalMap = Map<dynamic, dynamic>.from(rawEntry);
      final Map<String, dynamic> entry = {};
      
      // Copy values with string keys
      originalMap.forEach((k, v) {
        entry[k.toString()] = v;
      });
      
      return entry;
    } catch (e) {
      print('Error retrieving history entry: $e');
      return null;
    }
  }
  
  // Delete a specific history entry
  Future<bool> deleteHistoryEntry(String historyId) async {
    await init();
    
    try {
      await _historyBox!.delete(historyId);
      print('Deleted history entry $historyId');
      return true;
    } catch (e) {
      print('Error deleting history entry: $e');
      return false;
    }
  }
  
  // Delete all history entries for a session
  Future<bool> deleteSessionHistory(int sessionId) async {
    await init();
    
    try {
      // Find all history entries for this session
      final entries = await getSessionHistory(sessionId);
      
      // Delete each entry
      for (final entry in entries) {
        final historyId = entry['id'];
        if (historyId != null) {
          await _historyBox!.delete(historyId);
        }
      }
      
      print('Deleted all history entries for session $sessionId');
      return true;
    } catch (e) {
      print('Error deleting session history: $e');
      return false;
    }
  }
  
  // Update history entry
  Future<bool> updateHistoryEntry(Map<String, dynamic> historyEntry) async {
    await init();
    
    try {
      final historyId = historyEntry['id'];
      if (historyId == null) {
        print('Cannot update history entry: No ID provided');
        return false;
      }
      
      // Convert to Map<dynamic, dynamic> for Hive storage
      final Map<dynamic, dynamic> storageMap = {};
      historyEntry.forEach((k, v) {
        storageMap[k] = v;
      });
      
      await _historyBox!.put(historyId, storageMap);
      print('Updated history entry with ID $historyId');
      return true;
    } catch (e) {
      print('Error updating history entry: $e');
      return false;
    }
  }
  
  // CLEANUP
  
  Future<void> close() async {
    await _sessionsBox?.close();
    await _playersBox?.close();
    await _settingsBox?.close();
    await _historyBox?.close();
    print('Hive database closed');
  }
  
  Future<void> clearAllSessions() async {
    await init();
    
    // Clear all boxes
    await _sessionsBox!.clear();
    await _playersBox!.clear();
    await _settingsBox!.clear();
    await _historyBox!.clear();
    
    print('Cleared all sessions from Hive database');
  }

  // Add method to sync session from SQLite database to Hive
  Future<bool> syncSessionFromSQLite(int sessionId, Map<String, dynamic> sessionData) async {
    await init();
    
    try {
      // Convert to Map<dynamic, dynamic> for Hive storage
      final Map<dynamic, dynamic> storageMap = {};
      sessionData.forEach((k, v) {
        storageMap[k] = v;
      });
      
      // Store in Hive using the same ID as the key
      await _sessionsBox!.put(sessionId, storageMap);
      print('Synced session with ID $sessionId from SQLite to Hive');
      return true;
    } catch (e) {
      print('Error syncing session from SQLite to Hive: $e');
      return false;
    }
  }

  Future<void> updateSettings(Map<String, dynamic> sessionSettings) async {
    await init();
    
    try {
      final sessionId = sessionSettings['id'];
      if (sessionId == null) {
        print('Cannot update session settings: No ID provided');
        return;
      }
      
      // Convert to Map<dynamic, dynamic> for Hive storage
      final Map<dynamic, dynamic> storageMap = {};
      sessionSettings.forEach((k, v) {
        storageMap[k] = v;
      });
      
      await _settingsBox!.put(sessionId, storageMap);
      print('Saved settings for session $sessionId to Hive');
    } catch (e) {
      print('Error updating session settings: $e');
    }
  }

  Future<int?> getSessionIdByName(String sessionName) async {
    final sessions = await getAllSessions();
    final session = sessions.firstWhere(
      (s) => s['name'] == sessionName,
      orElse: () => {'id': null},
    );
    return session['id'];
  }
} 