import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget class for displaying session information including player counts, goals, and match status
class SessionInfoWidget extends StatelessWidget {
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

  const SessionInfoWidget({
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

  @override
  Widget build(BuildContext context) {
    // Define the colors based on the dark theme settings
    final statusBarBackgroundColor = isDark 
        ? Colors.black38 
        : Colors.grey.shade300; // More opaque light theme background
    final statusTextColor = isDark 
        ? Colors.white70
        : Colors.black87; // Darker text for light theme

    return Container(
      margin: EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: statusBarBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Player statistics
          Row(
            children: [
              Icon(Icons.person, color: Colors.green.shade400, size: 14),
              Text(
                ' $activePlayerCount',
                style: TextStyle(
                  fontSize: 12,
                  color: statusTextColor,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.person_outline, color: Colors.red.shade400, size: 14),
              Text(
                ' $inactivePlayerCount',
                style: TextStyle(
                  fontSize: 12,
                  color: statusTextColor,
                ),
              ),
            ],
          ),
          // Score indicator
          Row(
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/images/soccerball.svg',
                    height: 14,
                    width: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '$teamGoals - $opponentGoals',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Match status and duration indicators
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Match status (setup or paused indicator)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSetup 
                    ? Colors.blue.withOpacity(0.2)
                    : (isPaused ? Colors.orange.withOpacity(0.2) : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                  border: isSetup || (isPaused && !isMatchComplete)
                    ? Border.all(
                        color: isSetup 
                          ? Colors.blue.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5),
                      )
                    : null,
                ),
                child: isSetup
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings, color: Colors.blue, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'SETUP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    )
                  : isPaused && !isMatchComplete
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause, color: Colors.orange, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'PAUSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      )
                    : SizedBox(width: 65),  // Maintain consistent width
              ),
              // Duration indicators - always show but with opacity based on enabled state
              SizedBox(width: 8),
              Opacity(
                opacity: enableTargetDuration ? 1.0 : 0.0,
                child: Row(
                  children: [
                    Icon(Icons.person_pin_circle, color: Colors.amber.shade400, size: 14),
                    SizedBox(width: 2),
                    Text(
                      _formatTime(targetPlayDuration),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Opacity(
                opacity: enableMatchDuration ? 1.0 : 0.0,
                child: Row(
                  children: [
                    Icon(Icons.timer, color: Colors.blue.shade400, size: 14),
                    SizedBox(width: 2),
                    Text(
                      _formatTime(matchDuration),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format time with identical behavior to original
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
