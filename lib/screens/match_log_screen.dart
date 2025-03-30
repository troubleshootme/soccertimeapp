import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';
import '../models/match_log_entry.dart';
import '../utils/app_themes.dart';
import '../services/translation_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import '../services/pdf_service.dart';
import 'pdf_preview_screen.dart';

class MatchLogScreen extends StatefulWidget {
  final bool isHistory;
  final List<Map<String, dynamic>>? historyMatchLog;
  final String? historySessionName;
  final int? teamGoals;
  final int? opponentGoals;
  final DateTime? timestamp;
  
  MatchLogScreen({
    this.isHistory = false,
    this.historyMatchLog,
    this.historySessionName,
    this.teamGoals,
    this.opponentGoals,
    this.timestamp,
  });
  
  @override
  _MatchLogScreenState createState() => _MatchLogScreenState();
}

class _MatchLogScreenState extends State<MatchLogScreen> {
  bool _isAscendingOrder = true; // Default to ascending (match time order)
  bool _isExportingPdf = false;
  List<MatchLogEntry> _historyLogs = [];
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
    if (!widget.isHistory || widget.historyMatchLog == null) return;
    
    setState(() {
      _historyLogs = widget.historyMatchLog!.map((entry) {
        return MatchLogEntry.fromJson(entry);
      }).toList();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkTheme;
    
    // Get logs based on sort order and data source
    List<MatchLogEntry> logs;
    
    if (widget.isHistory) {
      // Sort historical logs
      if (_isAscendingOrder) {
        logs = List.from(_historyLogs)..sort((a, b) => a.seconds.compareTo(b.seconds));
      } else {
        logs = List.from(_historyLogs)..sort((a, b) => b.seconds.compareTo(a.seconds));
      }
    } else {
      // Get current logs from app state
      logs = _isAscendingOrder 
          ? appState.session.getSortedMatchLogAscending()
          : appState.session.getSortedMatchLog();
    }
    
    final title = widget.isHistory 
        ? 'Match Log: ${widget.historySessionName ?? "History"}'
        : context.tr('log.match_log');
    
    return Scaffold(
      backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
        title: Text(title),
        actions: [
          // Sort order toggle
          IconButton(
            icon: Icon(_isAscendingOrder ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _isAscendingOrder ? context.tr('log.sort_oldest') : context.tr('log.sort_newest'),
            onPressed: () {
              setState(() {
                _isAscendingOrder = !_isAscendingOrder;
              });
            },
          ),
          if (logs.isNotEmpty) ...[
            // PDF Export Button
            IconButton(
              icon: Icon(Icons.picture_as_pdf),
              tooltip: 'Export as PDF',
              onPressed: _isExportingPdf ? null : () => _exportToPdf(context, appState, logs),
            ),
            // Share Text Button
            IconButton(
              icon: Icon(Icons.share),
              tooltip: 'Share Match Log',
              onPressed: () => _shareMatchLog(context, appState, logs),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          logs.isEmpty
              ? _buildEmptyState(context, isDark)
              : _buildLogList(context, logs, isDark),
              
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
        onPressed: () => Navigator.pop(context),
        child: Icon(Icons.close, color: Colors.white),
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: isDark ? Colors.white70 : Colors.black45,
          ),
          SizedBox(height: 16),
          Text(
            context.tr('log.no_events'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black45,
            ),
          ),
          SizedBox(height: 8),
          Text(
            context.tr('log.events_appear'),
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black38,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogList(BuildContext context, List<MatchLogEntry> logs, bool isDark) {
    // Define colors for different entry types
    final mintGreen = Color(0xFF26C485);
    final darkMintGreen = Color(0xFF3EAB87);
    final softCyan = Color(0xFF29B6F6);      // Light Blue for match/period events
    final darkCyan = Color(0xFF0288D1);      // Darker Light Blue for dark theme
    final softRed = Color(0xFFE57373);
    final darkRed = Color(0xFFD32F2F);
    final softAmber = Color(0xFFFFCA28);
    final darkAmber = Color(0xFFFFA000);
    
    // If there are no entries, show a message
    if (logs.isEmpty) {
      return Center(
        child: Text(
          'No match events recorded',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 16,
          ),
        ),
      );
    }
    
    return ListView.builder(
      itemCount: logs.length,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      itemBuilder: (context, index) {
        final entry = logs[index];
        
        // Determine if this is a goal entry
        final isGoal = entry.details.toLowerCase().contains('goal') || entry.entryType?.toLowerCase() == 'goal';
        
        // Determine if this is a whistle entry (match start, period changes, match complete)
        final isWhistleEntry = entry.entryType?.toLowerCase() == 'match_start' ||
                             entry.entryType?.toLowerCase() == 'period_transition' ||
                             entry.entryType?.toLowerCase() == 'match_end';
        
        // Determine entry type for styling
        final isPeriodTransition = entry.entryType?.toLowerCase() == 'period_transition';
        final isMatchStart = entry.details.toLowerCase().contains(context.tr('match.match_started').toLowerCase()) ||
                           entry.entryType?.toLowerCase() == 'match_start';
        final isMatchComplete = entry.details.toLowerCase().contains(context.tr('match.match_complete').toLowerCase()) ||
                              entry.entryType?.toLowerCase() == 'match_end';
        final isPlayerEnter = entry.details.toLowerCase().contains(context.tr('match.entered_game').toLowerCase());
        final isPlayerExit = entry.details.toLowerCase().contains(context.tr('match.left_game').toLowerCase());
        
        // Skip reset entries
        if (entry.details.toLowerCase().contains('reset')) {
          return SizedBox.shrink();
        }
        
        // Determine time container color based on entry type
        Color timeContainerColor;
        Color timeTextColor;
        Color timeContainerBorderColor;
        
        if (isGoal) {
          // Goal events - amber/gold
          timeContainerColor = isDark ? darkAmber.withOpacity(0.2) : softAmber.withOpacity(0.2);
          timeContainerBorderColor = isDark ? darkAmber.withOpacity(0.4) : softAmber.withOpacity(0.4);
          timeTextColor = isDark ? softAmber : darkAmber;
        } else if (isMatchStart || isPeriodTransition || isMatchComplete || isWhistleEntry) {
          // All match/period events - light blue
          timeContainerColor = isDark ? darkCyan.withOpacity(0.2) : softCyan.withOpacity(0.2);
          timeContainerBorderColor = isDark ? darkCyan.withOpacity(0.4) : softCyan.withOpacity(0.4);
          timeTextColor = isDark ? Colors.lightBlue[300]! : darkCyan;
        } else if (isPlayerEnter) {
          // Player entering - green
          timeContainerColor = isDark ? darkMintGreen.withOpacity(0.2) : mintGreen.withOpacity(0.2);
          timeContainerBorderColor = isDark ? darkMintGreen.withOpacity(0.4) : mintGreen.withOpacity(0.4);
          timeTextColor = isDark ? mintGreen : darkMintGreen;
        } else if (isPlayerExit) {
          // Player exiting - red
          timeContainerColor = isDark ? darkRed.withOpacity(0.2) : softRed.withOpacity(0.2);
          timeContainerBorderColor = isDark ? darkRed.withOpacity(0.4) : softRed.withOpacity(0.4);
          timeTextColor = isDark ? softRed : darkRed;
        } else {
          // Default - gray
          timeContainerColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
          timeContainerBorderColor = isDark ? Colors.white24 : Colors.black12;
          timeTextColor = isDark ? Colors.white70 : Colors.black87;
        }
        
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isDark ? Colors.grey[850] : Colors.white,
          elevation: 1,
          child: ListTile(
            leading: isGoal 
              ? Container(
                  width: 40,
                  height: 40,
                  padding: EdgeInsets.all(8),
                  child: SvgPicture.asset(
                    'assets/images/soccerball.svg',
                  ),
                )
              : isWhistleEntry
                ? Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/images/white_whistle.svg',
                      colorFilter: ColorFilter.mode(
                        isDark ? Colors.white : Colors.blueGrey.shade700,
                        BlendMode.srcIn
                      ),
                    ),
                  )
              : isPlayerEnter
                ? Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/images/arrow_player_enter.svg',
                      colorFilter: ColorFilter.mode(
                        isDark ? Colors.white : darkMintGreen,
                        BlendMode.srcIn
                      ),
                    ),
                  )
              : isPlayerExit
                ? Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/images/arrow_player_left.svg',
                      colorFilter: ColorFilter.mode(
                        isDark ? Colors.white : darkRed,
                        BlendMode.srcIn
                      ),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: isDark 
                        ? AppThemes.darkSecondaryBlue.withOpacity(0.7)
                        : AppThemes.lightSecondaryBlue.withOpacity(0.7),
                    child: Icon(
                      _getEventIcon(entry.details),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: timeContainerColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: timeContainerBorderColor,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    entry.matchTime,
                    style: TextStyle(
                      color: timeTextColor,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.details,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: isPeriodTransition || isMatchComplete ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              _formatTimestamp(entry.timestamp),
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 12,
              ),
            ),
            trailing: _getTimeAgo(entry.timestamp),
          ),
        );
      },
    );
  }
  
  // Format ISO timestamp to a more user-friendly format
  String _formatTimestamp(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final DateFormat formatter = DateFormat('MMM d, h:mm a');
      return formatter.format(dateTime);
    } catch (e) {
      return timestamp;
    }
  }
  
