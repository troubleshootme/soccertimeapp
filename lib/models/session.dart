import '../models/player.dart';
import '../models/match_log_entry.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

class Session extends ChangeNotifier {
  final Map<String, Player> players = {};
  final List<String> currentOrder = [];
  List<String> activeBeforePause = [];
  
  @HiveField(20)
  int _matchTime = 0;
  
  // New field to track UI timer state separately
  @HiveField(21)
  int _uiMatchTime = 0;
  
  int get matchTime => _matchTime;
  int get uiMatchTime => _uiMatchTime;
  
  set matchTime(int value) {
    _matchTime = value;
    notifyListeners();
  }
  
  set uiMatchTime(int value) {
    _uiMatchTime = value;
    notifyListeners();
  }
  
  int currentPeriod = 1;
  bool hasWhistlePlayed = false;
  bool matchRunning = false;
  bool isPaused = false;
  bool isMatchComplete = false;
  bool isSetup = true;  // New flag for setup mode
  
  // Team goals
  int teamGoals = 0;
  int opponentGoals = 0;
  
  // Settings
  bool enableMatchDuration;
  int matchDuration;
  int matchSegments;
  bool enableTargetDuration;
  int targetPlayDuration;
  bool enableSound;
  bool enableVibration;
  
  // Session name
  String sessionName;
  
  // Match log
  final List<MatchLogEntry> matchLog = [];
  
  int? lastUpdateTime;
  
  int? lastVibrationSecond;
  
  Session({
    this.sessionName = '',
    this.enableMatchDuration = true,
    this.matchDuration = 5400, // 90 minutes in seconds
    this.matchSegments = 2,
    this.enableTargetDuration = true,
    this.targetPlayDuration = 960, // 16 minutes in seconds
    this.enableSound = false,
    this.enableVibration = true, // Vibration enabled by default
    this.matchRunning = false,
    this.teamGoals = 0,
    this.opponentGoals = 0,
    this.isSetup = true,  // Initialize in setup mode
    this.lastVibrationSecond,
  }) : lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  
  // Clear the match log
  void clearMatchLog() {
    matchLog.clear();
  }
  
  void addPlayer(String name) {
    if (!players.containsKey(name)) {
      players[name] = Player(name: name);
      currentOrder.add(name);
    }
  }
  
  void updatePlayerTime(String name, int seconds) {
    if (players.containsKey(name)) {
      players[name]!.totalTime = seconds;
    }
  }
  
  void resetAllPlayers() {
    // Reset all player timers and goals but keep the players
    for (var player in players.values) {
      player.totalTime = 0;
      player.active = false;
      player.lastActiveMatchTime = null;
      player.goals = 0;
    }
  }
  
  void resetSessionState() {
    // Reset match time and period tracking
    _matchTime = 0;
    currentPeriod = 1;
    hasWhistlePlayed = false;
    matchRunning = false;
    isPaused = false;
    isMatchComplete = false;
    isSetup = true;  // Reset to setup mode
    lastUpdateTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Reset team goals
    teamGoals = 0;
    opponentGoals = 0;
    
    // Clear active before pause list
    activeBeforePause.clear();
    
    // Clear match log
    matchLog.clear();
    
    // Reset all players
    resetAllPlayers();
    
    // Reset current order
    currentOrder.clear();
    
    lastVibrationSecond = null;
  }
  
  void togglePlayerActive(String name) {
    if (players.containsKey(name)) {
      players[name]!.active = !players[name]!.active;
    }
  }
  
