import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soccertimeapp/widgets/match_time_display_widget.dart';
import 'package:soccertimeapp/providers/app_state.dart';

void main() {
  group('MatchTimeDisplayWidget', () {
    late AppState appState;
    late ValueNotifier<int> matchTimeNotifier;

    setUp(() {
      appState = AppState();
      matchTimeNotifier = ValueNotifier<int>(0);
    });

    tearDown(() {
      matchTimeNotifier.dispose();
    });

    Widget createTestWidget({
      required bool isPaused,
      required bool isDark,
      required bool Function() hasActivePlayer,
      required String sessionName,
    }) {
      return MaterialApp(
        home: ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: Scaffold(
            body: MatchTimeDisplayWidget(
              matchTimeNotifier: matchTimeNotifier,
              isPaused: isPaused,
              isDark: isDark,
              hasActivePlayer: hasActivePlayer,
              sessionName: sessionName,
            ),
          ),
        ),
      );
    }

    testWidgets('displays session name correctly', (WidgetTester tester) async {
      const sessionName = 'Test Session';
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: sessionName,
      ));

      expect(find.text(sessionName), findsOneWidget);
    });

    testWidgets('displays read-only indicator when in read-only mode', (WidgetTester tester) async {
      // Note: isReadOnlyMode is a getter, not a setter, so we can't test this directly
      // This test would need to be updated when the AppState implementation is available
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      expect(find.text('Read-Only'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('displays match time correctly', (WidgetTester tester) async {
      matchTimeNotifier.value = 125; // 2:05
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      expect(find.text('02:05'), findsOneWidget);
    });

    testWidgets('displays correct timer color for different states', (WidgetTester tester) async {
      // Test setup mode
      appState.session.isSetup = true;
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      final timerText = find.text('00:00');
      expect(timerText, findsOneWidget);
      
      // Verify the text widget has the correct color
      final textWidget = tester.widget<Text>(timerText);
      expect(textWidget.style?.color, Colors.blue);
    });

    testWidgets('displays period indicator when match duration is enabled', (WidgetTester tester) async {
      appState.session.enableMatchDuration = true;
      appState.session.matchSegments = 2;
      appState.session.currentPeriod = 1;
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      expect(find.text('H1'), findsOneWidget);
    });

    testWidgets('displays quarters period indicator correctly', (WidgetTester tester) async {
      appState.session.enableMatchDuration = true;
      appState.session.matchSegments = 4;
      appState.session.currentPeriod = 2;
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      expect(find.text('Q2'), findsOneWidget);
    });

    testWidgets('displays match duration progress bar when enabled', (WidgetTester tester) async {
      appState.session.enableMatchDuration = true;
      appState.session.matchDuration = 3600; // 1 hour
      matchTimeNotifier.value = 1800; // 30 minutes
      
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test Session',
      ));

      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });

    testWidgets('formats time correctly', (WidgetTester tester) async {
      // Test the private _formatTime method through the widget
      matchTimeNotifier.value = 0;
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test',
      ));
      expect(find.text('00:00'), findsOneWidget);

      matchTimeNotifier.value = 65;
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test',
      ));
      expect(find.text('01:05'), findsOneWidget);

      matchTimeNotifier.value = 3661;
      await tester.pumpWidget(createTestWidget(
        isPaused: false,
        isDark: false,
        hasActivePlayer: () => true,
        sessionName: 'Test',
      ));
      expect(find.text('61:01'), findsOneWidget);
    });
  });
}
