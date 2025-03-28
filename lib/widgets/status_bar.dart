import 'package:flutter/material.dart';
import '../utils/app_themes.dart'; // Assuming theme constants are here

class StatusBar extends StatelessWidget {
  final bool isDark;
  final int activePlayerCount;
  final int inactivePlayerCount;
  final int teamGoals;
  final int opponentGoals;
  final bool isPaused;
  final bool isMatchComplete;
  final bool isSetup;
  final bool enableTargetDuration;
  final bool enableMatchDuration;
  final int targetPlayDuration;
  final int matchDuration;
  const StatusBar({
    Key? key,
    required this.isDark,
    required this.activePlayerCount,
    required this.inactivePlayerCount,
    required this.teamGoals,
    required this.opponentGoals,
    required this.isPaused,
    required this.isMatchComplete,
    required this.isSetup,
    required this.enableTargetDuration,
    required this.enableMatchDuration,
    required this.targetPlayDuration,
    required this.matchDuration,
  }) : super(key: key);

  // Helper to format time (moved here for encapsulation)
  String _formatTime(int seconds) {
    if (seconds < 0) seconds = 0;
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Define theme-aware colors
    final Color backgroundColor = isDark
        ? Colors.black38                 // Dark theme background
        : Colors.grey.shade300;          // Light theme background (opaque)
    final Color textColor = isDark
        ? Colors.white70                 // Dark theme text
        : Colors.black87;                // Light theme text (darker)
    final Color activeColor = Colors.green.shade400;
    final Color inactiveColor = Colors.red.shade400;
    final Color goalColor = isDark ? Colors.white : Colors.black; // Simpler goal color based on theme
    final Color setupColor = Colors.blue.withOpacity(0.7);
    final Color pausedColor = Colors.orange.withOpacity(0.7);

    // Build status indicators (moved logic here)
    List<Widget> statusIndicators = [];
    if (isSetup) {
      statusIndicators.add(
        _buildStatusChip(
          'Setup',
          setupColor.withOpacity(0.2),
          setupColor.withOpacity(0.5),
          textColor
        )
      );
    } else if (isPaused && !isMatchComplete) {
       statusIndicators.add(
         _buildStatusChip(
          'Paused',
          pausedColor.withOpacity(0.2),
          pausedColor.withOpacity(0.5),
          textColor
        )
      );
    }

    if (enableMatchDuration && !isSetup) {
       statusIndicators.add(
         Padding(
           padding: const EdgeInsets.only(left: 4.0),
           child: Row(
              children: [
                Icon(Icons.timer, size: 12, color: textColor),
                const SizedBox(width: 2),
                Text(
                  _formatTime(matchDuration),
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
              ],
            ),
         )
       );
    }

     if (enableTargetDuration && !isSetup) {
        statusIndicators.add(
         Padding(
           padding: const EdgeInsets.only(left: 4.0),
           child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 12, color: textColor),
                const SizedBox(width: 2),
                Text(
                  _formatTime(targetPlayDuration),
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
              ],
            ),
         )
       );
    }


    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Adjusted padding slightly
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8), // Increased radius slightly
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Player counts
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person, color: activeColor, size: 16),
              Text(
                ' $activePlayerCount',
                style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Icon(Icons.person_outline, color: inactiveColor, size: 16),
              Text(
                ' $inactivePlayerCount',
                 style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
              ),
            ],
          ),

          // Center: Status indicators (Setup/Paused, Durations)
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4.0, // Spacing between chips/icons
              runSpacing: 2.0,
              children: statusIndicators,
            ),
          ),


          // Right side: Score
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
               // Display score only if not in setup mode
              if (!isSetup) ...[
                Icon(Icons.scoreboard_outlined, size: 16, color: goalColor),
                const SizedBox(width: 4),
                Text(
                  '$teamGoals - $opponentGoals',
                   style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.bold),
                ),
              ] else ... [
                 // Placeholder or empty space during setup if needed
                 SizedBox(width: 1) // Ensures layout consistency
              ]
            ],
          ),
        ],
      ),
    );
  }

  // Helper widget for status chips (like Setup, Paused)
  Widget _buildStatusChip(String label, Color bgColor, Color borderColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
      ),
    );
  }
} 