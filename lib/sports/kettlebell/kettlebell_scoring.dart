/// Kettlebell sport scoring logic.
///
/// Rules: 1st place = 1pt, 2nd = 2pts, etc. Lower total sum wins.
/// Team scoring: 3 best results from 3 different categories.
/// Missing categories penalised with (largest category size + 1).
/// Tie-breakers: Most 1st places, then total body weight of 3 athletes (lower is better).
///
/// Kettlebell weight coefficients (for future use with raw results):
///   8kg = 0.35, 16kg = 0.55, 24kg = 1.0, 32kg = 1.25

const kettlebellWeightCoefficients = <int, double>{
  8: 0.35,
  16: 0.55,
  24: 1.0,
  32: 1.25,
};

class KettlebellStanding {
  final int teamId;
  final String teamName;
  int totalPoints;
  List<int> places;
  List<String> contributingCategories;
  double totalBodyWeight;
  int rank;
  bool isRemoved;

  KettlebellStanding({
    required this.teamId,
    required this.teamName,
    this.totalPoints = 0,
    this.places = const [],
    this.contributingCategories = const [],
    this.totalBodyWeight = 0.0,
    this.rank = 0,
    this.isRemoved = false,
  });

  int countPlace(int p) => places.where((x) => x == p).length;
}

List<KettlebellStanding> calculateStandings({
  required List<({int teamId, String teamName})> teams,
  required List<({int teamId, int place, String? category, int? playerId})> individualResults,
  int maxResultsPerTeam = 3,
  Set<int> removedTeamIds = const {},
  Map<int, double> playerWeights = const {},
}) {
  final standings = <int, KettlebellStanding>{};

  for (final team in teams) {
    standings[team.teamId] = KettlebellStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
  }

  final categorySizes = <String, int>{};
  for (final res in individualResults) {
    final cat = res.category ?? '';
    categorySizes[cat] = (categorySizes[cat] ?? 0) + 1;
  }
  int maxCategorySize = 0;
  for (final size in categorySizes.values) {
    if (size > maxCategorySize) maxCategorySize = size;
  }
  final penaltyPlace = maxCategorySize + 1;

  final teamResults = <int, List<({int place, String category, int? playerId})>>{};
  for (final res in individualResults) {
    teamResults
        .putIfAbsent(res.teamId, () => [])
        .add((place: res.place, category: res.category ?? '', playerId: res.playerId));
  }

  for (final teamId in teamResults.keys) {
    if (standings[teamId] == null) continue;

    final results = teamResults[teamId]!;
    final hasCategories = results.any((r) => r.category.isNotEmpty);

    List<int> bestPlaces;
    List<String> contribCats = [];
    double totalWeight = 0.0;

    if (hasCategories) {
      final bestPerCategory = <String, ({int place, int? playerId})>{};
      for (final r in results) {
        final cat = r.category;
        if (!bestPerCategory.containsKey(cat) || r.place < bestPerCategory[cat]!.place) {
          bestPerCategory[cat] = (place: r.place, playerId: r.playerId);
        }
      }
      final sortedCats = bestPerCategory.entries.toList()
        ..sort((a, b) => a.value.place.compareTo(b.value.place));
      bestPlaces = [];
      for (int i = 0; i < maxResultsPerTeam; i++) {
        if (i < sortedCats.length) {
          bestPlaces.add(sortedCats[i].value.place);
          contribCats.add(sortedCats[i].key);
          final pid = sortedCats[i].value.playerId;
          if (pid != null && playerWeights.containsKey(pid)) {
            totalWeight += playerWeights[pid]!;
          }
        } else {
          bestPlaces.add(penaltyPlace);
        }
      }
    } else {
      final sorted = results.toList()..sort((a, b) => a.place.compareTo(b.place));
      bestPlaces = [];
      for (int i = 0; i < sorted.length && (i < maxResultsPerTeam); i++) {
        bestPlaces.add(sorted[i].place);
        final pid = sorted[i].playerId;
        if (pid != null && playerWeights.containsKey(pid)) {
          totalWeight += playerWeights[pid]!;
        }
      }
    }

    standings[teamId]!.places = bestPlaces;
    standings[teamId]!.contributingCategories = contribCats;
    standings[teamId]!.totalPoints = bestPlaces.fold(0, (sum, p) => sum + p);
    standings[teamId]!.totalBodyWeight = totalWeight;
  }

  final result = standings.values.toList();
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    if (a.totalPoints == 0 && b.totalPoints == 0) return a.teamName.compareTo(b.teamName);
    if (a.totalPoints == 0) return 1;
    if (b.totalPoints == 0) return -1;
    final ptsCmp = a.totalPoints.compareTo(b.totalPoints);
    if (ptsCmp != 0) return ptsCmp;
    for (int i = 1; i <= 50; i++) {
      final aCount = a.countPlace(i);
      final bCount = b.countPlace(i);
      if (aCount != bCount) return bCount.compareTo(aCount);
    }
    // Tiebreaker: lower total body weight of contributing athletes
    if (a.totalBodyWeight != b.totalBodyWeight && a.totalBodyWeight > 0 && b.totalBodyWeight > 0) {
      return a.totalBodyWeight.compareTo(b.totalBodyWeight);
    }
    return a.teamName.compareTo(b.teamName);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }
  return result;
}
