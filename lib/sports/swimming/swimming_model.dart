/// Swimming age/gender categories matching the competition rules.
enum SwimmingCategory {
  /// Чоловіки до 35 років (2 per team in team scoring)
  m35('Ч35', 'Чоловіки до 35 років', 2),

  /// Чоловіки 35-49 років (2 per team in team scoring)
  m49('Ч49', 'Чоловіки 35-49 років', 2),

  /// Чоловіки 50+ років (1 per team in team scoring)
  m50('Ч50', 'Чоловіки 50+', 1),

  /// Жінки до 35 років (competes for 1 women slot)
  f35('Ж35', 'Жінки до 35 років', 1),

  /// Жінки 35+ років (competes for 1 women slot)
  f49('Ж49', 'Жінки 35+', 1),

  /// Естафета 4×25 м
  relay('Естафета', 'Естафета 4×25 м', 1);

  final String label;
  final String fullName;

  /// How many results from this category count toward team scoring.
  final int teamScoringSlots;

  const SwimmingCategory(this.label, this.fullName, this.teamScoringSlots);

  static SwimmingCategory fromDb(String value) {
    return SwimmingCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => SwimmingCategory.m35,
    );
  }
}

/// Individual swimming result for a player in a category.
class SwimmingResult {
  final int? id;
  final int tournamentId;
  final int? playerId; // null for relay
  final int teamId;
  final SwimmingCategory category;
  final int timeMin;
  final int timeSec;
  final int timeDsec;

  /// Total time in deciseconds for sorting (min*6000 + sec*100 + dsec).
  int get totalDsec => timeMin * 6000 + timeSec * 100 + timeDsec;

  /// Formatted time string: "0:24.43" or "1:10.00"
  String get timeFormatted {
    final sec = timeSec.toString().padLeft(2, '0');
    final dsec = timeDsec.toString().padLeft(2, '0');
    return '$timeMin:$sec.$dsec';
  }

  const SwimmingResult({
    this.id,
    required this.tournamentId,
    this.playerId,
    required this.teamId,
    required this.category,
    required this.timeMin,
    required this.timeSec,
    required this.timeDsec,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'sr_id': id,
        't_id': tournamentId,
        'player_id': playerId,
        'team_id': teamId,
        'category': category.name,
        'time_min': timeMin,
        'time_sec': timeSec,
        'time_dsec': timeDsec,
        'time_total': totalDsec,
      };

  factory SwimmingResult.fromMap(Map<String, dynamic> map) => SwimmingResult(
        id: map['sr_id'] as int?,
        tournamentId: map['t_id'] as int,
        playerId: map['player_id'] as int?,
        teamId: map['team_id'] as int,
        category: SwimmingCategory.fromDb(map['category'] as String),
        timeMin: map['time_min'] as int,
        timeSec: map['time_sec'] as int,
        timeDsec: map['time_dsec'] as int,
      );

  SwimmingResult copyWith({
    int? id,
    int? tournamentId,
    int? playerId,
    int? teamId,
    SwimmingCategory? category,
    int? timeMin,
    int? timeSec,
    int? timeDsec,
  }) =>
      SwimmingResult(
        id: id ?? this.id,
        tournamentId: tournamentId ?? this.tournamentId,
        playerId: playerId ?? this.playerId,
        teamId: teamId ?? this.teamId,
        category: category ?? this.category,
        timeMin: timeMin ?? this.timeMin,
        timeSec: timeSec ?? this.timeSec,
        timeDsec: timeDsec ?? this.timeDsec,
      );
}

/// A ranked result with place number.
class RankedSwimmingResult {
  final SwimmingResult result;
  final int place;
  final String? playerName;
  final String? teamName;

  const RankedSwimmingResult({
    required this.result,
    required this.place,
    this.playerName,
    this.teamName,
  });
}

/// Team swimming standings entry.
class SwimmingTeamStanding {
  final int teamId;
  final String teamName;

  /// Points per category (category -> list of places).
  final Map<SwimmingCategory, List<int>> categoryPlaces;

  /// Points from each scoring slot (7 total).
  final List<int> scoringPlaces;

  /// Total points (sum of best 7: 2×Ч35 + 2×Ч49 + 1×Ч50 + 1×Ж + 1×Relay).
  final int totalPoints;

  /// Final team place.
  final int place;

  const SwimmingTeamStanding({
    required this.teamId,
    required this.teamName,
    required this.categoryPlaces,
    required this.scoringPlaces,
    required this.totalPoints,
    required this.place,
  });
}
