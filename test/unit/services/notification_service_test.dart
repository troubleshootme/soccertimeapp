import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:soccertimeapp/services/notification_service.dart';
import 'package:soccertimeapp/providers/app_state.dart';

import 'notification_service_test.mocks.dart';

@GenerateMocks([AppState])
void main() {
  group('NotificationService', () {
    late NotificationService notificationService;
    late MockAppState mockAppState;

    setUp(() {
      notificationService = NotificationService();
      mockAppState = MockAppState();
    });

    testWidgets('showPeriodEndNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.session.matchSegments).thenReturn(2);

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => notificationService.showPeriodEndNotification(context, 1),
                child: Text('Show Notification'),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('End of 1st Half!'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('showMatchEndNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showMatchEndNotification(context),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Match Complete!'), findsOneWidget);
    });

    testWidgets('showPlayerAddedNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showPlayerAddedNotification(context, 'John Doe'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('John Doe added to match'), findsOneWidget);
    });

    testWidgets('showPlayerRemovedNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showPlayerRemovedNotification(context, 'John Doe'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('John Doe removed from match'), findsOneWidget);
    });

    testWidgets('showPlayerTimeResetNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showPlayerTimeResetNotification(context, 'John Doe'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('John Doe time reset'), findsOneWidget);
    });

    testWidgets('showMatchActionNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showMatchActionNotification(context, 'Goal', 'John Doe'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Goal logged for John Doe'), findsOneWidget);
    });

    testWidgets('showErrorNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showErrorNotification(context, 'Test error message'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('showSuccessNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showSuccessNotification(context, 'Test success message'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Test success message'), findsOneWidget);
    });

    testWidgets('showInfoNotification displays correct snackbar', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => notificationService.showInfoNotification(context, 'Test info message'),
              child: Text('Show Notification'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Notification'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Test info message'), findsOneWidget);
    });
  });
}
