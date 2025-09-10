import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';
import '../screens/settings_screen.dart';
import '../services/haptic_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget class for match control buttons including play/pause, settings, reset, and exit
class MatchControlsWidget extends StatelessWidget {
  final bool isPaused;
  final bool isDark;
  final VoidCallback onPauseAll;
  final VoidCallback onResetAll;
  final VoidCallback onExitMatch;
  final VoidCallback onShowActionSelectionDialog;
  final VoidCallback onExitToSessionDialog;
  final HapticService hapticService;

  const MatchControlsWidget({
    Key? key,
    required this.isPaused,
    required this.isDark,
    required this.onPauseAll,
    required this.onResetAll,
    required this.onExitMatch,
    required this.onShowActionSelectionDialog,
    required this.onExitToSessionDialog,
    required this.hapticService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Top row buttons
            Row(
              children: [
                // Pause button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2, bottom: 4),
                    child: ElevatedButton(
                      onPressed: onPauseAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appState.session.isSetup
                          ? Colors.blue.shade600
                          : (isPaused 
                              ? Colors.green.shade600
                              : (isDark ? AppThemes.darkPauseButton : AppThemes.lightPauseButton)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.white,
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isPaused ? 16 : 15,
                          letterSpacing: 2.0,
                        ),
                        elevation: isPaused ? 8 : 2,
                        shadowColor: isPaused ? Colors.green.shade900 : Colors.black38,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            appState.session.isSetup
                              ? Icons.play_arrow
                              : (isPaused ? Icons.play_circle : Icons.pause_circle),
                            size: 20
                          ),
                          SizedBox(width: 8),
                          Text(
                            appState.session.isSetup
                              ? 'Start Match'
                              : (isPaused ? 'Resume' : 'Pause')
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Settings button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 4),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SettingsScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppThemes.darkSettingsButton : AppThemes.lightSettingsButton,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.white,
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 2.0,
                        ),
                      ),
                      child: Text('Settings'),
                    ),
                  ),
                ),
              ],
            ),
            // Reset button with confirmation
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2, bottom: 4),
                    child: ElevatedButton(
                      onPressed: () async {
                        // Add vibration pattern with the same intensity as the pause button
                        await hapticService.resetButton(context);
                        
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text(
                                'Reset Match',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              content: Text('Are you sure you want to reset all timers?'),
                              actions: [
                                TextButton(
                                  child: Text('Cancel'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                                TextButton(
                                  child: Text('Reset'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    onResetAll();
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppThemes.darkExitButton : AppThemes.lightExitButton,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.white,
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 2.0,
                        ),
                      ),
                      child: Text('Reset'),
                    ),
                  ),
                ),
                // Exit button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 4),
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text(
                                'Exit Match',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppThemes.darkText : AppThemes.lightText,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              content: Text('Are you sure you want to exit this match?'),
                              actions: [
                                TextButton(
                                  child: Text('Cancel'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                                TextButton(
                                  child: Text('Exit'),
                                  onPressed: () {
                                    Provider.of<AppState>(context, listen: false).clearCurrentSession();
                                    Navigator.of(context).pop();
                                    onExitToSessionDialog();
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.white,
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 2.0,
                        ),
                      ),
                      child: Text('Exit'),
                    ),
                  ),
                ),
              ],
            ),
            // Centered soccer ball button
            Center(
              child: GestureDetector(
                onTap: onShowActionSelectionDialog,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.grey[800] : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        spreadRadius: 5,
                        blurRadius: 15,
                        offset: Offset(0, 0),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: Offset(0, 0),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/images/soccerball.svg',
                      width: 46,
                      height: 46,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}