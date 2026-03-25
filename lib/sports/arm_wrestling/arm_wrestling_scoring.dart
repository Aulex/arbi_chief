/// Arm wrestling scoring utilities.
///
/// Individual: round-robin within weight categories, win=1, loss=0, no draws.
/// Team: lowest sum of placement points from 3 best participants
/// across 3 different weight categories.

/// Weight category definitions.
enum WeightCategory {
  under70(1, 'до 70 кг'),
  under80(2, 'до 80 кг'),
  under90(3, 'до 90 кг'),
  under100(4, 'до 100 кг'),
  over100(5, 'понад 100 кг');

  final int id;
  final String label;
  const WeightCategory(this.id, this.label);

  static WeightCategory? fromId(int id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Minimum participants for a weight category to be valid.
const int minParticipantsForCategory = 5;

/// Points multiplier (1 win = 1 point).
const int armWrestlingPointMultiplier = 1;

/// Format result: + for win, − for loss.
String formatArmWrestlingResult(double? result) {
  if (result == null) return '';
  if (result == 1.0) return '+';
  if (result == 0.0) return '−';
  return result.toString();
}

/// Individual standing within a weight category.
class ArmWrestlingStanding {
  final int playerId;
  final String playerName;
  final String teamName;
  final int teamId;
  final int wins;
  final int losses;
  final int gamesPlayed;
  int place;

  ArmWrestlingStanding({
    required this.playerId,
    required this.playerName,
    required this.teamName,
    required this.teamId,
    required this.wins,
    required this.losses,
    required this.gamesPlayed,
    this.place = 0,
  });
}

/// Calculate individual standings for a weight category.
/// [results] maps playerId → opponentId → result (1.0=win, 0.0=loss).
List<ArmWrestlingStanding> calculateCategoryStandings({
  required List<({int playerId, String playerName, String teamName, int teamId})> players,
  required Map<int, Map<int, double>> results,
}) {
  final standings = <ArmWrestlingStanding>[];

  for (final p in players) {
    final playerResults = results[p.playerId] ?? {};
    int wins = 0;
    int losses = 0;
    for (final r in playerResults.values) {
      if (r == 1.0) wins++;
      else if (r == 0.0) losses++;
    }
    standings.add(ArmWrestlingStanding(
      playerId: p.playerId,
      playerName: p.playerName,
      teamName: p.teamName,
      teamId: p.teamId,
      wins: wins,
      losses: losses,
      gamesPlayed: playerResults.length,
    ));
  }

  // Sort: most wins first, then head-to-head
  standings.sort((a, b) {
    if (a.wins != b.wins) return b.wins.compareTo(a.wins);
    // Head-to-head: if a beat b, a ranks higher
    final h2h = results[a.playerId]?[b.playerId];
    if (h2h == 1.0) return -1;
    if (h2h == 0.0) return 1;
    // Fewer losses
    if (a.losses != b.losses) return a.losses.compareTo(b.losses);
    return 0;
  });

  // Assign places
  for (int i = 0; i < standings.length; i++) {
    standings[i].place = i + 1;
  }

  return standings;
}

/// Team standing in arm wrestling.
class ArmWrestlingTeamStanding {
  final int teamId;
  final String teamName;
  /// Sum of placement points from 3 best participants (lower is better).
  final int totalPoints;
  /// Details: which categories contributed.
  final List<({int categoryId, String categoryLabel, int place})> contributors;
  /// Total weight of 3 contributors (for tiebreaker).
  final double totalWeight;
  /// All placements across all categories.
  final List<int> allPlacements;
  int place;

  ArmWrestlingTeamStanding({
    required this.teamId,
    required this.teamName,
    required this.totalPoints,
    required this.contributors,
    this.totalWeight = 0.0,
    this.allPlacements = const [],
    this.place = 0,
  });
}

/// Calculate team standings based on individual placements.
///
/// Rules:
/// - Pick 3 best placements from 3 different weight categories (1 per category)
/// - Sum placement points (1st=1, 2nd=2, etc.)
/// - Lower sum wins
/// - Tiebreakers: more 1st/2nd/3rd places, then other categories, then all categories, then lower total weight
///
/// [penaltyPlace] is the place assigned for missing participants (last place + 1 in largest category).
List<ArmWrestlingTeamStanding> calculateTeamStandings({
  required Map<int, List<ArmWrestlingStanding>> categoryStandings,
  required Set<int> teamIds,
  required Map<int, String> teamNames,
}) {
  // Find the largest category size for penalty calculation
  int maxCategorySize = 0;
  for (final standings in categoryStandings.values) {
    if (standings.length > maxCategorySize) {
      maxCategorySize = standings.length;
    }
  }
  final penaltyPlace = maxCategorySize + 1;

  final teamStandings = <ArmWrestlingTeamStanding>[];

  for (final teamId in teamIds) {
    // Collect best placement per category for this team
    final bestPerCategory = <int, ({int place, String categoryLabel})>{};
    final allPlacements = <int>[];

    for (final catEntry in categoryStandings.entries) {
      final categoryId = catEntry.key;
      final standings = catEntry.value;
      final categoryLabel = WeightCategory.fromId(categoryId)?.label ?? 'Категорія $categoryId';

      // Find best placement for this team in this category
      int? bestPlace;
      for (final s in standings) {
        if (s.teamId == teamId) {
          if (bestPlace == null || s.place < bestPlace) {
            bestPlace = s.place;
          }
        }
      }
      if (bestPlace != null) {
        bestPerCategory[categoryId] = (place: bestPlace, categoryLabel: categoryLabel);
        allPlacements.add(bestPlace);
      }
    }

    // Select 3 best placements from 3 different categories
    final sortedCategories = bestPerCategory.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));

    final contributors = <({int categoryId, String categoryLabel, int place})>[];
    int totalPoints = 0;

    for (int i = 0; i < 3; i++) {
      if (i < sortedCategories.length) {
        final entry = sortedCategories[i];
        contributors.add((
          categoryId: entry.key,
          categoryLabel: entry.value.categoryLabel,
          place: entry.value.place,
        ));
        totalPoints += entry.value.place;
      } else {
        // Missing participant: penalty
        totalPoints += penaltyPlace;
      }
    }

    teamStandings.add(ArmWrestlingTeamStanding(
      teamId: teamId,
      teamName: teamNames[teamId] ?? '',
      totalPoints: totalPoints,
      contributors: contributors,
      allPlacements: allPlacements..sort(),
    ));
  }

