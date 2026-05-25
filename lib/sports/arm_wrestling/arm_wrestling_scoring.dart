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
  final int? playerNumber;
  final double? weight;
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
    this.playerNumber,
    this.weight,
    this.place = 0,
  });
}

/// Minimal player descriptor needed by [calculateCategoryStandings].
class ArmWrestlingPlayer {
  final int playerId;
  final String playerName;
  final String teamName;
  final int teamId;
  final int? playerNumber;
  final double? weight;
  const ArmWrestlingPlayer({
    required this.playerId,
    required this.playerName,
    required this.teamName,
    required this.teamId,
    this.playerNumber,
    this.weight,
  });
}

/// Calculate individual standings for a weight category.
/// [results] maps playerId → opponentId → result (1.0=win, 0.0=loss).
List<ArmWrestlingStanding> calculateCategoryStandings({
  required List<ArmWrestlingPlayer> players,
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
      playerNumber: p.playerNumber,
      weight: p.weight,
      wins: wins,
      losses: losses,
      gamesPlayed: playerResults.length,
    ));
  }

  // Sort by wins, then iteratively resolve ties by mini-league head-to-head.
  standings.sort((a, b) => b.wins.compareTo(a.wins));
  _resolveTiesByMiniLeague(standings, results);

  for (int i = 0; i < standings.length; i++) {
    standings[i].place = i + 1;
  }

  return standings;
}

