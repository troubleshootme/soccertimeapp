import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:soccertimeapp/services/dialog_service.dart';
import 'package:soccertimeapp/providers/app_state.dart';
import 'package:soccertimeapp/services/haptic_service.dart';
import 'package:soccertimeapp/services/background_service.dart';

import 'dialog_service_test.mocks.dart';

@GenerateMocks([AppState, HapticService, BackgroundService])
void main() {
  group('DialogService', () {
    late DialogService dialogService;
    late MockAppState mockAppState;
    late MockHapticService mockHapticService;
    late MockBackgroundService mockBackgroundService;

    setUp(() {
      dialogService = DialogService();
      mockAppState = MockAppState();
      mockHapticService = MockHapticService();
      mockBackgroundService = MockBackgroundService();
    });

    testWidgets('showPeriodEndDialog displays correct dialog', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      when(mockBackgroundService.isTimerActive()).thenReturn(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => dialogService.showPeriodEndDialog(context, 1),
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Period End'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('showAddPlayerDialog displays correct dialog', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);
      final textController = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => dialogService.showAddPlayerDialog(
                  context,
                  textController: textController,
                  focusNode: focusNode,
                  onAddPlayer: () {},
                ),
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Add Player'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('showPlayerActionsDialog displays correct dialog', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => dialogService.showPlayerActionsDialog(
                  context,
                  'Test Player',
                  onEdit: () {},
                  onReset: () {},
                  onRemove: () {},
                ),
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Player Actions'), findsOneWidget);
      expect(find.text('What would you like to do with Test Player?'), findsOneWidget);
      expect(find.text('Edit Name'), findsOneWidget);
      expect(find.text('Reset Time'), findsOneWidget);
      expect(find.text('Remove Player'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('showActionSelectionDialog displays correct dialog', (WidgetTester tester) async {
      // Arrange
      when(mockAppState.isDarkTheme).thenReturn(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<AppState>(
            create: (_) => mockAppState,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => dialogService.showActionSelectionDialog(
                  context,
                  actionTimestamp: 1000,
                  onGoal: () {},
                  onAssist: () {},
                  onSubstitution: () {},
                  onYellowCard: () {},
                  onRedCard: () {},
                  onOther: () {},
                ),
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Match Action'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Assist'), findsOneWidget);
      expect(find.text('Substitution'), findsOneWidget);
      expect(find.text('Yellow Card'), findsOneWidget);
      expect(find.text('Red Card'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
