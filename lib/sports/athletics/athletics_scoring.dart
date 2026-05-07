// Athletics scoring logic.
//
// Rules:
// - Individual: 1st place = 1pt, 2nd = 2pts, etc. (within each age/gender category)
// - Team scoring: 3 best results (2 men + 1 woman) from different age categories
// - Missing categories penalised with (largest category size + 1)
// - Tie-breakers (in order):
//   1) More 1st places, then 2nd, 3rd, etc.
//   2) Lowest sum of times of 3 contributing participants
//   3) Largest sum of ages of 3 contributing participants
//   4) Best result among women in scoring
//
// Category merging: if <5 participants in a category, merge into younger category.
// Category cancellation: if <=4 participants (including base categories), don't run.
//
// Age flexibility:
// - Participants 35+ may compete in Ч35/Ж35
// - Participants 50+ may compete in Ч35, Ч49 / Ж35, Ж49
// - Women may replace men only in their own or younger age categories

// Main scoring logic is implemented in AthleticsService.getTeamStandings()
// This file is kept for compatibility with the sport_type_config.dart pattern.

class AthleticsStanding {
  final int teamId;
  final String teamName;
  int totalPoints;
  List<int> places;
  List<String> contributingCategories;
  int rank;
  bool isRemoved;

  AthleticsStanding({
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
