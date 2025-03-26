import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';
import '../models/match_log_entry.dart';
import '../utils/app_themes.dart';
import '../services/translation_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MatchLogScreen extends StatefulWidget {
  @override
  _MatchLogScreenState createState() => _MatchLogScreenState();
}

class _MatchLogScreenState extends State<MatchLogScreen> {
  bool _isAscendingOrder = true; // Default to ascending (match time order)
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkTheme;
    
    // Get logs based on sort order
    final logs = _isAscendingOrder 
        ? appState.session.getSortedMatchLogAscending()
        : appState.session.getSortedMatchLog();
    
    return Scaffold(
      backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
        title: Text(context.tr('log.match_log')),
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
          if (logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.share),
              tooltip: 'Share Match Log',
              onPressed: () => _shareMatchLog(context, appState),
            ),
        ],
      ),
      body: logs.isEmpty
          ? _buildEmptyState(context, isDark)
          : _buildLogList(context, logs, isDark),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? AppThemes.darkSecondaryBlue : AppThemes.lightSecondaryBlue,
        onPressed: () => Navigator.pop(context),
        child: Icon(Icons.close),
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
    final mintGreen = Color(0xFF98D7C2);
    final darkMintGreen = Color(0xFF3EAB87);
    final softCyan = Color(0xFF00BCD4);
    final softRed = Color(0xFFE57373);
    final darkRed = Color(0xFFD32F2F);
    final softAmber = Color(0xFFFFCA28);
    final darkAmber = Color(0xFFFFA000);
    
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
        final isMatchComplete = entry.details.toLowerCase().contains(context.tr('match.match_complete').toLowerCase());
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
        
        if (isMatchComplete || isMatchStart || isGoal) {
          // Match complete, start, or goal - amber
          timeContainerColor = isDark ? darkAmber.withOpacity(0.2) : softAmber.withOpacity(0.2);
          timeContainerBorderColor = isDark ? darkAmber.withOpacity(0.4) : softAmber.withOpacity(0.4);
          timeTextColor = isDark ? softAmber : darkAmber;
        } else if (isPeriodTransition) {
          // Period transitions - cyan
          timeContainerColor = isDark ? softCyan.withOpacity(0.2) : softCyan.withOpacity(0.2);
          timeContainerBorderColor = isDark ? softCyan.withOpacity(0.4) : softCyan.withOpacity(0.4);
          timeTextColor = isDark ? Colors.white : softCyan;
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
                        Colors.white,
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
                        Colors.white,
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
                        Colors.white,
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
  
  // Share the match log as text
  void _shareMatchLog(BuildContext context, AppState appState) {
    final logText = appState.exportMatchLogToText();
    
    if (logText.isNotEmpty) {
      Share.share(
        logText,
        subject: 'Match Log: ${appState.session.sessionName}',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No match events to share')),
      );
    }
  }
}