  // Sort teams
  teamStandings.sort((a, b) {
    // Primary: lowest total points
    if (a.totalPoints != b.totalPoints) {
      return a.totalPoints.compareTo(b.totalPoints);
    }

    // Tiebreaker 1: more 1st, 2nd, 3rd places etc.
    final maxPlace = _maxPlace(a.allPlacements, b.allPlacements);
    for (int p = 1; p <= maxPlace; p++) {
      final aCount = a.allPlacements.where((x) => x == p).length;
      final bCount = b.allPlacements.where((x) => x == p).length;
      if (aCount != bCount) return bCount.compareTo(aCount); // more is better
    }

    // Tiebreaker 2: better results in other categories not in team standing
    // (compare remaining placements not used in contributors)
    final aContribCats = a.contributors.map((c) => c.categoryId).toSet();
    final bContribCats = b.contributors.map((c) => c.categoryId).toSet();
    final aOther = <int>[];
    final bOther = <int>[];
    for (final catEntry in categoryStandings.entries) {
      if (!aContribCats.contains(catEntry.key)) {
        for (final s in catEntry.value) {
          if (s.teamId == a.teamId) aOther.add(s.place);
        }
      }
      if (!bContribCats.contains(catEntry.key)) {
        for (final s in catEntry.value) {
          if (s.teamId == b.teamId) bOther.add(s.place);
        }
      }
    }
    aOther.sort();
    bOther.sort();
    final otherLen = aOther.length < bOther.length ? aOther.length : bOther.length;
    for (int i = 0; i < otherLen; i++) {
      if (aOther[i] != bOther[i]) return aOther[i].compareTo(bOther[i]); // lower place is better
    }

    // Tiebreaker 3: lower total weight (not tracked in DB, keep equal)
    return 0;
  });

  // Assign places
  for (int i = 0; i < teamStandings.length; i++) {
    teamStandings[i].place = i + 1;
  }

  return teamStandings;
}

int _maxPlace(List<int> a, List<int> b) {
  int max = 0;
  for (final p in a) {
    if (p > max) max = p;
  }
  for (final p in b) {
    if (p > max) max = p;
  }
  return max;
}
