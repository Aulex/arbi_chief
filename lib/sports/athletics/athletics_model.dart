/// Athletics age/gender categories matching the competition rules.
///
/// Women: 1500m, Men: 3000m.
/// Age categories based on birth year (reference year 2026):
///   35 = born 1992+, 49 = born 1977–1991, 50 = born ≤1976.
enum AthleticsCategory {
  /// Чоловіки до 35 років (1992 р.н. та молодші)
  m35('Ч35', 'Чоловіки до 35 років', 3000, true),

  /// Чоловіки 35-49 років (1977-1991 р.н.)
  m49('Ч49', 'Чоловіки 35-49 років', 3000, true),

  /// Чоловіки 50+ років (1976 р.н. та старші)
  m50('Ч50', 'Чоловіки 50+', 3000, true),

  /// Жінки до 35 років (1992 р.н. та молодші)
  f35('Ж35', 'Жінки до 35 років', 1500, false),

  /// Жінки 35-49 років (1977-1991 р.н.)
  f49('Ж49', 'Жінки 35-49 років', 1500, false),

  /// Жінки 50+ років (1976 р.н. та старші)
  f50('Ж50', 'Жінки 50+', 1500, false);

  final String label;
  final String fullName;
  final int distanceMeters;
  final bool isMale;

  const AthleticsCategory(this.label, this.fullName, this.distanceMeters, this.isMale);

  String get distanceLabel => '$distanceMeters м';

  static AthleticsCategory fromDb(String value) {
    return AthleticsCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => AthleticsCategory.m35,
    );
  }

  /// All male categories.
  static List<AthleticsCategory> get maleCategories => [m35, m49, m50];

  /// All female categories.
  static List<AthleticsCategory> get femaleCategories => [f35, f49, f50];

  /// Auto-detect category from birth year and gender.
  /// Gender: 0 = male, 1 = female.
  static AthleticsCategory detectCategory(int? birthYear, int gender) {
    if (birthYear == null) {
      return gender == 1 ? f35 : m35;
    }
    if (gender == 1) {
      // Female
      if (birthYear >= 1992) return f35;
      if (birthYear >= 1977) return f49;
      return f50;
    } else {
      // Male
      if (birthYear >= 1992) return m35;
      if (birthYear >= 1977) return m49;
      return m50;
    }
  }
}

/// Individual athletics result for a player in a category.
class AthleticsResult {
  final int? id;
  final int tournamentId;
  final int playerId;
  final int teamId;
  final AthleticsCategory category;
  final int timeMin;
  final int timeSec;
  final int timeDsec;

  /// Total time in deciseconds for sorting (min*6000 + sec*100 + dsec).
  int get totalDsec => timeMin * 6000 + timeSec * 100 + timeDsec;

  /// Formatted time string: "5:24.43" or "12:10.00"
  String get timeFormatted {
    final sec = timeSec.toString().padLeft(2, '0');
    final dsec = timeDsec.toString().padLeft(2, '0');
    return '$timeMin:$sec.$dsec';
  }

  /// Adjusted time in deciseconds after applying age coefficient.
  double adjustedDsec(double coefficient) => totalDsec * coefficient;

  /// Formatted adjusted time string.
  String adjustedTimeFormatted(double coefficient) {
    final adjusted = adjustedDsec(coefficient);
    final totalDsecInt = adjusted.round();
    final min = totalDsecInt ~/ 6000;
    final sec = (totalDsecInt % 6000) ~/ 100;
    final dsec = totalDsecInt % 100;
    return '$min:${sec.toString().padLeft(2, '0')}.${dsec.toString().padLeft(2, '0')}';
  }

  const AthleticsResult({
    this.id,
    required this.tournamentId,
    required this.playerId,
    required this.teamId,
    required this.category,
    required this.timeMin,
    required this.timeSec,
    required this.timeDsec,
  });

  AthleticsResult copyWith({
    int? id,
    int? tournamentId,
    int? playerId,
    int? teamId,
    AthleticsCategory? category,
    int? timeMin,
    int? timeSec,
    int? timeDsec,
  }) =>
      AthleticsResult(
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
class RankedAthleticsResult {
  final AthleticsResult result;
  final int place;
  final String? playerName;
  final String? teamName;
  final int age;
  final double coefficient;
  final double adjustedDsec;
  final int? playerNumber;

  const RankedAthleticsResult({
    required this.result,
    required this.place,
    this.playerName,
    this.teamName,
    this.age = 0,
    this.coefficient = 1.0,
    this.adjustedDsec = 0,
    this.playerNumber,
  });
}

/// Team athletics standings entry.
class AthleticsTeamStanding {
  final int teamId;
  final String teamName;

  /// Places used from each category for team scoring.
  final Map<AthleticsCategory, List<int>> categoryPlaces;

  /// The 3 scoring places chosen (2 men + 1 woman from different categories).
  final List<int> scoringPlaces;

  /// Total points (sum of scoring places).
  final int totalPoints;

  /// Sum of raw times (deciseconds) of 3 contributing participants for tiebreak.
  final int sumOfTimes;

  /// Sum of ages of 3 contributing participants for tiebreak.
  final int sumOfAges;

  /// Best (lowest) adjusted time among women counted in scoring.
  final double bestWomanTime;

  /// Final team place.
  final int place;

  const AthleticsTeamStanding({
    required this.teamId,
    required this.teamName,
    required this.categoryPlaces,
    required this.scoringPlaces,
    required this.totalPoints,
    this.sumOfTimes = 0,
    this.sumOfAges = 0,
    this.bestWomanTime = double.infinity,
    required this.place,
  });
}

// ── Age Coefficient Lookup ──

/// Age coefficients for athletics scoring.
/// All coefficient data is stored per-tournament in the database.
/// Coefficients must be imported/entered by the user in tournament settings.
class AthleticsCoefficients {
  /// Look up the coefficient for a given age and gender from a custom table.
  /// [isMale] = true for men (3000m), false for women (1500m).
  /// Returns 1.0 if no coefficient is configured for this age.
  static double getCoefficientFromTable(
    int age,
    bool isMale,
    Map<int, ({double men3000, double women1500})>? customTable,
  ) {
    if (customTable == null || customTable.isEmpty) return 1.0;
    final entry = customTable[age];
    if (entry == null) return 1.0;
    return isMale ? entry.men3000 : entry.women1500;
  }
}
