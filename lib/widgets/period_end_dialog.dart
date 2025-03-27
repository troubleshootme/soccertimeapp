import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PeriodEndDialog extends StatelessWidget {
  // Add callback for next period transition
  final VoidCallback? onNextPeriod;
  
  // Remove const constructor to avoid widget identity issues
  PeriodEndDialog({Key? key, this.onNextPeriod}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    try {
      final appState = Provider.of<AppState>(context, listen: false); // Use listen: false to prevent unnecessary rebuilds
      final currentPeriod = appState.session.currentPeriod;
      final totalPeriods = appState.session.matchSegments;
      final isGameOver = currentPeriod >= totalPeriods;
      
      // Determine period name (Quarter/Half)
      final periodName = totalPeriods == 2 ? 'Half' : 'Quarter';
      final currentOrdinal = _getOrdinalNumber(currentPeriod);
      final nextOrdinal = _getOrdinalNumber(currentPeriod + 1);

      // Get the score for match complete screen
      final teamGoals = appState.session.teamGoals;
      final opponentGoals = appState.session.opponentGoals;
      final teamName = appState.session.sessionName;

      return PopScope(
        canPop: isGameOver,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            appState.saveSession();
          }
        },
        child: AlertDialog(
          title: Text(
            isGameOver ? 'Match Complete!' : '$currentOrdinal $periodName Ended',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ), 
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show score when game is over
              if (isGameOver)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/images/soccerball.svg',
                            height: 24,
                            width: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Final Score',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey.shade800 
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              teamName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              '$teamGoals - $opponentGoals',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Opp',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            if (!isGameOver)
              ElevatedButton(
                onPressed: () {
                  try {
                    // Use the callback instead of direct state manipulation
                    if (onNextPeriod != null) {
                      onNextPeriod!();
                    } else {
                      // Fallback to previous behavior if no callback
                      final appStateForAction = Provider.of<AppState>(context, listen: false);
                      appStateForAction.startNextPeriod();
                      Navigator.of(context).pop();
                    }
                  } catch (e) {
                    print('Error starting next period: $e');
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text('Start $nextOrdinal $periodName',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,  
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            if (isGameOver) // Only show OK button if game is over
              ElevatedButton(
                onPressed: () {
                  // Just dismiss the dialog, main screen will handle state
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 60, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text('OK',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      print('Error in PeriodEndDialog build: $e');
      // Return a simple dialog if build fails
      return AlertDialog(
        title: Text('Period Ended'),
        content: Text('Please close this dialog and restart the app if you see issues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      );
    }
  }
  
  // Helper method to convert number to ordinal (1st, 2nd, etc.)
  String _getOrdinalNumber(int number) {
    if (number <= 0) return "0";
    
    switch (number) {
      case 1:
        return "1st";
      case 2:
        return "2nd";
      case 3:
        return "3rd";
      default:
        return "${number}th";
    }
  }
}