  // Get an appropriate icon based on the event description
  IconData _getEventIcon(String details) {
    final lowerDetails = details.toLowerCase();
    
    if (lowerDetails.contains('entered the game')) {
      return Icons.login;
    } else if (lowerDetails.contains('left the game')) {
      return Icons.logout;
    } else if (lowerDetails.contains('paused')) {
      return Icons.pause_circle;
    } else if (lowerDetails.contains('resumed')) {
      return Icons.play_circle;
    } else if (lowerDetails.contains('match complete')) {
      return Icons.emoji_events;
    } else if (lowerDetails.contains('quarter started') || lowerDetails.contains('half started')) {
      return Icons.sports;
    } else if (lowerDetails.contains('reset')) {
      return Icons.refresh;
    } else if (lowerDetails.contains('added to roster')) {
      return Icons.person_add;
    } else if (lowerDetails.contains('removed from roster')) {
      return Icons.person_remove;
    } else if (lowerDetails.contains('session')) {
      return Icons.start;
    } else if (lowerDetails.contains('active players moving')) {
      return Icons.people;
    }
    
    // Default icon
    return Icons.event_note;
  }
  
  // Display relative time
  Widget _getTimeAgo(String timestamp) {
    try {
      final eventTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(eventTime);
      
      String timeAgo;
      
      if (difference.inSeconds < 60) {
        timeAgo = context.tr('log.just_now');
      } else if (difference.inMinutes < 60) {
        timeAgo = '${difference.inMinutes}m ${context.tr('log.ago')}';
      } else if (difference.inHours < 24) {
        timeAgo = '${difference.inHours}h ${context.tr('log.ago')}';
      } else {
        timeAgo = '${difference.inDays}d ${context.tr('log.ago')}';
      }
      
      return Text(
        timeAgo,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    } catch (e) {
      return Text('');
    }
  }
  
  Future<void> _exportToPdf(BuildContext context, AppState appState, List<MatchLogEntry> logs) async {
    if (logs.isEmpty) return;
    
    try {
      // Show loading indicator
      setState(() {
        _isExportingPdf = true;
      });
      
      // Get session name - use widget's history name if in history mode
      final sessionName = widget.isHistory 
          ? widget.historySessionName ?? 'Session History'
          : appState.session.sessionName;
      
      // Use the history scores if viewing history, otherwise use current session scores
      final teamGoals = widget.isHistory ? _teamGoals : appState.session.teamGoals;
      final opponentGoals = widget.isHistory ? _opponentGoals : appState.session.opponentGoals;
      
      // Get the timestamp - use widget's timestamp if provided, otherwise try to extract from name
      DateTime? timestamp = widget.timestamp;
      if (timestamp == null && widget.isHistory && widget.historySessionName != null) {
        timestamp = _extractDateFromHistoryName(widget.historySessionName!);
      }
      
      print('Using timestamp for PDF: ${timestamp?.toString() ?? 'Current time'}');
      
      // Generate the PDF file
      final pdfFile = await PdfService().generateMatchLogPdf(
        entries: logs,
        session: appState.session,
        isDarkTheme: appState.isDarkTheme,
        sessionName: sessionName,
        teamGoals: teamGoals,
        opponentGoals: opponentGoals,
        timestamp: timestamp,
      );
      
      // Hide loading indicator
      setState(() {
        _isExportingPdf = false;
      });
      
      // Navigate to the PDF preview screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(
            pdfFile: pdfFile,
            title: 'Match Log',
          ),
        ),
      );
    } catch (e) {
      // Hide loading indicator
      setState(() {
        _isExportingPdf = false;
      });
      
      print('Error exporting to PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting to PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
  
  // Update the share method to work with history logs
  void _shareMatchLog(BuildContext context, AppState appState, [List<MatchLogEntry>? customLogs]) async {
    String text;
    
    if (widget.isHistory && customLogs != null) {
      // Generate export text for history data
      final buffer = StringBuffer();
      
      // Add session name and score as header
      buffer.writeln('MATCH LOG: ${widget.historySessionName ?? "Match History"}');
      buffer.writeln('SCORE: $_teamGoals - $_opponentGoals');
      buffer.writeln('----------------------------------------');
      buffer.writeln();
      
      // Add log entries in chronological order (oldest first)
      final entries = List<MatchLogEntry>.from(customLogs)..sort((a, b) => a.seconds.compareTo(b.seconds));
      
      for (var entry in entries) {
        // Format: [Time] Event details
        if (entry.entryType?.toLowerCase() == 'period_transition') {
          // Simple emphasis for period transitions
          buffer.writeln('[${entry.matchTime}] * ${entry.details} *');
        } else {
          buffer.writeln('[${entry.matchTime}] ${entry.details}');
        }
      }
      
      text = buffer.toString();
    } else {
      // Use app state's export function for current session
      text = appState.exportMatchLogToText();
    }
    
    // Share the text
    await Share.share(text, subject: 'Soccer Time Match Log');
  }
}