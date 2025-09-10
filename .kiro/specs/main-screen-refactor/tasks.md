# Implementation Plan

- [x] 1. Create service layer foundation
  - Create DialogService class to handle all dialog operations (period end, match end, player actions) with identical dialog appearance and behavior
  - Create NotificationService class to handle snackbar notifications with identical styling and timing
  - Create LifecycleService class to handle app lifecycle management with identical behavior
  - Ensure all services maintain exact same UI appearance, timing, and user interactions as original
  - Write unit tests for each service class
  - _Requirements: 5.1, 5.2, 5.3, 6.1, 6.2_

- [x] 2. Extract and implement MatchTimerWidget
  - Create MatchTimerWidget class with timer management logic that produces identical UI behavior
  - Move all timer-related methods (_startMatchTimer, _stopMatchTimer, _resetMatch, _togglePlayPause) to the widget without changing any timing or behavior
  - Implement background service integration within the timer widget maintaining exact same integration behavior
  - Move period end and match end detection logic to the timer widget with identical trigger conditions and timing
  - Ensure timer display updates at exactly the same frequency and appearance as original
  - Create comprehensive unit tests for timer functionality
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 3. Extract and implement PlayerManagementWidget
  - Create PlayerManagementWidget class with player operations
  - Move player-related methods (_showAddPlayerDialog, _togglePlayerByName, _showPlayerActionsDialog, etc.) to the widget
  - Implement player table expansion/collapse functionality
  - Move player validation logic (_hasActivePlayer) to the widget
  - Create unit tests for player management functionality
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 4. Create UI display components
- [x] 4.1 Implement MatchTimeDisplayWidget
  - Create MatchTimeDisplayWidget class for time display
  - Move time formatting and display logic to the widget
  - Implement ValueNotifier integration for reactive updates
  - Create unit tests for time display functionality
  - _Requirements: 4.3, 4.4_

- [x] 4.2 Implement SessionInfoWidget
  - Create SessionInfoWidget class for session information display
  - Move session name and period display logic to the widget
  - Implement proper styling and theme integration
  - Create unit tests for session info display
  - _Requirements: 4.2, 4.4_

- [x] 4.3 Implement MatchControlsWidget
  - Create MatchControlsWidget class for play/pause/reset controls
  - Move control button logic and styling to the widget
  - Implement proper callback integration with parent components
  - Create unit tests for control functionality
  - _Requirements: 4.1, 4.4_

- [ ] 5. Integrate services into existing components
  - Update MatchTimerWidget to use DialogService for period/match end dialogs
  - Update PlayerManagementWidget to use DialogService for player dialogs
  - Update all components to use NotificationService for snackbar notifications
  - Update MainScreen to use LifecycleService for app lifecycle management
  - Write integration tests for service usage
  - _Requirements: 5.1, 5.2, 5.3, 6.1, 6.2_

- [ ] 6. Refactor MainScreen to use extracted components
  - Remove extracted functionality from MainScreen class while preserving exact UI layout and appearance
  - Implement component composition in MainScreen build method ensuring identical widget tree structure
  - Set up proper callback chains between components and MainScreen maintaining identical user interaction behavior
  - Ensure proper state management between components and AppState with no changes to state timing or values
  - Reduce MainScreen to under 500 lines as specified while maintaining 100% identical UI and behavior
  - _Requirements: 1.1, 1.2, 6.3, 6.4_

- [ ] 7. Update imports and dependencies
  - Add proper import statements for all new components
  - Remove unused imports from MainScreen
  - Ensure all dependencies are properly declared
  - Update any relative imports to use correct paths
  - _Requirements: 1.3, 1.4_

- [ ] 8. UI preservation validation during component extraction
  - Take screenshots of all UI states before starting component extraction
  - After each component extraction, verify UI renders identically to screenshots
  - Test that all button positions, sizes, colors, and styling remain exactly the same
  - Verify all animations and transitions work identically to original
  - Ensure no layout shifts or visual changes occur during refactoring
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 9. Behavioral preservation testing
  - Test all timer functionality works exactly as before (start, pause, reset, period transitions)
  - Verify all player management operations work identically (add, remove, edit, toggle)
  - Test all dialog flows appear and behave exactly as in original implementation
  - Verify all audio and haptic feedback triggers at identical times and conditions
  - Test background service integration maintains identical behavior
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 10. Performance and final validation
  - Run performance tests to ensure no regression in rendering or memory usage
  - Verify app lifecycle management works identically to original
  - Test all edge cases and error conditions work exactly as before
  - Perform side-by-side comparison testing with original implementation
  - Document that refactoring achieved code organization goals without any UI/UX changes
  - _Requirements: 1.3, 7.1, 7.2, 7.3, 7.4, 7.5_