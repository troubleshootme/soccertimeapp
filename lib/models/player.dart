class Player {
  String name;
  bool active = false;         // Is the player currently active?
  int totalTime = 0;          // Accumulated time in seconds
  int? lastActiveMatchTime;   // Match time (in seconds) when this player was last activated
  int goals = 0;             // Number of goals scored by the player

  Player({
    required this.name,
    this.totalTime = 0,
    this.active = false,
    this.lastActiveMatchTime,
    this.goals = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'active': active,
    'totalTime': totalTime,
    'lastActiveMatchTime': lastActiveMatchTime,
    'goals': goals,
  };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    name: json['name'] as String,
    totalTime: json['totalTime'] ?? 0,
    active: json['active'] ?? false,
    lastActiveMatchTime: json['lastActiveMatchTime'],
    goals: json['goals'] ?? 0,
  );
}