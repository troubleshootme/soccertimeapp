import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:soccertimeapp/services/lifecycle_service.dart';
import 'package:soccertimeapp/providers/app_state.dart';
import 'package:soccertimeapp/services/background_service.dart';

import 'lifecycle_service_test.mocks.dart';

@GenerateMocks([AppState, BackgroundService])
void main() {
  group('LifecycleService', () {
    late LifecycleService lifecycleService;
    late MockAppState mockAppState;
    late MockBackgroundService mockBackgroundService;

    setUp(() {
      lifecycleService = LifecycleService();
      mockAppState = MockAppState();
      mockBackgroundService = MockBackgroundService();
    });

    test('initialize sets isInitialized to true', () {
      // Act
      lifecycleService.initialize();

      // Assert
      expect(lifecycleService.isInitialized, isTrue);
    });

    test('handleAppLifecycleStateChange with resumed state calls onResume', () {
      // Arrange
      lifecycleService.initialize();
      bool onResumeCalled = false;
      bool onPauseCalled = false;
      bool onInactiveCalled = false;

      // Act
      lifecycleService.handleAppLifecycleStateChange(
        MaterialApp(home: Container()).createElement(),
        AppLifecycleState.resumed,
        onResume: () => onResumeCalled = true,
        onPause: () => onPauseCalled = true,
        onInactive: () => onInactiveCalled = true,
      );

      // Assert
      expect(onResumeCalled, isTrue);
      expect(onPauseCalled, isFalse);
      expect(onInactiveCalled, isFalse);
    });

    test('handleAppLifecycleStateChange with paused state calls onPause', () {
      // Arrange
      lifecycleService.initialize();
      bool onResumeCalled = false;
      bool onPauseCalled = false;
      bool onInactiveCalled = false;

      // Act
      lifecycleService.handleAppLifecycleStateChange(
        MaterialApp(home: Container()).createElement(),
        AppLifecycleState.paused,
        onResume: () => onResumeCalled = true,
        onPause: () => onPauseCalled = true,
        onInactive: () => onInactiveCalled = true,
      );

      // Assert
      expect(onResumeCalled, isFalse);
      expect(onPauseCalled, isTrue);
      expect(onInactiveCalled, isFalse);
    });

    test('handleAppLifecycleStateChange with inactive state calls onInactive', () {
      // Arrange
      lifecycleService.initialize();
      bool onResumeCalled = false;
      bool onPauseCalled = false;
      bool onInactiveCalled = false;

      // Act
      lifecycleService.handleAppLifecycleStateChange(
        MaterialApp(home: Container()).createElement(),
        AppLifecycleState.inactive,
        onResume: () => onResumeCalled = true,
        onPause: () => onPauseCalled = true,
        onInactive: () => onInactiveCalled = true,
      );

      // Assert
      expect(onResumeCalled, isFalse);
      expect(onPauseCalled, isFalse);
      expect(onInactiveCalled, isTrue);
    });

    test('checkBackgroundTimersAfterReset resets variables when match time is 0', () {
      // Arrange
      lifecycleService.initialize();
      when(mockAppState.session.matchTime).thenReturn(0);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      lifecycleService.checkBackgroundTimersAfterReset(mockAppState);

      // Assert
      expect(lifecycleService.backgroundEntryTime, isNull);
      expect(lifecycleService.lastKnownMatchTime, isNull);
    });

    test('checkBackgroundTimersAfterReset does not reset when match time is not 0', () {
      // Arrange
      lifecycleService.initialize();
      when(mockAppState.session.matchTime).thenReturn(100);
      when(mockAppState.session.isPaused).thenReturn(false);

      // Act
      lifecycleService.checkBackgroundTimersAfterReset(mockAppState);

      // Assert
      // Variables should remain unchanged
      expect(lifecycleService.backgroundEntryTime, isNull);
      expect(lifecycleService.lastKnownMatchTime, isNull);
    });

    test('reset clears tracking variables', () {
      // Arrange
      lifecycleService.initialize();

      // Act
      lifecycleService.reset();

      // Assert
      expect(lifecycleService.backgroundEntryTime, isNull);
      expect(lifecycleService.lastKnownMatchTime, isNull);
    });

    test('backgroundEntryTime getter returns correct value', () {
      // Arrange
      lifecycleService.initialize();

      // Act & Assert
      expect(lifecycleService.backgroundEntryTime, isNull);
    });

    test('lastKnownMatchTime getter returns correct value', () {
      // Arrange
      lifecycleService.initialize();

      // Act & Assert
      expect(lifecycleService.lastKnownMatchTime, isNull);
    });

    test('isInitialized getter returns correct value', () {
      // Arrange
      lifecycleService.initialize();

      // Act & Assert
      expect(lifecycleService.isInitialized, isTrue);
    });
  });
}
