/// Cycling scoring logic.
///
/// Rules: 1st place = 1pt, 2nd = 2pts, etc. Lower total sum wins.
/// Team scoring: 3 best results from 3 different categories.
/// Missing categories penalised with (largest category size + 1).
/// Tie-breakers: Most 1st places, then most 2nd places, etc.

class CyclingStanding {
  final int teamId;
  final String teamName;
  int totalPoints;
  List<int> places;
  List<String> contributingCategories;
  int rank;
  bool isRemoved;

  CyclingStanding({
    required this.teamId,
    required this.teamName,
    this.totalPoints = 0,
    this.places = const [],
    this.contributingCategories = const [],
    this.rank = 0,
    this.isRemoved = false,
  });

  int countPlace(int p) => places.where((x) => x == p).length;
}

List<CyclingStanding> calculateStandings({
  required List<({int teamId, String teamName})> teams,
  required List<({int teamId, int place, String? category})> individualResults,
  int maxResultsPerTeam = 3,
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, CyclingStanding>{};

  for (final team in teams) {
    standings[team.teamId] = CyclingStanding(
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

  final teamResults = <int, List<({int place, String category})>>{};
  for (final res in individualResults) {
    teamResults
        .putIfAbsent(res.teamId, () => [])
        .add((place: res.place, category: res.category ?? ''));
  }

  for (final teamId in teamResults.keys) {
    if (standings[teamId] == null) continue;

    final results = teamResults[teamId]!;
    final hasCategories = results.any((r) => r.category.isNotEmpty);

    List<int> bestPlaces;
    List<String> contribCats = [];

    if (hasCategories) {
      final bestPerCategory = <String, int>{};
      for (final r in results) {
        final cat = r.category;
        if (!bestPerCategory.containsKey(cat) || r.place < bestPerCategory[cat]!) {
          bestPerCategory[cat] = r.place;
        }
      }
      final sortedCats = bestPerCategory.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      bestPlaces = [];
      for (int i = 0; i < maxResultsPerTeam; i++) {
        if (i < sortedCats.length) {
          bestPlaces.add(sortedCats[i].value);
          contribCats.add(sortedCats[i].key);
        } else {
          bestPlaces.add(penaltyPlace);
        }
      }
    } else {
      final sorted = results.map((r) => r.place).toList()..sort();
      bestPlaces = sorted.length > maxResultsPerTeam
          ? sorted.take(maxResultsPerTeam).toList()
          : sorted;
    }

    standings[teamId]!.places = bestPlaces;
    standings[teamId]!.contributingCategories = contribCats;
    standings[teamId]!.totalPoints = bestPlaces.fold(0, (sum, p) => sum + p);
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
    return a.teamName.compareTo(b.teamName);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }
  return result;
}
