# ADR-001: Local Storage with Hive Database

## Status
**Accepted** - January 2024

## Context and Problem Statement

The SoccerTimeApp requires local data persistence for:
- Match session data (timers, settings, player information)
- Player timing statistics and match logs
- Application settings and preferences
- Session history for match review and sharing

### Requirements
- **Performance**: Real-time updates during active matches (sub-second response)
- **Reliability**: Data must persist across app restarts and device reboots
- **Simplicity**: Straightforward key-value storage for app's simple data relationships
- **Flutter Integration**: Native Dart integration without additional complexity
- **Offline-First**: No network dependency for core functionality

### Current Implementation Analysis
The app uses Hive with a 4-box storage architecture:
- `sessions` box: Session metadata and configuration
- `players` box: Player data and timing information
- `sessionSettings` box: Per-session configuration
- `sessionHistory` box: Completed match records

## Decision

**Chosen**: Hive NoSQL key-value database for local data persistence

### Implementation Details
```dart
class HiveSessionDatabase {
  static const String sessionBoxName = 'sessions';
  static const String playersBoxName = 'players';
  static const String settingsBoxName = 'sessionSettings';
  static const String historyBoxName = 'sessionHistory';
  
  // Singleton pattern with lazy initialization
  static HiveSessionDatabase get instance => _instance ??= HiveSessionDatabase._();
}
```

### Storage Architecture
- **Sessions Box**: Primary session data with metadata
- **Players Box**: Individual player timing and statistics
- **Settings Box**: Per-session configuration (match duration, segments, etc.)
- **History Box**: Completed match records for review and export

## Rationale

### Performance Analysis
- **Read Operations**: Hive provides O(1) key-based access, optimal for real-time timer updates
- **Write Operations**: Asynchronous writes don't block UI during frequent player time updates
- **Memory Usage**: Lazy loading keeps only active data in memory
- **Startup Time**: ~400-600ms initialization is acceptable for app launch

### Flutter Integration Benefits
- **Native Dart**: No FFI overhead or platform channel complexity
- **Type Safety**: Direct Dart object serialization/deserialization
- **Reactive Integration**: Works seamlessly with Provider/ChangeNotifier patterns
- **Development Experience**: Familiar Dart APIs reduce learning curve

### Operational Simplicity
- **Schema-less**: No migration complexity for evolving data structures
- **Single File**: Each box maps to a single file, simplifying backup/restore
- **Cross-Platform**: Identical behavior across Android/iOS without platform-specific code

## Alternatives Considered

### SQLite (via sqflite package)
**Rejected** - Reasons:
- **Over-Engineering**: Relational features not needed for simple key-value data
- **Performance**: SQL query parsing overhead for simple lookups
- **Migration Complexity**: Schema migrations would complicate future updates
- **Integration**: Requires mapping between SQL and Dart objects

```dart
// SQLite would require complex setup:
CREATE TABLE sessions (id INTEGER PRIMARY KEY, data TEXT);
// Plus migration logic, query building, object mapping
```

### SharedPreferences
**Rejected** - Reasons:
- **Data Structure**: Only supports primitive types, would require JSON serialization
- **Performance**: Not optimized for large datasets (50+ players, 100+ match events)
- **Atomic Operations**: No transaction support for complex state updates
- **Platform Limitations**: Android SharedPreferences has size limitations

### File-based JSON Storage
**Rejected** - Reasons:
- **Concurrency**: No built-in concurrency control for simultaneous reads/writes
- **Performance**: Full file reads/writes for partial updates
- **Reliability**: Manual file locking and error recovery complexity
- **Atomic Updates**: Risk of data corruption during app crashes

### Cloud Storage (Firebase, etc.)
**Rejected** - Reasons:
- **Network Dependency**: Requires internet connection for core timer functionality
- **Latency**: Network latency incompatible with real-time timer updates
- **Complexity**: Authentication, offline sync, and conflict resolution overhead
- **Privacy**: Local-only matches don't require cloud storage

## Consequences

### Positive
- **Excellent Performance**: Sub-100ms data operations for real-time timer updates
- **Simple Development**: Direct Dart object persistence without ORM complexity
- **Reliable**: Auto-recovery and atomic operations prevent data corruption
- **Portable**: Single-file databases simplify backup/restore functionality
- **Memory Efficient**: Lazy loading and box-based organization optimize memory usage
- **Future-Proof**: Schema-less design accommodates feature additions without migrations

### Negative
- **Query Limitations**: No complex queries or joins (acceptable given simple data relationships)
- **Box Management**: Manual box lifecycle management required (open/close operations)
- **Debug Complexity**: Binary format makes direct database inspection difficult
- **Large Data**: May not scale to thousands of matches (not a current requirement)

### Neutral
- **Learning Curve**: Team needs Hive-specific knowledge (minimal due to simple API)
- **Ecosystem**: Smaller ecosystem than SQLite (acceptable given feature completeness)

## Implementation Notes

### Database Initialization
```dart
Future<void> init() async {
  await Hive.initFlutter();
  _sessionsBox = await Hive.openBox<Map>(sessionBoxName);
  _playersBox = await Hive.openBox<Map>(playersBoxName);
  _settingsBox = await Hive.openBox<Map>(settingsBoxName);
  _historyBox = await Hive.openBox<Map>(historyBoxName);
}
```

### Performance Optimizations
- **Batch Operations**: Group related updates to minimize I/O operations
- **Lazy Loading**: Only load boxes when needed
- **Memory Management**: Close boxes during app backgrounding
- **Error Recovery**: Graceful handling of corrupted databases

### Testing Strategy
- **Unit Tests**: Mock Hive boxes for business logic testing
- **Integration Tests**: Real Hive operations for persistence verification
- **Performance Tests**: Timer accuracy validation under load

## Related ADRs
- [ADR-002](./ADR-002-background-service-architecture.md): Background service uses Hive for state persistence
- [ADR-003](./ADR-003-state-management-provider.md): AppState integrates with Hive for reactive updates
- [ADR-006](./ADR-006-service-layer-organization.md): HiveDatabase service encapsulates storage operations

## Review Notes
This decision aligns with the app's requirements for real-time performance, simplicity, and Flutter integration. The 4-box architecture provides logical separation while maintaining operational simplicity. Performance testing validates sub-second response times for timer operations.