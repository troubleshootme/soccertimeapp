import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';
import '../widgets/period_end_dialog.dart';
import '../services/background_service.dart';
import '../services/haptic_service.dart';
import 'dart:async';

/// Service class to handle all dialog operations with identical appearance and behavior
class DialogService {
  static final DialogService _instance = DialogService._internal();
  factory DialogService() => _instance;
  DialogService._internal();

  final HapticService _hapticService = HapticService();
  final BackgroundService _backgroundService = BackgroundService();

  /// Show period end dialog with identical styling and behavior
  Future<void> showPeriodEndDialog(
    BuildContext context,
    int periodNumber, {
    bool isMatchEnd = false,
    VoidCallback? onOk,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);

    // Provide haptic feedback
    await _hapticService.periodEnd(context);

    // Show dialog with timer management
    _showManagedDialog(
      context,
      PeriodEndDialog(
        isMatchEnd: isMatchEnd,
        onOk: onOk ?? () {
          if (isMatchEnd) {
            // Handle match end
            appState.ensureMatchEndLogged();
            _backgroundService.stopReminderVibrations();
          } else {
            // Handle period end
            appState.startNextPeriod();
          }
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Show add player dialog with identical styling and behavior
  Future<void> showAddPlayerDialog(
    BuildContext context, {
    required TextEditingController textController,
    required FocusNode focusNode,
    required VoidCallback onAddPlayer,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          // Request focus when dialog is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusNode.canRequestFocus) {
              focusNode.requestFocus();
            }
          });

          return AlertDialog(
            key: UniqueKey(),
            title: Text(
              'Add Player',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                letterSpacing: 1.0,
              ),
            ),
            content: TextField(
              controller: textController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'Enter player name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
                    width: 2,
                  ),
                ),
              ),
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
                fontSize: 16,
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  onAddPlayer();
                  Navigator.of(context).pop();
                }
              },
            ),
            backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? AppThemes.darkText : AppThemes.lightText,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (textController.text.trim().isNotEmpty) {
                    onAddPlayer();
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Show player actions dialog with identical styling and behavior
  Future<void> showPlayerActionsDialog(
    BuildContext context,
    String playerName, {
    required VoidCallback onEdit,
    required VoidCallback onReset,
    required VoidCallback onRemove,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Text(
          'Player Actions',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'What would you like to do with $playerName?',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onEdit();
            },
            child: Text(
              'Edit Name',
              style: TextStyle(
                color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onReset();
            },
            child: Text(
              'Reset Time',
              style: TextStyle(
                color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRemove();
            },
            child: Text(
              'Remove Player',
              style: TextStyle(
                color: Colors.red,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show action selection dialog with identical styling and behavior
  Future<void> showActionSelectionDialog(
    BuildContext context, {
    required int actionTimestamp,
    required VoidCallback onGoal,
    required VoidCallback onAssist,
    required VoidCallback onSubstitution,
    required VoidCallback onYellowCard,
    required VoidCallback onRedCard,
    required VoidCallback onOther,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;

    // Provide haptic feedback
    await _hapticService.soccerBallButton(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        title: Row(
          children: [
            Text(
              'Match Action',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              context,
              'Goal',
              Icons.sports_soccer,
              onGoal,
              isDark,
            ),
            _buildActionButton(
              context,
              'Assist',
              Icons.handshake,
              onAssist,
              isDark,
            ),
            _buildActionButton(
              context,
              'Substitution',
              Icons.swap_horiz,
              onSubstitution,
              isDark,
            ),
            _buildActionButton(
              context,
              'Yellow Card',
              Icons.warning,
              onYellowCard,
              isDark,
            ),
            _buildActionButton(
              context,
              'Red Card',
              Icons.block,
              onRedCard,
              isDark,
            ),
            _buildActionButton(
              context,
              'Other',
              Icons.more_horiz,
              onOther,
              isDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build action button with consistent styling
  Widget _buildActionButton(
    BuildContext context,
    String text,
    IconData icon,
    VoidCallback onPressed,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onPressed();
          },
          icon: Icon(icon),
          label: Text(text),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  /// Show edit player dialog with identical styling and behavior
  Future<void> showEditPlayerDialog(
    BuildContext context,
    String playerName, {
    required TextEditingController textController,
    required VoidCallback onSave,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Edit Player',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            letterSpacing: 1.0,
          ),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Player Name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
                width: 2,
              ),
            ),
          ),
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            fontSize: 16,
          ),
        ),
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.trim().isNotEmpty && textController.text.trim() != playerName) {
                onSave();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
              foregroundColor: Colors.white,
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Show remove player confirmation dialog with identical styling and behavior
  Future<void> showRemovePlayerConfirmation(
    BuildContext context,
    String playerName, {
    required VoidCallback onRemove,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove Player',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            letterSpacing: 0.5,
          ),
        ),
        content: Text('Are you sure you want to remove $playerName?'),
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              onRemove();
              Navigator.pop(context);
            },
            child: Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Show add player warning dialog with identical styling and behavior
  Future<void> showAddPlayerWarningDialog(
    BuildContext context, {
    required VoidCallback onProceed,
  }) async {
    if (!context.mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final isDark = appState.isDarkTheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Add Player During Match',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          'Adding a player during a running match will pause the timer. Do you want to continue?',
          style: TextStyle(
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
            fontSize: 16,
          ),
        ),
        backgroundColor: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppThemes.darkText : AppThemes.lightText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              onProceed();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
              foregroundColor: Colors.white,
            ),
            child: Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Helper method to show dialogs with timer management
  void _showManagedDialog(BuildContext context, Widget dialog) {
    // Ensure timers aren't destroyed when showing a dialog
    final wasRunning = _backgroundService.isTimerActive();
    
    // Create a new temporary timer to keep checking time updates
    // even when a dialog is shown
    Timer? dialogTimer;
    if (wasRunning) {
      dialogTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
        // Keep UI in sync with background timer
        // This would need to be handled by the parent component
      });
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => dialog,
    ).then((_) {
      // Clean up temporary timer
      dialogTimer?.cancel();
    });
  }
}
