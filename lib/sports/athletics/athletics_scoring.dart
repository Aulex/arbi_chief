/// Athletics scoring logic.
///
/// Rules: 1st place = 1pt, 2nd = 2pts, etc. Lower total sum wins.
/// Tie-breakers: Most 1st places, then most 2nd places, etc.

class AthleticsStanding {
  final int teamId;
  final String teamName;
  int totalPoints;
  List<int> places;
  int rank;
  bool isRemoved;

  AthleticsStanding({
    required this.teamId,
    required this.teamName,
    this.totalPoints = 0,
    this.places = const [],
    this.rank = 0,
    this.isRemoved = false,
  });

  int countPlace(int p) => places.where((x) => x == p).length;
}

List<AthleticsStanding> calculateStandings({
  required List<({int teamId, String teamName})> teams,
  required List<({int teamId, int place})> individualResults,
  int? maxResultsPerTeam = 3, // Athletics typically counts top 3 results
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, AthleticsStanding>{};

  for (final team in teams) {
    standings[team.teamId] = AthleticsStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
  }

  final teamResults = <int, List<int>>{};
  for (final res in individualResults) {
    teamResults.putIfAbsent(res.teamId, () => []).add(res.place);
  }

  for (final teamId in teamResults.keys) {
    if (standings[teamId] == null) continue;
    final results = teamResults[teamId]!..sort();
    final bestResults = maxResultsPerTeam != null && results.length > maxResultsPerTeam
        ? results.take(maxResultsPerTeam).toList()
        : results;
    standings[teamId]!.places = bestResults;
    standings[teamId]!.totalPoints = bestResults.fold(0, (sum, p) => sum + p);
  }

  final result = standings.values.toList();
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
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
