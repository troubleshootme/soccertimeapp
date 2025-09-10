import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_themes.dart';
import '../models/player.dart';
import '../services/haptic_service.dart';
import '../services/dialog_service.dart';
import '../services/notification_service.dart';
import '../services/background_service.dart';

/// Widget class to handle all player management functionality
class PlayerManagementWidget extends StatefulWidget {
  final bool isTableExpanded;
  final VoidCallback onToggleExpansion;
  final FocusNode addPlayerFocusNode;
  final VoidCallback? onPlayerStateChange;
  final VoidCallback? onMatchStateChange;

  const PlayerManagementWidget({
    Key? key,
    required this.isTableExpanded,
    required this.onToggleExpansion,
    required this.addPlayerFocusNode,
    this.onPlayerStateChange,
    this.onMatchStateChange,
  }) : super(key: key);

  @override
  _PlayerManagementWidgetState createState() => _PlayerManagementWidgetState();
}

class _PlayerManagementWidgetState extends State<PlayerManagementWidget> {
  // Services
  final HapticService _hapticService = HapticService();
  final DialogService _dialogService = DialogService();
  final NotificationService _notificationService = NotificationService();
  final BackgroundService _backgroundService = BackgroundService();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          children: [
            // Player table header with expansion toggle
            _buildPlayerTableHeader(context, appState),
            
            // Player table (expanded/collapsed)
            if (widget.isTableExpanded) _buildPlayerTable(context, appState),
          ],
        );
      },
    );
  }

  /// Build the player table header with expansion toggle
  Widget _buildPlayerTableHeader(BuildContext context, AppState appState) {
    final isDark = appState.isDarkTheme;
    final activePlayerCount = appState.session.players.values.where((p) => p.active).length;
    final totalPlayerCount = appState.session.players.length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          widget.isTableExpanded ? Icons.expand_less : Icons.expand_more,
          color: isDark ? AppThemes.darkText : AppThemes.lightText,
        ),
        title: Text(
          'Players ($activePlayerCount/$totalPlayerCount active)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.person_add,
            color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
          ),
          onPressed: () => _showAddPlayerDialog(context),
        ),
        onTap: widget.onToggleExpansion,
      ),
    );
  }

  /// Build the player table
  Widget _buildPlayerTable(BuildContext context, AppState appState) {
    final isDark = appState.isDarkTheme;
    final players = appState.session.players.values.toList();

    if (players.isEmpty) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No players added yet. Tap + to add a player.',
            style: TextStyle(
              color: isDark ? AppThemes.darkText : AppThemes.lightText,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppThemes.darkCardBackground : AppThemes.lightCardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: players.map((player) => _buildPlayerRow(context, appState, player)).toList(),
      ),
    );
  }

  /// Build a single player row
  Widget _buildPlayerRow(BuildContext context, AppState appState, Player player) {
    final isDark = appState.isDarkTheme;
    final playerTime = _calculatePlayerTime(player, appState);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _togglePlayerByName(player.name),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: player.active 
                ? (isDark ? AppThemes.darkGreen : AppThemes.lightGreen)
                : (isDark ? Colors.grey[600] : Colors.grey[400]),
              shape: BoxShape.circle,
            ),
            child: Icon(
              player.active ? Icons.person : Icons.person_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        title: Text(
          player.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: player.active ? FontWeight.bold : FontWeight.normal,
            color: player.active 
              ? (isDark ? AppThemes.darkText : AppThemes.lightText)
              : (isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ),
        subtitle: Text(
          _formatTime(playerTime),
          style: TextStyle(
            fontSize: 14,
            color: player.active 
              ? (isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue)
              : (isDark ? Colors.grey[500] : Colors.grey[500]),
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.more_vert,
            color: isDark ? AppThemes.darkText : AppThemes.lightText,
          ),
          onPressed: () => _showPlayerActionsDialog(context, player.name),
        ),
      ),
    );
  }

  /// Show add player dialog with identical behavior to original
  void _showAddPlayerDialog(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    // Check if match is running and not paused
    if (appState.session.matchRunning && !appState.session.isPaused) {
      _showAddPlayerWarningDialog(context);
      return;
    }

    // If match is not running or already paused, show add player dialog directly
    _showActualAddPlayerDialog(context);
  }

  /// Show warning dialog for adding player during running match
  void _showAddPlayerWarningDialog(BuildContext context) {
    _dialogService.showAddPlayerWarningDialog(
      context,
      onProceed: () => _showActualAddPlayerDialog(context),
    );
  }

  /// Show the actual add player dialog
  void _showActualAddPlayerDialog(BuildContext context) {
    final textController = TextEditingController();
    final appState = Provider.of<AppState>(context, listen: false);

    // Pause the timer while dialog is open to prevent state updates
    final wasRunning = appState.session.matchRunning && !appState.session.isPaused;
    if (wasRunning) {
      _pauseAll();
    }

    _dialogService.showAddPlayerDialog(
      context,
      textController: textController,
      focusNode: widget.addPlayerFocusNode,
      onAddPlayer: () async {
        if (textController.text.trim().isNotEmpty) {
          try {
            await appState.addPlayer(textController.text.trim());
            _notificationService.showPlayerAddedNotification(context, textController.text.trim());
            widget.onPlayerStateChange?.call();
          } catch (e) {
            print('Error adding player: $e');
            _notificationService.showErrorNotification(context, 'Could not add player: $e');
          }
        }
      },
    );
    
    // Clean up the controller AFTER the dialog is closed
    Future.delayed(Duration(milliseconds: 50), () {
      textController.dispose();
    });
  }

  /// Toggle player by name with identical behavior to original
  void _togglePlayerByName(String playerName) async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.currentSessionId == null) return;

    // Provide haptic feedback without awaiting
    _hapticService.playerToggle(context);

    // CRITICAL FIX: Check if match is already running but not in setup mode
    final isMatchRunning = appState.session.matchRunning && !appState.session.isPaused && !appState.session.isSetup;
    final wasPlayerActive = appState.session.players[playerName]?.active ?? false;
    
    // Toggle player state
    appState.togglePlayer(playerName);

    // If we activated a player during a running match, make sure the UI knows the match is running
    if (isMatchRunning && !wasPlayerActive) {
      // Force UI refresh to show active time immediately
      setState(() {});
      
      // Ensure background service is aware of player change
      if (_backgroundService.isRunning) {
        _backgroundService.syncAppState(appState);
      }
    }

    // Only start the match timer if we're not paused and not in setup mode
    if (!appState.session.isPaused && !appState.session.isSetup) {
      // Check if we have any active players
      if (_hasActivePlayer()) {
        // Start the match if it's not already running
        if (!appState.session.matchRunning) {
          appState.session.matchRunning = true;
          widget.onMatchStateChange?.call();
        }
      } else {
        // No active players, stop the match
        if (appState.session.matchRunning) {
          appState.session.matchRunning = false;
          widget.onMatchStateChange?.call();
        }
      }
    }

    // Notify parent of player state change
    widget.onPlayerStateChange?.call();
  }

  /// Show player actions dialog with identical behavior to original
  void _showPlayerActionsDialog(BuildContext context, String playerName) {
    _dialogService.showPlayerActionsDialog(
      context,
      playerName,
      onEdit: () => _showEditPlayerDialog(context, '', playerName),
      onReset: () => _resetPlayerTime(playerName),
      onRemove: () => _showRemovePlayerConfirmation(playerName),
    );
  }

  /// Show edit player dialog with identical behavior to original
  void _showEditPlayerDialog(BuildContext context, String playerId, String playerName) {
    final textController = TextEditingController(text: playerName);
    final appState = Provider.of<AppState>(context, listen: false);
    
    _dialogService.showEditPlayerDialog(
      context,
      playerName,
      textController: textController,
      onSave: () async {
        if (textController.text.trim().isNotEmpty && textController.text.trim() != playerName) {
          try {
            await appState.renamePlayer(playerName, textController.text.trim());
            _notificationService.showSuccessNotification(context, 'Player renamed to ${textController.text.trim()}');
            widget.onPlayerStateChange?.call();
          } catch (e) {
            _notificationService.showErrorNotification(context, 'Could not rename player: $e');
          }
        }
      },
    );
  }

  /// Show remove player confirmation dialog with identical behavior to original
  void _showRemovePlayerConfirmation(String playerName) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    _dialogService.showRemovePlayerConfirmation(
      context,
      playerName,
      onRemove: () {
        appState.removePlayer(playerName);
        _notificationService.showPlayerRemovedNotification(context, playerName);
        widget.onPlayerStateChange?.call();
      },
    );
  }

  /// Reset player time with identical behavior to original
  void _resetPlayerTime(String playerName) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Deactivate player if active
    if (appState.session.players[playerName]?.active ?? false) {
      appState.togglePlayer(playerName);
    }
    
    // Reset player time
    appState.resetPlayerTime(playerName);
    
    // Show confirmation
    _notificationService.showPlayerTimeResetNotification(context, playerName);
    
    // Notify parent of player state change
    widget.onPlayerStateChange?.call();
  }

  /// Check if there are any active players
  bool _hasActivePlayer() {
    final appState = Provider.of<AppState>(context, listen: false);
    for (var playerName in appState.session.players.keys) {
      if (appState.session.players[playerName]!.active) {
        return true;
      }
    }
    return false;
  }

  /// Calculate player time with identical behavior to original
  int _calculatePlayerTime(Player? player, AppState appState) {
    if (player == null) return 0;
    return appState.calculatePlayerTime(player);
  }

  /// Format time with identical behavior to original
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Pause all timers (helper method for dialog management)
  void _pauseAll() {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.session.matchRunning && !appState.session.isPaused) {
      appState.session.isPaused = true;
      widget.onMatchStateChange?.call();
    }
  }
}
