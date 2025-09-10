import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soccertimeapp/widgets/session_info_widget.dart';

void main() {
  group('SessionInfoWidget', () {
    Widget createTestWidget({
      required bool isDark,
      required int activePlayerCount,
      required int inactivePlayerCount,
      required int teamGoals,
      required int opponentGoals,
      required bool isPaused,
      required bool isMatchComplete,
      required bool isSetup,
      required bool enableTargetDuration,
      required bool enableMatchDuration,
      required int targetPlayDuration,
      required int matchDuration,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SessionInfoWidget(
            isDark: isDark,
            activePlayerCount: activePlayerCount,
            inactivePlayerCount: inactivePlayerCount,
            teamGoals: teamGoals,
            opponentGoals: opponentGoals,
            isPaused: isPaused,
            isMatchComplete: isMatchComplete,
            isSetup: isSetup,
            enableTargetDuration: enableTargetDuration,
            enableMatchDuration: enableMatchDuration,
            targetPlayDuration: targetPlayDuration,
            matchDuration: matchDuration,
          ),
        ),
      );
    }

    testWidgets('displays player counts correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 5,
        inactivePlayerCount: 3,
        teamGoals: 2,
        opponentGoals: 1,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));

      expect(find.text('5'), findsOneWidget); // Active players
      expect(find.text('3'), findsOneWidget); // Inactive players
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('displays goals correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 3,
        opponentGoals: 2,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));

      expect(find.text('3 - 2'), findsOneWidget);
    });

    testWidgets('displays setup status correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: true,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));

      expect(find.text('SETUP'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('displays paused status correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: true,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('displays target duration when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: true,
        enableMatchDuration: false,
        targetPlayDuration: 1800, // 30 minutes
        matchDuration: 0,
      ));

      expect(find.text('30:00'), findsOneWidget);
      expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
    });

    testWidgets('displays match duration when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: true,
        targetPlayDuration: 0,
        matchDuration: 3600, // 1 hour
      ));

      expect(find.text('60:00'), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);
    });

    testWidgets('hides duration indicators when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 1800,
        matchDuration: 3600,
      ));

      // Duration indicators should be present but with opacity 0
      expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);
    });

    testWidgets('formats time correctly', (WidgetTester tester) async {
      // Test the private _formatTime method through the widget
      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: true,
        enableMatchDuration: true,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));
      expect(find.text('00:00'), findsNWidgets(2)); // Both durations

      await tester.pumpWidget(createTestWidget(
        isDark: false,
        activePlayerCount: 0,
        inactivePlayerCount: 0,
        teamGoals: 0,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: true,
        enableMatchDuration: true,
        targetPlayDuration: 65,
        matchDuration: 3661,
      ));
      expect(find.text('01:05'), findsOneWidget); // Target duration
      expect(find.text('61:01'), findsOneWidget); // Match duration
    });

    testWidgets('applies correct styling for dark theme', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        isDark: true,
        activePlayerCount: 2,
        inactivePlayerCount: 1,
        teamGoals: 1,
        opponentGoals: 0,
        isPaused: false,
        isMatchComplete: false,
        isSetup: false,
        enableTargetDuration: false,
        enableMatchDuration: false,
        targetPlayDuration: 0,
        matchDuration: 0,
      ));

      // The widget should render without errors in dark theme
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2)); // Inactive players and team goals
      expect(find.text('1 - 0'), findsOneWidget);
    });
  });
}
