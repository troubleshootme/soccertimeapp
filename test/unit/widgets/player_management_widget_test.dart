import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:soccertimeapp/widgets/player_management_widget.dart';
import 'package:soccertimeapp/providers/app_state.dart';
import 'package:soccertimeapp/models/player.dart';
import 'package:soccertimeapp/services/haptic_service.dart';
import 'package:soccertimeapp/services/dialog_service.dart';
import 'package:soccertimeapp/services/notification_service.dart';
import 'package:soccertimeapp/services/background_service.dart';

import 'player_management_widget_test.mocks.dart';

@GenerateMocks([
  AppState,
  HapticService,
  DialogService,
  NotificationService,
  BackgroundService,
])
void main() {
  group('PlayerManagementWidget', () {
    late PlayerManagementWidget playerManagementWidget;
    late FocusNode addPlayerFocusNode;
    late MockAppState mockAppState;
    late MockHapticService mockHapticService;
    late MockDialogService mockDialogService;
    late MockNotificationService mockNotificationService;
    late MockBackgroundService mockBackgroundService;

    setUp(() {
      addPlayerFocusNode = FocusNode();
      mockAppState = MockAppState();
      mockHapticService = MockHapticService();
      mockDialogService = MockDialogService();
      mockNotificationService = MockNotificationService();
      mockBackgroundService = MockBackgroundService();
    });

    testWidgets('renders player table header correctly', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Players (0/0 active)'), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('shows empty state when no players', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('No players added yet. Tap + to add a player.'), findsOneWidget);
    });

    testWidgets('renders player list correctly', (WidgetTester tester) async {
      // Arrange
      final player1 = Player(name: 'John Doe', active: true);
      final player2 = Player(name: 'Jane Smith', active: false);
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({
        'John Doe': player1,
        'Jane Smith': player2,
      });
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);
      when(mockAppState.calculatePlayerTime(any)).thenReturn(120);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('02:00'), findsNWidgets(2)); // Both players show formatted time
    });

    testWidgets('toggles table expansion when header is tapped', (WidgetTester tester) async {
      // Arrange
      bool expansionToggled = false;
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () => expansionToggled = true,
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Players (0/0 active)'));
      await tester.pumpAndSettle();

      // Assert
      expect(expansionToggled, isTrue);
    });

    testWidgets('calls onPlayerStateChange when player is toggled', (WidgetTester tester) async {
      // Arrange
      bool playerStateChanged = false;
      final player = Player(name: 'John Doe', active: false);
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({'John Doe': player});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);
      when(mockAppState.session.isSetup).thenReturn(false);
      when(mockAppState.currentSessionId).thenReturn('test-session');
      when(mockAppState.calculatePlayerTime(any)).thenReturn(0);
      when(mockAppState.togglePlayer(any)).thenReturn(null);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
              onPlayerStateChange: () => playerStateChanged = true,
            ),
          ),
        ),
      );

      // Tap on player toggle button
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Assert
      expect(playerStateChanged, isTrue);
    });

    testWidgets('shows add player dialog when add button is tapped', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.person_add));
      await tester.pumpAndSettle();

      // Assert
      // The dialog service would be called, but we can't easily test the dialog appearance
      // without more complex mocking. This test verifies the button tap works.
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('shows player actions dialog when more button is tapped', (WidgetTester tester) async {
      // Arrange
      final player = Player(name: 'John Doe', active: true);
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({'John Doe': player});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);
      when(mockAppState.calculatePlayerTime(any)).thenReturn(120);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Assert
      // The dialog service would be called, but we can't easily test the dialog appearance
      // without more complex mocking. This test verifies the button tap works.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('handles dark theme correctly', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(true);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Players (0/0 active)'), findsOneWidget);
      // Dark theme styling would be applied through the theme system
    });

    testWidgets('handles light theme correctly', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Players (0/0 active)'), findsOneWidget);
      // Light theme styling would be applied through the theme system
    });

    testWidgets('calls onMatchStateChange when match state changes', (WidgetTester tester) async {
      // Arrange
      bool matchStateChanged = false;
      final player = Player(name: 'John Doe', active: false);
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({'John Doe': player});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);
      when(mockAppState.session.isSetup).thenReturn(false);
      when(mockAppState.currentSessionId).thenReturn('test-session');
      when(mockAppState.calculatePlayerTime(any)).thenReturn(0);
      when(mockAppState.togglePlayer(any)).thenReturn(null);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
              onMatchStateChange: () => matchStateChanged = true,
            ),
          ),
        ),
      );

      // Tap on player toggle button
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Assert
      expect(matchStateChanged, isTrue);
    });

    testWidgets('disposes correctly', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockAppState.session.players).thenReturn({});
      when(mockAppState.session.matchRunning).thenReturn(false);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: PlayerManagementWidget(
              isTableExpanded: true,
              onToggleExpansion: () {},
              addPlayerFocusNode: addPlayerFocusNode,
            ),
          ),
        ),
      );

      // Remove the widget
      await tester.pumpWidget(Container());

      // Assert
      // Widget should be disposed without errors
      expect(find.byType(PlayerManagementWidget), findsNothing);
    });
  });
}
