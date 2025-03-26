class MatchLogEntry {
  String matchTime;  // Formatted time (mm:ss)
  int seconds;      // Actual seconds for sorting
  String timestamp;
  String details;
  String? entryType;

  MatchLogEntry({
    required this.matchTime,
    required this.seconds,
    required this.timestamp,
    required this.details,
    this.entryType = 'standard',
  });

  Map<String, dynamic> toJson() => {
        'matchTime': matchTime,
        'seconds': seconds,
        'timestamp': timestamp,
        'details': details,
        'entryType': entryType ?? 'standard',
      };

  factory MatchLogEntry.fromJson(Map<String, dynamic> json) {
    // Convert match time to seconds if seconds is not provided
    int? storedSeconds = json['seconds'] as int?;
    if (storedSeconds == null) {
      final matchTime = json['matchTime'] as String? ?? '0:00';
      final parts = matchTime.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        storedSeconds = minutes * 60 + seconds;
      } else {
        storedSeconds = 0;
      }
    }

    return MatchLogEntry(
      matchTime: json['matchTime'] ?? '0:00',
      seconds: storedSeconds,
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      details: json['details'] ?? '',
      entryType: json['entryType'],
    );
  }
}