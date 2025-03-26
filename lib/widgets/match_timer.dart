import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/format_time.dart';

class MatchTimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        var session = appState.session;
        var periodDuration = session.matchDuration / session.matchSegments;
        var periodEndTime = session.currentPeriod * periodDuration;
        String displayText;
        Color textColor;
        Color containerColor;
        
        // Check for match end
        if (session.enableMatchDuration && session.matchTime >= session.matchDuration) {
          displayText = 'Match Complete';
          textColor = Colors.white;
          containerColor = Colors.amber.shade700;
        } 
        // Check for period end
        else if (session.enableMatchDuration &&
            session.matchTime >= periodEndTime.toInt() &&
            session.currentPeriod <= session.matchSegments) {
          displayText = formatTime(periodEndTime.toInt());
          textColor = Colors.white;
          containerColor = Colors.amber.shade700;
        } 
        // Regular match time
        else {
          displayText = formatTime(session.matchTime);
          // Use amber for just-started match (first 3 seconds)
          if (session.matchRunning && session.matchTime < 3) {
            textColor = Colors.white;
            containerColor = Colors.amber.shade700;
          } else {
            textColor = session.matchRunning ? Colors.green : Colors.red;
            containerColor = Colors.transparent;
          }
        }

        var progress = session.enableMatchDuration && session.matchDuration > 0
            ? (session.matchTime / session.matchDuration * 100).clamp(0, 100)
            : 0.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Background container for important events
            if (containerColor != Colors.transparent)
              Positioned.fill(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (session.enableMatchDuration)
              Positioned(
                bottom: -6,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue[300]!
                        : Colors.blue[700]!,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Match Time: ',
                  style: TextStyle(
                    fontSize: 22,
                    color: containerColor != Colors.transparent ? Colors.white : null,
                  ),
                ),
                Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                SizedBox(width: 6),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: containerColor != Colors.transparent
                          ? [Colors.amber.shade500, Colors.amber.shade700]
                          : [Colors.blue[300]!, Colors.blue[700]!],
                      stops: [0.2, 0.7],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      session.matchSegments == 2
                          ? 'H${session.currentPeriod}'
                          : 'Q${session.currentPeriod}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}