import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Service class to handle snackbar notifications with identical styling and timing
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Show period end notification with identical styling and behavior
  void showPeriodEndNotification(BuildContext context, int periodNumber) {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isQuarters = appState.session.matchSegments == 4;
    final periodText = isQuarters ? 'Quarter' : 'Half';
    final ordinalPeriod = _getOrdinalNumber(periodNumber);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.sports_soccer, color: Colors.white),
            SizedBox(width: 8),
            Text('End of $ordinalPeriod $periodText!'),
          ],
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.amber.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: SnackBarAction(
          label: 'Next',
          textColor: Colors.white,
          onPressed: () {
            final appState = Provider.of<AppState>(context, listen: false);
            appState.startNextPeriod();
            // Note: Timer management would need to be handled by parent component
          },
        ),
      ),
    );
  }

  /// Show match end notification with identical styling and behavior
  void showMatchEndNotification(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.sports_score, color: Colors.white),
            SizedBox(width: 8),
            Text('Match Complete!'),
          ],
        ),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.blue.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show player added notification with consistent styling
  void showPlayerAddedNotification(BuildContext context, String playerName) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.person_add, color: Colors.white),
            SizedBox(width: 8),
            Text('$playerName added to match'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.green.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show player removed notification with consistent styling
  void showPlayerRemovedNotification(BuildContext context, String playerName) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.person_remove, color: Colors.white),
            SizedBox(width: 8),
            Text('$playerName removed from match'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.red.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show player time reset notification with consistent styling
  void showPlayerTimeResetNotification(BuildContext context, String playerName) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.refresh, color: Colors.white),
            SizedBox(width: 8),
            Text('$playerName time reset'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.orange.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show match action logged notification with consistent styling
  void showMatchActionNotification(BuildContext context, String action, String playerName) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.sports_soccer, color: Colors.white),
            SizedBox(width: 8),
            Text('$action logged for $playerName'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.blue.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show error notification with consistent styling
  void showErrorNotification(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.red.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show success notification with consistent styling
  void showSuccessNotification(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.green.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show info notification with consistent styling
  void showInfoNotification(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info, color: Colors.white),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.blue.shade700,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Helper method for ordinal numbers (1st, 2nd, 3rd, etc.)
  String _getOrdinalNumber(int number) {
    if (number == 1) return '1st';
    if (number == 2) return '2nd';
    if (number == 3) return '3rd';
    if (number >= 4 && number <= 20) return '${number}th';
    if (number % 10 == 1) return '${number}st';
    if (number % 10 == 2) return '${number}nd';
    if (number % 10 == 3) return '${number}rd';
    return '${number}th';
  }
}