  // Format the current match time as mm:ss
  String get formattedMatchTime {
    final minutes = _matchTime ~/ 60;
    final seconds = _matchTime % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  // Add a new log entry
  void addMatchLogEntry(String details, {String entryType = 'standard', int? customMatchTime}) {
    final timeToUse = customMatchTime ?? _matchTime;
    final minutes = timeToUse ~/ 60;
    final seconds = timeToUse % 60;
    final formattedTime = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    
    final entry = MatchLogEntry(
      matchTime: formattedTime,
      seconds: timeToUse,
      timestamp: DateTime.now().toIso8601String(),
      details: details,
      entryType: entryType,
    );
    matchLog.add(entry);
  }
  
  // Get match log entries sorted by timestamp (newest first)
  List<MatchLogEntry> getSortedMatchLog() {
    final sortedLog = List<MatchLogEntry>.from(matchLog);
    sortedLog.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
    return sortedLog;
  }
  
  // Get match log entries sorted by match time in ascending order
  List<MatchLogEntry> getSortedMatchLogAscending() {
    final sortedLog = List<MatchLogEntry>.from(matchLog);
    sortedLog.sort((a, b) {
      // Sort by seconds first
      int timeCompare = a.seconds.compareTo(b.seconds);
      if (timeCompare != 0) return timeCompare;
      
      // If times are equal, sort by timestamp
      return a.timestamp.compareTo(b.timestamp);
    });
    return sortedLog;
  }

  Map<String, dynamic> toJson() => {
        'players': players.map((name, player) => MapEntry(name, player.toJson())),
        'currentOrder': currentOrder,
        'isPaused': isPaused,
        'activeBeforePause': activeBeforePause,
        'targetPlayDuration': targetPlayDuration,
        'enableTargetDuration': enableTargetDuration,
        'matchTime': _matchTime,
        'matchStartTime': 0,
        'matchRunning': matchRunning,
        'matchDuration': matchDuration,
        'enableMatchDuration': enableMatchDuration,
        'matchSegments': matchSegments,
        'currentPeriod': currentPeriod,
        'hasWhistlePlayed': hasWhistlePlayed,
        'enableSound': enableSound,
        'enableVibration': enableVibration,
        'matchLog': matchLog.map((entry) => entry.toJson()).toList(),
        'sessionName': sessionName,
        'lastUpdateTime': lastUpdateTime,
        'teamGoals': teamGoals,
        'opponentGoals': opponentGoals,
        'isSetup': isSetup,  // Add isSetup to JSON
        'lastVibrationSecond': lastVibrationSecond,
      };

  factory Session.fromJson(Map<String, dynamic> json) {
    final session = Session(
      sessionName: json['sessionName'] ?? '',
      enableMatchDuration: json['enableMatchDuration'] ?? true,
      matchDuration: json['matchDuration'] ?? 5400,
      matchSegments: json['matchSegments'] ?? 2,
      enableTargetDuration: json['enableTargetDuration'] ?? true,
      targetPlayDuration: json['targetPlayDuration'] ?? 960,
      enableSound: json['enableSound'] ?? false,
      enableVibration: json.containsKey('enableVibration') ? json['enableVibration'] : true,
      matchRunning: json['matchRunning'] ?? false,
      teamGoals: json['teamGoals'] ?? 0,
      opponentGoals: json['opponentGoals'] ?? 0,
      isSetup: json['isSetup'] ?? true,  // Load isSetup from JSON
      lastVibrationSecond: json['lastVibrationSecond'],
    );
    
    // Load match log if available
    if (json['matchLog'] is List) {
      for (var entry in json['matchLog']) {
        if (entry is Map<String, dynamic>) {
          // For period entries, set the entryType for backward compatibility
          if (entry['details'] != null) {
            String details = entry['details'].toString().toLowerCase();
            if (details.contains('half') || details.contains('quarter')) {
              if (details.contains('start of') || details.contains('end of')) {
                // This is likely a period transition entry added in the new format
                if (!entry.containsKey('entryType')) {
                  entry['entryType'] = 'period_transition';
                }
              }
            }
          }
          session.matchLog.add(MatchLogEntry.fromJson(entry));
        }
      }
    }
    
    return session;
  }

  Session copyWith({
    String? sessionName,
    bool? enableMatchDuration,
    int? matchDuration,
    int? matchSegments,
    bool? enableTargetDuration,
    int? targetPlayDuration,
    bool? enableSound,
    bool? enableVibration,
    bool? matchRunning,
    int? matchTime,
    int? currentPeriod,
    bool? hasWhistlePlayed,
    bool? isPaused,
    bool? isMatchComplete,
    bool? isSetup,  // Add isSetup to copyWith
    int? teamGoals,
    int? opponentGoals,
    int? lastVibrationSecond,
  }) {
    final newSession = Session(
      sessionName: sessionName ?? this.sessionName,
      enableMatchDuration: enableMatchDuration ?? this.enableMatchDuration,
      matchDuration: matchDuration ?? this.matchDuration,
      matchSegments: matchSegments ?? this.matchSegments,
      enableTargetDuration: enableTargetDuration ?? this.enableTargetDuration,
      targetPlayDuration: targetPlayDuration ?? this.targetPlayDuration,
      enableSound: enableSound ?? this.enableSound,
      enableVibration: enableVibration ?? this.enableVibration,
      matchRunning: matchRunning ?? this.matchRunning,
      teamGoals: teamGoals ?? this.teamGoals,
      opponentGoals: opponentGoals ?? this.opponentGoals,
      isSetup: isSetup ?? this.isSetup,  // Copy isSetup
      lastVibrationSecond: lastVibrationSecond ?? this.lastVibrationSecond,
    );
    
    // Copy over other state
    newSession._matchTime = matchTime ?? _matchTime;
    newSession.currentPeriod = currentPeriod ?? this.currentPeriod;
    newSession.hasWhistlePlayed = hasWhistlePlayed ?? this.hasWhistlePlayed;
    newSession.isPaused = isPaused ?? this.isPaused;
    newSession.isMatchComplete = isMatchComplete ?? this.isMatchComplete;
    
    // Copy players and their states
    for (var entry in players.entries) {
      newSession.players[entry.key] = Player(
        name: entry.key,
        totalTime: entry.value.totalTime,
        active: entry.value.active,
        lastActiveMatchTime: entry.value.lastActiveMatchTime,
        goals: entry.value.goals,
      );
    }
    
    // Copy current order and active before pause lists
    newSession.currentOrder.addAll(currentOrder);
    newSession.activeBeforePause.addAll(activeBeforePause);
    
    // Copy match log
    newSession.matchLog.addAll(matchLog);
    
    return newSession;
  }
}