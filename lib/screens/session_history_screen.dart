import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';
import '../hive_database.dart';
import 'match_log_screen.dart';
import 'player_times_screen.dart';
import 'package:intl/intl.dart';

class SessionHistoryScreen extends StatefulWidget {
  @override
  _SessionHistoryScreenState createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyEntries = [];
  int? _sessionId;
  String _sessionName = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSessionHistory();
  }

  Future<void> _loadSessionHistory() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    // Get session details from arguments
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _sessionId = args['sessionId'];
      _sessionName = args['sessionName'] ?? 'Session History';
    }

    if (_sessionId != null) {
      final appState = Provider.of<AppState>(context, listen: false);
      final historyEntries = await appState.getSessionHistory(_sessionId!);
      
      if (mounted) {
        setState(() {
          _historyEntries = historyEntries;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<AppState>(context).isDarkTheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Session History: $_sessionName'),
        backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
                    ),
                  )
                : _historyEntries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'No history entries found for this session.\n\nHistory entries are created when matches are completed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? AppThemes.darkText : AppThemes.lightText,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _historyEntries.length,
                        padding: const EdgeInsets.all(16.0),
                        itemBuilder: (context, index) {
                          final entry = _historyEntries[index];
                          final date = DateTime.fromMillisecondsSinceEpoch(entry['created_at'] ?? 0);
                          final formattedDate = DateFormat('MM/dd/yyyy h:mm a').format(date);
                          
                          // Get session data and match log
                          final sessionData = entry['session_data'];
                          final matchLog = entry['match_log'] as List?;
                          
                          // Get the team score if available
                          String scoreText = '';
                          if (sessionData != null && 
                              sessionData['teamGoals'] != null && 
                              sessionData['opponentGoals'] != null) {
                            scoreText = 'Score: ${sessionData['teamGoals']} - ${sessionData['opponentGoals']}';
                          }
                          
                          return Card(
                            color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isDark ? AppThemes.darkSecondaryBlue.withOpacity(0.3) : AppThemes.lightSecondaryBlue.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry['title'] ?? 'Session ${entry['session_id'] ?? ""}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Completed on $formattedDate',
                                        style: TextStyle(
                                          color: isDark ? AppThemes.darkText.withOpacity(0.7) : AppThemes.lightText.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (scoreText.isNotEmpty)
                                        Text(
                                          scoreText,
                                          style: TextStyle(
                                            color: isDark ? AppThemes.darkText.withOpacity(0.7) : AppThemes.lightText.withOpacity(0.7),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.edit,
                                          color: isDark ? Colors.white70 : AppThemes.lightSecondaryBlue.withOpacity(0.7),
                                          size: 24,
                                        ),
                                        onPressed: () => _showRenameHistoryEntryDialog(entry),
                                        tooltip: 'Rename match',
                                        constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: EdgeInsets.all(12),
                                      ),
                                      SizedBox(width: 4),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: Colors.red.shade300,
                                          size: 24,
                                        ),
                                        onPressed: () => _showDeleteHistoryEntryDialog(entry),
                                        tooltip: 'Delete match',
                                        constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                        padding: EdgeInsets.all(12),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // View Match Log button
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.list_alt),
                                          label: const Text('Match Log'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => _navigateToMatchLog(entry),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // View Player Times button
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.timer),
                                          label: const Text('Player Times'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => _navigateToPlayerTimes(entry),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          // Add "Clear Session History" button at the bottom
          if (!_isLoading && _historyEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text('Clear Session History'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showClearHistoryDialog,
              ),
            ),
        ],
      ),
    );
  }

  // Show confirmation dialog for deleting a single history entry
  void _showDeleteHistoryEntryDialog(Map<String, dynamic> historyEntry) {
    final isDark = Provider.of<AppState>(context, listen: false).isDarkTheme;
    final date = DateTime.fromMillisecondsSinceEpoch(historyEntry['created_at'] ?? 0);
    final formattedDate = DateFormat('MM/dd/yyyy h:mm a').format(date);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Delete History Entry',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        content: Text(
          'Are you sure you want to delete the match history from $formattedDate?',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteHistoryEntry(historyEntry['id']);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Show confirmation dialog for clearing all history
  void _showClearHistoryDialog() {
    final isDark = Provider.of<AppState>(context, listen: false).isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Clear All Session History',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ALL match history for $_sessionName?\n\nThis action cannot be undone.',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllHistory();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  // Delete a single history entry
  Future<void> _deleteHistoryEntry(String? historyId) async {
    if (historyId == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final result = await appState.deleteHistoryEntry(historyId);
      
      if (result && mounted) {
        // Refresh the history list
        await _loadSessionHistory();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('History entry deleted')),
        );
      }
    } catch (e) {
      print('Error deleting history entry: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting history entry')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Clear all history for this session
  Future<void> _clearAllHistory() async {
    if (_sessionId == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final result = await appState.deleteSessionHistory(_sessionId!);
      
      if (result && mounted) {
        // Refresh the history list
        await _loadSessionHistory();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('All history cleared for this session')),
        );
      }
    } catch (e) {
      print('Error clearing session history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing session history')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Navigate to Match Log screen
  void _navigateToMatchLog(Map<String, dynamic> historyEntry) {
    final matchLog = historyEntry['match_log'];
    final sessionData = historyEntry['session_data'];
    final title = historyEntry['title'] ?? 'Session ${historyEntry['session_id'] ?? ""}';
    final date = DateTime.fromMillisecondsSinceEpoch(historyEntry['created_at'] ?? 0);
    final formattedDate = DateFormat('MM/dd/yyyy h:mm a').format(date);
    
    // Extract team and opponent goals from session data
    int teamGoals = 0;
    int opponentGoals = 0;
    
    if (sessionData != null) {
      if (sessionData.containsKey('teamGoals')) {
        teamGoals = sessionData['teamGoals'] is int ? sessionData['teamGoals'] : 0;
      }
      
      if (sessionData.containsKey('opponentGoals')) {
        opponentGoals = sessionData['opponentGoals'] is int ? sessionData['opponentGoals'] : 0;
      }
    }
    
    print('Score from history entry (match log): $teamGoals-$opponentGoals');
    
    // Format the name with score
    final String formattedTitle;
    if (title.trim().isEmpty || title.toLowerCase() == 'session' || title.toLowerCase() == 'match') {
      // For generic/default names, use "Match" label with date and score
      formattedTitle = 'Match ($teamGoals-$opponentGoals)';
    } else {
      // For custom named matches, use the custom name with score
      formattedTitle = '$title ($teamGoals-$opponentGoals)';
    }
    
    if (matchLog != null) {
      // Safely convert the matchLog entries to the expected format
      List<Map<String, dynamic>> typedMatchLog = [];
      
      if (matchLog is List) {
        for (var entry in matchLog) {
          if (entry is Map) {
            // Convert each entry to Map<String, dynamic>
            typedMatchLog.add(Map<String, dynamic>.from(entry));
          }
        }
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MatchLogScreen(
            isHistory: true,
            historyMatchLog: typedMatchLog,
            historySessionName: formattedTitle,
            teamGoals: teamGoals,
            opponentGoals: opponentGoals,
            timestamp: date,
          ),
        ),
      );
    }
  }
  
  // Navigate to Player Times screen
  void _navigateToPlayerTimes(Map<String, dynamic> historyEntry) {
    final sessionData = historyEntry['session_data'];
    final playersData = sessionData?['players'];
    final title = historyEntry['title'] ?? 'Session ${historyEntry['session_id'] ?? ""}';
    final date = DateTime.fromMillisecondsSinceEpoch(historyEntry['created_at'] ?? 0);
    final formattedDate = DateFormat('MM/dd/yyyy h:mm a').format(date);
    
    // Extract team and opponent goals from session data
    int teamGoals = 0;
    int opponentGoals = 0;
    
    if (sessionData != null) {
      if (sessionData.containsKey('teamGoals')) {
        teamGoals = sessionData['teamGoals'] is int ? sessionData['teamGoals'] : 0;
      }
      
      if (sessionData.containsKey('opponentGoals')) {
        opponentGoals = sessionData['opponentGoals'] is int ? sessionData['opponentGoals'] : 0;
      }
    }
    
    print('Score from history entry: $teamGoals-$opponentGoals');
    
    // Format the name with score
    final String formattedTitle;
    if (title.trim().isEmpty || title.toLowerCase() == 'session' || title.toLowerCase() == 'match') {
      // For generic/default names, use "Match" label with date and score
      formattedTitle = 'Match ($teamGoals-$opponentGoals)';
    } else {
      // For custom named matches, use the custom name with score
      formattedTitle = '$title ($teamGoals-$opponentGoals)';
    }
    
    if (playersData != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerTimesScreen(
            isHistory: true,
            historyPlayersData: playersData,
            historySessionName: formattedTitle,
            teamGoals: teamGoals,
            opponentGoals: opponentGoals,
            timestamp: date,
          ),
        ),
      );
    }
  }

  // Add rename history entry dialog method
  void _showRenameHistoryEntryDialog(Map<String, dynamic> historyEntry) {
    final isDark = Provider.of<AppState>(context, listen: false).isDarkTheme;
    final TextEditingController nameController = TextEditingController();
    final historyId = historyEntry['id'];
    final date = DateTime.fromMillisecondsSinceEpoch(historyEntry['created_at'] ?? 0);
    final formattedDate = DateFormat('MM/dd/yyyy h:mm a').format(date);
    final sessionId = historyEntry['session_id'];
    
    // Start with empty text field instead of current title
    nameController.text = '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Name This Match',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give this match a descriptive name:',
              style: TextStyle(
                color: isDark ? AppThemes.darkText.withOpacity(0.7) : AppThemes.lightText.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            Text(
              '(Match date: $formattedDate)',
              style: TextStyle(
                color: isDark ? AppThemes.darkText.withOpacity(0.5) : AppThemes.lightText.withOpacity(0.5),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
              decoration: InputDecoration(
                hintText: 'Home vs Away or Tournament Finals',
                hintStyle: TextStyle(
                  color: isDark ? AppThemes.darkText.withOpacity(0.5) : AppThemes.lightText.withOpacity(0.5),
                  fontStyle: FontStyle.italic,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: isDark ? AppThemes.darkSecondaryBlue.withOpacity(0.7) : AppThemes.lightSecondaryBlue.withOpacity(0.7),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final newTitle = nameController.text.trim();
              if (newTitle.isNotEmpty) {
                try {
                  final appState = Provider.of<AppState>(context, listen: false);
                  
                  // Update the history entry
                  historyEntry['title'] = newTitle;
                  final result = await appState.updateHistoryEntry(historyEntry);
                  
                  if (result) {
                    // Refresh the history list
                    await _loadSessionHistory();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Match renamed successfully')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to rename match')),
                    );
                  }
                } catch (e) {
                  print('Error renaming history entry: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error renaming match')),
                  );
                }
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppThemes.lightSecondaryBlue,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
} 