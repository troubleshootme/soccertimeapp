import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Widget class for displaying match time with proper formatting and styling
class MatchTimeDisplayWidget extends StatelessWidget {
  final ValueNotifier<int> matchTimeNotifier;
  final bool isPaused;
  final bool isDark;
  final bool Function() hasActivePlayer;
  final String sessionName;

  const MatchTimeDisplayWidget({
    Key? key,
    required this.matchTimeNotifier,
    required this.isPaused,
    required this.isDark,
    required this.hasActivePlayer,
    required this.sessionName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
              // Dark theme colors (keep existing logic)
              ? (appState.session.isSetup
                  ? Colors.blueGrey.shade900.withOpacity(0.5)
                  : (appState.session.isMatchComplete
                      ? Colors.red.shade900.withOpacity(0.5)
                      : (isPaused
                          ? Colors.orange.shade900.withOpacity(0.5)
                          : Colors.black38)))
              // Light theme: Use eggshell color
              : const Color(0xFFFAF0E6), // Eggshell color for light theme
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                // Dark theme border colors (keep existing logic)
                ? (appState.session.isSetup
                    ? Colors.blueGrey.shade600
                    : (appState.session.isMatchComplete
                        ? Colors.red.shade600
                        : (isPaused
                            ? Colors.orange.shade600
                            : Colors.grey.shade700)))
                // Light theme border colors (keep existing logic)
                : (appState.session.isSetup
                    ? Colors.blueGrey.shade300
                    : (appState.session.isMatchComplete
                        ? Colors.red.shade300
                        : (isPaused
                            ? Colors.orange.shade300
                            : Colors.grey.shade400))),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              // Session Name display
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  sessionName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.lightBlue,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              
              // Read-only mode indicator
              if (appState.isReadOnlyMode)
                Padding(
                  padding: const EdgeInsets.only(left: 3.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 9,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 1),
                      Text(
                        'Read-Only',
                        style: TextStyle(
                          fontSize: 8,
                          fontStyle: FontStyle.italic,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Stack to separate timer centering and period positioning
              Stack(
                alignment: Alignment.center,
                children: [
                  // Center the match timer independently
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 0, bottom: 0),
                      child: ValueListenableBuilder<int>(
                        valueListenable: matchTimeNotifier,
                        builder: (context, time, child) {
                          return Text(
                            _formatTime(time),
                            style: TextStyle(
                              fontSize: 46,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'RobotoMono',
                              color: appState.session.isSetup
                                ? Colors.blue  // Blue in setup mode
                                : (isPaused 
                                    ? Colors.orange.shade600  // Orange when paused
                                    : (hasActivePlayer() 
                                        ? Colors.green  // Green when running
                                        : Colors.red)),  // Red when stopped
                              letterSpacing: 2.0,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // Position the period indicator to the right of the timer
                  Positioned(
                    left: MediaQuery.of(context).size.width / 2 + 64,
                    top: 4,
                    child: appState.session.enableMatchDuration ? Padding(
                      padding: EdgeInsets.all(6),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.lightBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          appState.session.matchSegments == 2 
                            ? 'H${appState.session.currentPeriod}' 
                            : 'Q${appState.session.currentPeriod}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ) : SizedBox.shrink(),
                  ),
                ],
              ),
              
              // Match duration progress bar
              if (appState.session.enableMatchDuration)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    height: 6,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isDark ? Colors.black38 : Colors.grey.shade300,
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ((matchTimeNotifier.value) / appState.session.matchDuration).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(
                            colors: [Colors.lightBlueAccent, Colors.blueAccent],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Format time with identical behavior to original
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
