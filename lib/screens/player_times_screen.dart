import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';
import '../utils/format_time.dart';
import '../models/player.dart';
import '../utils/app_themes.dart';
import '../services/pdf_service.dart';
import 'pdf_preview_screen.dart';
import 'package:intl/intl.dart';

class PlayerTimesScreen extends StatefulWidget {
  final bool isHistory;
  final dynamic historyPlayersData;
  final String? historySessionName;
  final int? teamGoals;
  final int? opponentGoals;
  final DateTime? timestamp;
  
  PlayerTimesScreen({
    this.isHistory = false,
    this.historyPlayersData,
    this.historySessionName,
    this.teamGoals,
    this.opponentGoals,
    this.timestamp,
  });
  
  @override
  _PlayerTimesScreenState createState() => _PlayerTimesScreenState();
}

class _PlayerTimesScreenState extends State<PlayerTimesScreen> {
  List<MapEntry<String, Player>> _historyPlayers = [];
  bool _isAscendingOrder = false; // Default to descending (most time first)
  bool _isExportingPdf = false;
  int _teamGoals = 0;
  int _opponentGoals = 0;
  
  @override
  void initState() {
    super.initState();
    // Initialize scores from widget parameters if provided
    if (widget.teamGoals != null) {
      _teamGoals = widget.teamGoals!;
    }
    if (widget.opponentGoals != null) {
      _opponentGoals = widget.opponentGoals!;
    }
    _processHistoryData();
  }
  
  void _processHistoryData() {
    if (!widget.isHistory || widget.historyPlayersData == null) return;
    
    try {
      final Map<String, Player> players = {};
      
      widget.historyPlayersData!.forEach((key, value) {
        final playerName = key.toString();
        
        // Handle case where value might be a Player object or a Map
        if (value is Map) {
          final player = Player(name: playerName);
          
          // Try to extract data based on common key patterns
          if (value.containsKey('totalTime')) {
            player.totalTime = value['totalTime'] as int? ?? 0;
          } else if (value.containsKey('total_time')) {
            player.totalTime = value['total_time'] as int? ?? 0;
          }
          
          if (value.containsKey('active')) {
            player.active = value['active'] as bool? ?? false;
          }
          
          if (value.containsKey('goals')) {
            player.goals = value['goals'] as int? ?? 0;
          }
          
          players[playerName] = player;
        } else {
          // Fallback if value is not a map
          print('Warning: Player data not in expected format: $value (type: ${value.runtimeType})');
          final player = Player(name: playerName);
          players[playerName] = player;
        }
      });
      
      if (players.isEmpty) {
        print('Warning: No players were successfully processed from history data');
        return;
      }
      
      setState(() {
        _historyPlayers = players.entries.toList();
        // Sort by total time (descending by default)
        _sortPlayers();
      });
      
      // Debug log the processed players
      print('Processed ${_historyPlayers.length} players from history data:');
      for (var player in _historyPlayers) {
        print('  Player: ${player.key}, Time: ${player.value.totalTime}');
      }
    } catch (e) {
      print('Error processing history player data: $e');
    }
  }
  
