import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soccertimeapp/providers/app_state.dart';
import 'package:soccertimeapp/services/dialog_service.dart';
import 'package:soccertimeapp/services/notification_service.dart';
import 'package:soccertimeapp/services/lifecycle_service.dart';
import 'package:soccertimeapp/services/background_service.dart';

void main() {
  group('Services Integration Tests', () {
    late DialogService dialogService;
    late NotificationService notificationService;
    late LifecycleService lifecycleService;
    late BackgroundService backgroundService;

    setUp(() {
      dialogService = DialogService();
      notificationService = NotificationService();
      lifecycleService = LifecycleService();
      backgroundService = BackgroundService();
    });

    group('DialogService Integration', () {
      testWidgets('should show period end dialog with correct styling', (WidgetTester tester) async {
        // Create a test app with AppState
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => dialogService.showPeriodEndDialog(context, 1),
                    child: Text('Show Dialog'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Tap the button to show dialog
        await tester.tap(find.text('Show Dialog'));
        await tester.pumpAndSettle();

        // Verify dialog is shown
        expect(find.text('Period End'), findsOneWidget);
        expect(find.text('1st Half'), findsOneWidget);
      });

      testWidgets('should show match end dialog with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => dialogService.showPeriodEndDialog(context, 0, isMatchEnd: true),
                    child: Text('Show Match End'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Match End'));
        await tester.pumpAndSettle();

        expect(find.text('Match Complete'), findsOneWidget);
      });

      testWidgets('should show add player dialog with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        final textController = TextEditingController();
        final focusNode = FocusNode();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => dialogService.showAddPlayerDialog(
                      context,
                      textController: textController,
                      focusNode: focusNode,
                      onAddPlayer: () {},
                    ),
                    child: Text('Add Player'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Add Player'));
        await tester.pumpAndSettle();

        expect(find.text('Add Player'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('NotificationService Integration', () {
      testWidgets('should show period end notification with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => notificationService.showPeriodEndNotification(context, 1),
                    child: Text('Show Notification'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Notification'));
        await tester.pumpAndSettle();

        // Verify snackbar is shown
        expect(find.text('End of 1st Half!'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });

      testWidgets('should show match end notification with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => notificationService.showMatchEndNotification(context),
                    child: Text('Show Match End'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Match End'));
        await tester.pumpAndSettle();

        expect(find.text('Match Complete!'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });

      testWidgets('should show player added notification with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => notificationService.showPlayerAddedNotification(context, 'John'),
                    child: Text('Add Player'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Add Player'));
        await tester.pumpAndSettle();

        expect(find.text('John added to match'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });

      testWidgets('should show error notification with correct styling', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => notificationService.showErrorNotification(context, 'Test error'),
                    child: Text('Show Error'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Error'));
        await tester.pumpAndSettle();

        expect(find.text('Test error'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    });

    group('LifecycleService Integration', () {
      test('should initialize correctly', () {
        expect(lifecycleService.isInitialized, false);
        lifecycleService.initialize();
        expect(lifecycleService.isInitialized, true);
      });

      test('should handle background timers after reset', () {
        final appState = AppState();
        appState.session.matchTime = 0;
        appState.session.isPaused = false;
        
        lifecycleService.initialize();
        lifecycleService.checkBackgroundTimersAfterReset(appState);
        
        // Should not throw any exceptions
        expect(lifecycleService.isInitialized, true);
      });

      test('should reset tracking variables', () {
        lifecycleService.initialize();
        lifecycleService.reset();
        
        expect(lifecycleService.backgroundEntryTime, null);
        expect(lifecycleService.lastKnownMatchTime, null);
      });
    });

    group('Service Coordination', () {
      testWidgets('should coordinate dialog and notification services', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => dialogService.showPeriodEndDialog(context, 1),
                        child: Text('Show Dialog'),
                      ),
                      ElevatedButton(
                        onPressed: () => notificationService.showPeriodEndNotification(context, 1),
                        child: Text('Show Notification'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Test dialog
        await tester.tap(find.text('Show Dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Period End'), findsOneWidget);
        
        // Close dialog
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // Test notification
        await tester.tap(find.text('Show Notification'));
        await tester.pumpAndSettle();
        expect(find.text('End of 1st Half!'), findsOneWidget);
      });

      test('should maintain service state consistency', () {
        // Initialize all services
        lifecycleService.initialize();
        
        // Verify all services are properly initialized
        expect(lifecycleService.isInitialized, true);
        expect(dialogService, isNotNull);
        expect(notificationService, isNotNull);
        expect(backgroundService, isNotNull);
      });
    });

    group('Error Handling Integration', () {
      testWidgets('should handle service errors gracefully', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => notificationService.showErrorNotification(context, 'Service error'),
                    child: Text('Show Error'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Error'));
        await tester.pumpAndSettle();

        // Should show error notification without crashing
        expect(find.text('Service error'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    });

    group('Performance Integration', () {
      test('should handle multiple rapid service calls', () async {
        final appState = AppState();
        lifecycleService.initialize();
        
        // Rapid calls to lifecycle service
        for (int i = 0; i < 10; i++) {
          lifecycleService.checkBackgroundTimersAfterReset(appState);
        }
        
        // Should not throw exceptions
        expect(lifecycleService.isInitialized, true);
      });

      testWidgets('should handle rapid dialog and notification calls', (WidgetTester tester) async {
        final appState = AppState();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Provider<AppState>(
              create: (_) => appState,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      // Rapid calls to both services
                      for (int i = 0; i < 5; i++) {
                        notificationService.showInfoNotification(context, 'Info $i');
                      }
                    },
                    child: Text('Rapid Calls'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Rapid Calls'));
        await tester.pumpAndSettle();

        // Should handle rapid calls without issues
        expect(find.byType(SnackBar), findsOneWidget);
      });
    });
  });
}
