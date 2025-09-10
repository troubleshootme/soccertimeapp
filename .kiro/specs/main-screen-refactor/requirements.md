# Requirements Document

## Introduction

The main_screen.dart file has grown to over 3800 lines and contains multiple responsibilities that should be separated into distinct, modular components. This refactoring will improve code maintainability, testability, and readability by extracting logical components into separate files while maintaining the existing functionality and user experience.

## Requirements

### Requirement 1

**User Story:** As a developer, I want the main screen code to be modular and well-organized, so that I can easily maintain and extend the application.

#### Acceptance Criteria

1. WHEN the refactoring is complete THEN the main_screen.dart file SHALL be reduced to under 500 lines
2. WHEN components are extracted THEN each component SHALL have a single, well-defined responsibility
3. WHEN the refactoring is complete THEN all existing functionality SHALL remain unchanged
4. WHEN components are created THEN they SHALL follow Flutter best practices for widget composition

### Requirement 2

**User Story:** As a developer, I want timer-related functionality to be in a separate component, so that timer logic is isolated and easier to test.

#### Acceptance Criteria

1. WHEN timer functionality is extracted THEN it SHALL be moved to a dedicated timer widget or service
2. WHEN the timer component is created THEN it SHALL handle all match timing logic including start, stop, pause, and reset
3. WHEN the timer component is created THEN it SHALL manage period transitions and match completion
4. WHEN the timer is extracted THEN it SHALL maintain all existing timer behaviors including background service integration
5. WHEN a match is started THEN the timers and period ends WILL be preserved and alerted regardless of whether the phone is asleep or in standby and app is minimized
### Requirement 3

**User Story:** As a developer, I want player management functionality to be in a separate component, so that player-related code is organized and reusable.

#### Acceptance Criteria

1. WHEN player management is extracted THEN it SHALL be moved to a dedicated player management widget
2. WHEN the player component is created THEN it SHALL handle adding, removing, and displaying players
3. WHEN the player component is created THEN it SHALL manage player selection and active player validation
4. WHEN the player component is created THEN it SHALL handle the expandable player table functionality

### Requirement 4

**User Story:** As a developer, I want UI controls to be organized into logical component groups, so that the interface is easier to understand and modify.

#### Acceptance Criteria

1. WHEN UI controls are extracted THEN play/pause controls SHALL be in a dedicated control panel component
2. WHEN UI controls are extracted THEN session information display SHALL be in a separate component
3. WHEN UI controls are extracted THEN match time display SHALL be in a dedicated time display component
4. WHEN components are created THEN they SHALL use proper Flutter widget composition patterns

### Requirement 5

**User Story:** As a developer, I want dialog and notification logic to be separated from the main screen, so that UI feedback is modular and reusable.

#### Acceptance Criteria

1. WHEN dialog logic is extracted THEN period end dialogs SHALL be handled by a dedicated dialog service or component
2. WHEN dialog logic is extracted THEN match end dialogs SHALL be handled by a dedicated dialog service or component
3. WHEN notification logic is extracted THEN snackbar notifications SHALL be handled by a dedicated notification service
4. WHEN dialog components are created THEN they SHALL maintain all existing dialog behaviors and user interactions

### Requirement 6

**User Story:** As a developer, I want lifecycle and state management to be clearly separated, so that component initialization and cleanup is easier to understand.

#### Acceptance Criteria

1. WHEN lifecycle management is extracted THEN app lifecycle observers SHALL be in a dedicated lifecycle component
2. WHEN state management is extracted THEN background service integration SHALL be clearly separated from UI logic
3. WHEN components are created THEN each SHALL properly handle its own initialization and disposal
4. WHEN the refactoring is complete THEN the main screen SHALL only coordinate between components rather than managing all details

### Requirement 7

**User Story:** As a developer, I want the refactored code to maintain all existing functionality, so that users experience no changes in behavior.

#### Acceptance Criteria

1. WHEN the refactoring is complete THEN all timer functionality SHALL work exactly as before
2. WHEN the refactoring is complete THEN all player management SHALL work exactly as before
3. WHEN the refactoring is complete THEN all dialogs and notifications SHALL appear exactly as before
4. WHEN the refactoring is complete THEN all audio and haptic feedback SHALL work exactly as before
5. WHEN the refactoring is complete THEN background service integration SHALL work exactly as before