/// Resolves groups of standings tied on `wins` by replaying the games among
/// just those players (mini-league): more wins inside the tied group ranks
/// higher; remaining ties recurse, falling back to fewer losses overall.
void _resolveTiesByMiniLeague(
  List<ArmWrestlingStanding> standings,
  Map<int, Map<int, double>> results,
) {
  int i = 0;
  while (i < standings.length) {
    int j = i + 1;
    while (j < standings.length && standings[j].wins == standings[i].wins) {
      j++;
    }
    if (j - i > 1) {
      final group = standings.sublist(i, j);
      final groupIds = group.map((s) => s.playerId).toSet();
      // Mini-league wins inside the group.
      final miniWins = <int, int>{
        for (final s in group) s.playerId: 0,
      };
      for (final s in group) {
        final opponents = results[s.playerId] ?? const <int, double>{};
        for (final entry in opponents.entries) {
          if (groupIds.contains(entry.key) && entry.value == 1.0) {
            miniWins[s.playerId] = (miniWins[s.playerId] ?? 0) + 1;
          }
        }
      }
      group.sort((a, b) {
        final mw = (miniWins[b.playerId] ?? 0).compareTo(miniWins[a.playerId] ?? 0);
        if (mw != 0) return mw;
        return a.losses.compareTo(b.losses);
      });
      for (int k = 0; k < group.length; k++) {
        standings[i + k] = group[k];
      }
    }
    i = j;
  }
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
  /// Best placement per category, sorted (for contributor selection).
  final List<int> allPlacements;
  /// ALL individual placements across all categories, sorted (for tiebreakers).
  final List<int> allIndividualPlacements;
  int place;

  ArmWrestlingTeamStanding({
    required this.teamId,
    required this.teamName,
    required this.totalPoints,
    required this.contributors,
    this.totalWeight = 0.0,
    this.allPlacements = const [],
    this.allIndividualPlacements = const [],
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
  Map<int, double> playerWeights = const {},
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
    // Collect best placement per category and all individual placements
    final bestPerCategory = <int, ({int playerId, int place, String categoryLabel})>{};
    final allPlacements = <int>[];
    final allIndividualPlacements = <int>[];

    for (final catEntry in categoryStandings.entries) {
      final categoryId = catEntry.key;
      final standings = catEntry.value;
      final categoryLabel = WeightCategory.fromId(categoryId)?.label ?? 'Категорія $categoryId';

      // Find best placement for this team in this category
      int? bestPlace;
      int? bestPlayerId;
      for (final s in standings) {
        if (s.teamId == teamId) {
          allIndividualPlacements.add(s.place);
          if (bestPlace == null || s.place < bestPlace) {
            bestPlace = s.place;
            bestPlayerId = s.playerId;
          }
        }
      }
      if (bestPlace != null) {
        bestPerCategory[categoryId] = (playerId: bestPlayerId!, place: bestPlace, categoryLabel: categoryLabel);
        allPlacements.add(bestPlace);
      }
    }

    // Select 3 best placements from 3 different categories
    final sortedCategories = bestPerCategory.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));

    final contributors = <({int categoryId, String categoryLabel, int place})>[];
    int totalPoints = 0;
    double totalWeight = 0.0;

    for (int i = 0; i < 3; i++) {
      if (i < sortedCategories.length) {
        final entry = sortedCategories[i];
        contributors.add((
          categoryId: entry.key,
          categoryLabel: entry.value.categoryLabel,
          place: entry.value.place,
        ));
        totalPoints += entry.value.place;
        totalWeight += playerWeights[entry.value.playerId] ?? 0.0;
      } else {
        // Missing participant: penalty = last place in largest category + 1
        totalPoints += penaltyPlace;
      }
    }

    teamStandings.add(ArmWrestlingTeamStanding(
      teamId: teamId,
      teamName: teamNames[teamId] ?? '',
      totalPoints: totalPoints,
      contributors: contributors,
      totalWeight: totalWeight,
      allPlacements: allPlacements..sort(),
      allIndividualPlacements: allIndividualPlacements..sort(),
    ));
  }

  // Sort teams
  teamStandings.sort((a, b) {
    // Primary: lowest total points
    if (a.totalPoints != b.totalPoints) {
      return a.totalPoints.compareTo(b.totalPoints);
    }

    // Tiebreaker 1: more 1st, 2nd, 3rd ... places among the 3 contributors.
    final aContribPlaces = a.contributors.map((c) => c.place).toList();
    final bContribPlaces = b.contributors.map((c) => c.place).toList();
    final maxPlace = _maxPlace(aContribPlaces, bContribPlaces);
    for (int p = 1; p <= maxPlace; p++) {
      final aCount = aContribPlaces.where((x) => x == p).length;
      final bCount = bContribPlaces.where((x) => x == p).length;
      if (aCount != bCount) return bCount.compareTo(aCount); // more is better
    }

    // Tiebreaker 2: better results in other categories not in team standing
    // (one best result per non-contributing category)
    final aContribCats = a.contributors.map((c) => c.categoryId).toSet();
    final bContribCats = b.contributors.map((c) => c.categoryId).toSet();
    final aOther = <int>[];
    final bOther = <int>[];
    for (final catEntry in categoryStandings.entries) {
      if (!aContribCats.contains(catEntry.key)) {
        int? best;
        for (final s in catEntry.value) {
          if (s.teamId == a.teamId && (best == null || s.place < best)) {
            best = s.place;
          }
        }
        if (best != null) aOther.add(best);
      }
      if (!bContribCats.contains(catEntry.key)) {
        int? best;
        for (final s in catEntry.value) {
          if (s.teamId == b.teamId && (best == null || s.place < best)) {
            best = s.place;
          }
        }
        if (best != null) bOther.add(best);
      }
    }
    aOther.sort();
    bOther.sort();
    final otherLen = aOther.length < bOther.length ? aOther.length : bOther.length;
    for (int i = 0; i < otherLen; i++) {
      if (aOther[i] != bOther[i]) return aOther[i].compareTo(bOther[i]);
    }

    // Tiebreaker 3: better results from ALL weight categories (all individual placements)
    final aAll = a.allIndividualPlacements;
    final bAll = b.allIndividualPlacements;
    final allLen = aAll.length < bAll.length ? aAll.length : bAll.length;
    for (int i = 0; i < allLen; i++) {
      if (aAll[i] != bAll[i]) return aAll[i].compareTo(bAll[i]);
    }
    if (aAll.length != bAll.length) return bAll.length.compareTo(aAll.length);

    // Tiebreaker 4: lower total weight of 3 contributors
    if (a.totalWeight > 0 && b.totalWeight > 0 && a.totalWeight != b.totalWeight) {
      return a.totalWeight.compareTo(b.totalWeight);
    }

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