  void _sortPlayers() {
    if (widget.isHistory) {
      if (_isAscendingOrder) {
        _historyPlayers.sort((a, b) => a.value.totalTime.compareTo(b.value.totalTime));
      } else {
        _historyPlayers.sort((a, b) => b.value.totalTime.compareTo(a.value.totalTime));
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkTheme;
    
    // Clean up session name for display to remove redundant timestamp
    final String cleanTitle = widget.isHistory
        ? _cleanHistorySessionName(widget.historySessionName ?? "History")
        : 'Player Times';
    
    // Get players data based on source
    List<MapEntry<String, Player>> players;
    bool isPaused = false;
    int matchTime = 0;
    
    if (widget.isHistory) {
      players = _historyPlayers;
      
      // Try to get score from appState history data
      try {
        if (appState.currentSessionId != null) {
          _teamGoals = appState.session.teamGoals;
          _opponentGoals = appState.session.opponentGoals;
        }
      } catch (e) {
        print('Could not retrieve score for history: $e');
      }
    } else {
      var session = appState.session;
      isPaused = session.isPaused;
      matchTime = session.matchTime;
      _teamGoals = session.teamGoals;
      _opponentGoals = session.opponentGoals;
      
      players = session.players.entries.toList();
      
      // Sort players by time
      if (_isAscendingOrder) {
        players.sort((a, b) {
          var timeA = a.value.active && !session.isPaused
              ? a.value.totalTime +
                  (session.matchTime - (a.value.lastActiveMatchTime ?? session.matchTime))
              : a.value.totalTime;
          var timeB = b.value.active && !session.isPaused
              ? b.value.totalTime +
                  (session.matchTime - (b.value.lastActiveMatchTime ?? session.matchTime))
              : b.value.totalTime;
          if (timeA != timeB) return timeA.compareTo(timeB);
          return session.currentOrder.indexOf(a.key).compareTo(session.currentOrder.indexOf(b.key));
        });
      } else {
        players.sort((a, b) {
          var timeA = a.value.active && !session.isPaused
              ? a.value.totalTime +
                  (session.matchTime - (a.value.lastActiveMatchTime ?? session.matchTime))
              : a.value.totalTime;
          var timeB = b.value.active && !session.isPaused
              ? b.value.totalTime +
                  (session.matchTime - (b.value.lastActiveMatchTime ?? session.matchTime))
              : b.value.totalTime;
          if (timeB != timeA) return timeB.compareTo(timeA);
          return session.currentOrder.indexOf(a.key).compareTo(session.currentOrder.indexOf(b.key));
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(cleanTitle),
        backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
        actions: [
          // Sort order toggle
          IconButton(
            icon: Icon(_isAscendingOrder ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _isAscendingOrder ? 'Sort by least time' : 'Sort by most time',
            onPressed: () {
              setState(() {
                _isAscendingOrder = !_isAscendingOrder;
                _sortPlayers();
              });
            },
          ),
          if (players.isNotEmpty) ...[
            // PDF Export Button
            IconButton(
              icon: Icon(Icons.picture_as_pdf),
              tooltip: 'Export as PDF',
              onPressed: _isExportingPdf ? null : () => _exportToPdf(context, appState, players),
            ),
            // Share Text Button
            IconButton(
              icon: Icon(Icons.share),
              tooltip: 'Share Player Times',
              onPressed: () => _sharePlayerTimes(context, players),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Score section at the top
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                color: isDark 
                    ? AppThemes.darkPrimaryBlue.withOpacity(0.7) 
                    : AppThemes.lightPrimaryBlue.withOpacity(0.7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        widget.isHistory
                            ? _cleanHistorySessionName(widget.historySessionName ?? "Session").replaceAll("Player Times: ", "")
                            : appState.session.sessionName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      '$_teamGoals - $_opponentGoals',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Player times table
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Table header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white30 : Colors.black12,
                                  width: 1.5
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    'Player',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: Text(
                                      'Time',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      'Goals',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Player list
                          Expanded(
                            child: players.isEmpty
                              ? Center(
                                  child: Text(
                                    'No player data available',
                                    style: TextStyle(
                                      color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: players.length,
                                  itemBuilder: (context, index) {
                                    var entry = players[index];
                                    var name = entry.key;
                                    var player = entry.value;
                                    var time = widget.isHistory 
                                        ? player.totalTime 
                                        : (player.active && !isPaused && player.lastActiveMatchTime != null)
                                            ? player.totalTime + (matchTime - player.lastActiveMatchTime!)
                                            : player.totalTime;
                                    
                                    return Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isDark ? Colors.white12 : Colors.black12,
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 5,
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              formatTime(time),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              '${player.goals}',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Show loading indicator when exporting PDF
          if (_isExportingPdf)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: isDark 
                          ? AppThemes.darkSecondaryBlue 
                          : AppThemes.lightSecondaryBlue,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Generating PDF...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Export player times to PDF
  Future<void> _exportToPdf(BuildContext context, AppState appState, List<MapEntry<String, Player>> players) async {
    if (players.isEmpty) return;
    
    setState(() {
      _isExportingPdf = true;
    });
    
    try {
      final pdfService = PdfService();
      final sessionName = widget.isHistory 
          ? widget.historySessionName ?? 'Session History' 
          : appState.session.sessionName;
      
      // Create a list of player time data
      final List<Map<String, dynamic>> playerData = [];
      
      for (var entry in players) {
        final name = entry.key;
        final player = entry.value;
        final time = widget.isHistory 
            ? player.totalTime 
            : (player.active && !appState.session.isPaused && player.lastActiveMatchTime != null)
                ? player.totalTime + (appState.session.matchTime - player.lastActiveMatchTime!)
                : player.totalTime;
        
        playerData.add({
          'name': name,
          'time': formatTime(time),
          'seconds': time,
          'goals': player.goals,
        });
      }
      
      // Get the timestamp - use widget's timestamp if provided, otherwise try to extract from name
      DateTime? timestamp = widget.timestamp;
      if (timestamp == null && widget.isHistory && widget.historySessionName != null) {
        timestamp = _extractDateFromHistoryName(widget.historySessionName!);
      }
      
      print('Using timestamp for PDF: ${timestamp?.toString() ?? 'Current time'}');
      
      // Generate PDF
      final pdfFile = await pdfService.generatePlayerTimesPdf(
        sessionName: sessionName,
        playerData: playerData,
        isDarkMode: appState.isDarkTheme,
        teamGoals: _teamGoals,
        opponentGoals: _opponentGoals,
        timestamp: timestamp,
      );
      
      setState(() {
        _isExportingPdf = false;
      });
      
      if (pdfFile != null) {
        // Navigate to PDF preview screen
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfPreviewScreen(
                pdfFile: pdfFile,
                title: 'Player Times',
              ),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to generate PDF')),
          );
        }
      }
    } catch (e) {
      print('Error generating PDF: $e');
      setState(() {
        _isExportingPdf = false;
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    }
  }
  
  // Helper method to extract date from history name format like "Title - MM/DD/YYYY h:mm a"
  DateTime? _extractDateFromHistoryName(String historyName) {
    try {
      // First check for the timestamp pattern with dash: "- MM/DD/YYYY h:mm a"
      final dateRegex = RegExp(r'(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\s*[ap]m)', caseSensitive: false);
      final match = dateRegex.firstMatch(historyName);
      
      if (match != null && match.group(1) != null) {
        final dateStr = match.group(1)!;
        // Parse with DateFormat from intl package
        return DateFormat('MM/dd/yyyy h:mm a').parse(dateStr);
      }
      
      // Also check for date with score pattern: MM/DD/YYYY (0-0)
      final dateScoreRegex = RegExp(r'(\d{1,2}/\d{1,2}/\d{4})\s*\(\d+-\d+\)', caseSensitive: false);
      final dateScoreMatch = dateScoreRegex.firstMatch(historyName);
      
      if (dateScoreMatch != null && dateScoreMatch.group(1) != null) {
        final dateStr = dateScoreMatch.group(1)!;
        // Parse with DateFormat from intl package
        return DateFormat('MM/dd/yyyy').parse(dateStr);
      }
      
      // Simple date format
      final simpleDateRegex = RegExp(r'(\d{1,2}/\d{1,2}/\d{4})', caseSensitive: false);
      final simpleDateMatch = simpleDateRegex.firstMatch(historyName);
      
      if (simpleDateMatch != null && simpleDateMatch.group(1) != null) {
        final dateStr = simpleDateMatch.group(1)!;
        // Parse with DateFormat from intl package
        return DateFormat('MM/dd/yyyy').parse(dateStr);
      }
      
      return null;
    } catch (e) {
      print('Error extracting date from history name: $e');
      return null;
    }
  }
  
  // Share player times as text
  Future<void> _sharePlayerTimes(BuildContext context, List<MapEntry<String, Player>> players) async {
    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No player data to share')),
      );
      return;
    }
    
    final buffer = StringBuffer();
    final sessionName = widget.isHistory 
        ? widget.historySessionName ?? 'Session History' 
        : Provider.of<AppState>(context, listen: false).session.sessionName;
    
    buffer.writeln('PLAYER TIMES: $sessionName');
    buffer.writeln('SCORE: $_teamGoals - $_opponentGoals');
    buffer.writeln('----------------------------------------');
    buffer.writeln();
    
    // Add player times
    for (var entry in players) {
      final name = entry.key;
      final player = entry.value;
      final time = widget.isHistory 
          ? player.totalTime 
          : (player.active && !Provider.of<AppState>(context, listen: false).session.isPaused && 
             player.lastActiveMatchTime != null)
              ? player.totalTime + 
                (Provider.of<AppState>(context, listen: false).session.matchTime - 
                 player.lastActiveMatchTime!)
              : player.totalTime;
      
      buffer.writeln('${name}: ${formatTime(time)}  (Goals: ${player.goals})');
    }
    
    await Share.share(buffer.toString(), subject: 'Soccer Time Player Times');
  }
  
  // Helper method to clean up history session name by removing redundant timestamp/score info
  String _cleanHistorySessionName(String historyName) {
    // Check if the session name is just a date pattern - if so, don't strip it
    final justDatePattern = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\s*[ap]m$');
    if (justDatePattern.hasMatch(historyName)) {
      return 'Player Times: $historyName';
    }
    
    // Also check for simple date format without time
    final simpleDatePattern = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');
    if (simpleDatePattern.hasMatch(historyName)) {
      return 'Player Times: $historyName';
    }
    
    // Pattern to match default generic names
    RegExp defaultNamePattern = RegExp(r'^(Session|History|Match)(\s+History)?$', caseSensitive: false);
    if (defaultNamePattern.hasMatch(historyName)) {
      return "Player Times";
    }
    
    // Only clean up if there's more than just a date/timestamp pattern
    
    // First try to remove timestamp pattern like "- MM/DD/YYYY h:mm a"
    final timestampPattern = RegExp(r'\s*-\s*\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\s*[ap]m', caseSensitive: false);
    String cleanName = historyName.replaceAll(timestampPattern, '');
    
    // Also clean up any score patterns
    final scorePattern = RegExp(r'\s*\(\d+-\d+\)');
    cleanName = cleanName.replaceAll(scorePattern, '');
    
    // If we've cleaned too much and have nothing left, return the original
    if (cleanName.trim().isEmpty) {
      return 'Player Times: $historyName';
    }
    
    // Add "Player Times:" prefix if it doesn't start with it
    if (!cleanName.toLowerCase().contains('player times')) {
      cleanName = 'Player Times: $cleanName';
    }
    
    return cleanName.trim();
  }
} 