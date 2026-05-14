/// Cycling age/gender categories for the cross-country marathon rules.
///
/// Single mass-start distance (~30 km) for all groups; winners are decided
/// by raw time (no age coefficients). Age categories are based on birth year
/// (reference year 2026):
///   35 = born 1992+, 49 = born 1977–1991, 50 = born ≤1976.
/// Women have only two categories — Ж49 covers all women 35 and older.
enum CyclingCategory {
  /// Чоловіки до 35 років (1992 р.н. та молодші)
  m35('Ч35', 'Чоловіки до 35 років', true),

  /// Чоловіки 35-49 років (1977-1991 р.н.)
  m49('Ч49', 'Чоловіки 35-49 років', true),

  /// Чоловіки 50+ років (1976 р.н. та старші)
  m50('Ч50', 'Чоловіки 50+', true),

  /// Жінки до 35 років (1992 р.н. та молодші)
  f35('Ж35', 'Жінки до 35 років', false),

  /// Жінки 35+ років (1991 р.н. та старші)
  f49('Ж49', 'Жінки 35+', false);

  final String label;
  final String fullName;
  final bool isMale;

  const CyclingCategory(this.label, this.fullName, this.isMale);

  static CyclingCategory fromDb(String value) {
    return CyclingCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => CyclingCategory.m35,
    );
  }

  /// All male categories.
  static List<CyclingCategory> get maleCategories => [m35, m49, m50];

  /// All female categories.
  static List<CyclingCategory> get femaleCategories => [f35, f49];

  /// Auto-detect category from birth year and gender.
  /// Gender: 0 = male, 1 = female.
  static CyclingCategory detectCategory(int? birthYear, int gender) {
    if (birthYear == null) {
      return gender == 1 ? f35 : m35;
    }
    if (gender == 1) {
      // Female — only two brackets; Ж49 covers everyone 35+.
      if (birthYear >= 1992) return f35;
      return f49;
    } else {
      // Male
      if (birthYear >= 1992) return m35;
      if (birthYear >= 1977) return m49;
      return m50;
    }
  }

  /// Categories an athlete may compete in given their auto-detected category.
  /// Per the rules:
  ///   - older athletes may drop to a younger age category within their gender;
  ///   - women may additionally substitute for men in their own age category
  ///     or younger.
  /// Movement up the age scale and men-to-women movement are not allowed.
  static List<CyclingCategory> allowedCategoriesFor(CyclingCategory auto) {
    switch (auto) {
      case m35:
        return const [m35];
      case m49:
        return const [m35, m49];
      case m50:
        return const [m35, m49, m50];
      case f35:
        return const [f35, m35];
      case f49:
        return const [f35, f49, m35, m49];
    }
  }
}

/// Label for the single cross-country marathon distance.
const String kCyclingDistanceLabel = 'Крос-кантрі веломарафон (до 30 км)';

/// Individual cycling result for a player in a category.
///
/// A cross-country marathon takes hours, so times are stored as
/// hours / minutes / seconds (the underlying `se_result` value is the
/// total in whole seconds).
class CyclingResult {
  final int? id;
  final int tournamentId;
  final int playerId;
  final int teamId;
  final CyclingCategory category;
  final int timeHour;
  final int timeMin;
  final int timeSec;

  /// Total time in whole seconds for sorting (h*3600 + m*60 + s).
  int get totalSec => timeHour * 3600 + timeMin * 60 + timeSec;

  /// Formatted time string: "1:24:43" or "0:48:05"
  String get timeFormatted {
    final m = timeMin.toString().padLeft(2, '0');
    final s = timeSec.toString().padLeft(2, '0');
    return '$timeHour:$m:$s';
  }

  const CyclingResult({
    this.id,
    required this.tournamentId,
    required this.playerId,
    required this.teamId,
    required this.category,
    required this.timeHour,
    required this.timeMin,
    required this.timeSec,
  });

  CyclingResult copyWith({
    int? id,
    int? tournamentId,
    int? playerId,
    int? teamId,
    CyclingCategory? category,
    int? timeHour,
    int? timeMin,
    int? timeSec,
  }) =>
      CyclingResult(
        id: id ?? this.id,
        tournamentId: tournamentId ?? this.tournamentId,
        playerId: playerId ?? this.playerId,
        teamId: teamId ?? this.teamId,
        category: category ?? this.category,
        timeHour: timeHour ?? this.timeHour,
        timeMin: timeMin ?? this.timeMin,
        timeSec: timeSec ?? this.timeSec,
      );
}

/// A ranked result with place number. Cycling ranks by raw time, so there is
/// no coefficient / adjusted time (unlike athletics).
class RankedCyclingResult {
  final CyclingResult? result;
  final int place;
  final String? playerName;
  final String? teamName;
  final int age;
  final int? playerNumber;
  final int? pendingPlayerId;
  final int? pendingTeamId;

  const RankedCyclingResult({
    this.result,
    required this.place,
    this.playerName,
    this.teamName,
    this.age = 0,
    this.playerNumber,
    this.pendingPlayerId,
    this.pendingTeamId,
  });

  int get effectivePlayerId => result?.playerId ?? pendingPlayerId ?? 0;
  int get effectiveTeamId => result?.teamId ?? pendingTeamId ?? 0;
}

/// Team cycling standings entry.
class CyclingTeamStanding {
  final int teamId;
  final String teamName;

  /// Places used from each category for team scoring.
  final Map<CyclingCategory, List<int>> categoryPlaces;

  /// The 3 scoring places chosen (2 men + 1 woman from different categories).
  final List<int> scoringPlaces;

  /// Total points (sum of scoring places).
  final int totalPoints;

  /// Sum of raw times (whole seconds) of 3 contributing participants for tiebreak.
  final int sumOfTimes;

  /// Sum of ages of 3 contributing participants for tiebreak.
  final int sumOfAges;

  /// Best (lowest) raw time among women counted in scoring.
  final double bestWomanTime;

  /// Final team place.
  final int place;

  const CyclingTeamStanding({
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

/// Row of the "Всі учасники" inline-entry tab. Combines participant identity
/// with their assigned-category override and existing result (if any).
class CyclingParticipantEntry {
  final int playerId;
  final int teamId;
  final String fullName;
  final String teamName;
  final int age;
  final int gender;
  final int? playerNumber;
  final CyclingCategory autoCategory;
  final CyclingCategory? assignedCategory;
  final int? resultId;
  final int? resultTotalSec;
  final CyclingCategory? resultCategory;

  /// Effective category for the participant: assigned override or auto.
  CyclingCategory get effectiveCategory => assignedCategory ?? autoCategory;

  const CyclingParticipantEntry({
    required this.playerId,
    required this.teamId,
    required this.fullName,
    required this.teamName,
    required this.age,
    required this.gender,
    this.playerNumber,
    required this.autoCategory,
    this.assignedCategory,
    this.resultId,
    this.resultTotalSec,
    this.resultCategory,
  });
}
