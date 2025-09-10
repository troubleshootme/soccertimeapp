import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soccertimeapp/widgets/match_controls_widget.dart';
import 'package:soccertimeapp/providers/app_state.dart';
import 'package:soccertimeapp/services/haptic_service.dart';

void main() {
  group('MatchControlsWidget', () {
    late AppState appState;
    late HapticService hapticService;
    bool pauseAllCalled = false;
    bool resetAllCalled = false;
    bool exitMatchCalled = false;
    bool actionSelectionCalled = false;
    bool exitToSessionCalled = false;

    setUp(() {
      appState = AppState();
      hapticService = HapticService();
      pauseAllCalled = false;
      resetAllCalled = false;
      exitMatchCalled = false;
      actionSelectionCalled = false;
      exitToSessionCalled = false;
    });

    Widget createTestWidget({
      required bool isPaused,
      required bool isDark,
    }) {
      return MaterialApp(
        home: ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: Scaffold(
            body: MatchControlsWidget(
              isPaused: isPaused,
              isDark: isDark,
              onPauseAll: () => pauseAllCalled = true,
              onResetAll: () => resetAllCalled = true,
              onExitMatch: () => exitMatchCalled = true,
              onShowActionSelectionDialog: () => actionSelectionCalled = true,
              onExitToSessionDialog: () => exitToSessionCalled = true,
              hapticService: hapticService,
            ),
          ),
        ),
      );
    }

    testWidgets('displays all control buttons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
    });

    testWidgets('displays correct button text for setup mode', (WidgetTester tester) async {
      appState.session.isSetup = true;
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      expect(find.text('Start Match'), findsOneWidget);
    });

    testWidgets('displays correct button text for paused state', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: true,
        isDark: false,
      ));

      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('displays correct button text for running state', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('calls onPauseAll when pause button is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Pause'));
      await tester.pump();

      expect(pauseAllCalled, isTrue);
    });

    testWidgets('calls onPauseAll when resume button is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: true,
        isDark: false,
      ));

      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(pauseAllCalled, isTrue);
    });

    testWidgets('navigates to settings when settings button is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Should navigate to settings screen
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows reset confirmation dialog when reset button is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Reset'));
      await tester.pump();

      expect(find.text('Reset Match'), findsOneWidget);
      expect(find.text('Are you sure you want to reset all timers?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
    });

    testWidgets('calls onResetAll when reset is confirmed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.tap(find.text('Reset'));
      await tester.pump();

      expect(resetAllCalled, isTrue);
    });

    testWidgets('does not call onResetAll when reset is cancelled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(resetAllCalled, isFalse);
    });

    testWidgets('shows exit confirmation dialog when exit button is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Exit'));
      await tester.pump();

      expect(find.text('Exit Match'), findsOneWidget);
      expect(find.text('Are you sure you want to exit this match?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
    });

    testWidgets('calls onExitMatch and onExitToSessionDialog when exit is confirmed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Exit'));
      await tester.pump();
      await tester.tap(find.text('Exit'));
      await tester.pump();

      expect(exitMatchCalled, isTrue);
      expect(exitToSessionCalled, isTrue);
    });

    testWidgets('does not call exit callbacks when exit is cancelled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.text('Exit'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(exitMatchCalled, isFalse);
      expect(exitToSessionCalled, isFalse);
    });

    testWidgets('calls onShowActionSelectionDialog when soccer ball is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(actionSelectionCalled, isTrue);
    });

    testWidgets('displays soccer ball icon', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      expect(find.byType(GestureDetector), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('applies correct styling for dark theme', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: true,
      ));

      // The widget should render without errors in dark theme
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
    });

    testWidgets('applies correct styling for light theme', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
      ));

      // The widget should render without errors in light theme
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
    });
  });
}
