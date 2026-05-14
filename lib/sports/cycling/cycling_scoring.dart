// Cycling scoring logic (cross-country marathon).
//
// Rules:
// - Single mass-start distance (~30 km); winners per category are decided by
//   raw time (no age coefficients).
// - Individual: 1st place = 1pt, 2nd = 2pts, etc. (within each age/gender category)
// - Team scoring: 3 best results (2 men + 1 woman) from different age categories
// - Missing entries penalised with (largest category size + 1)
// - Tie-breakers (in order):
//   1) More 1st places, then 2nd, 3rd, etc.
//   2) Lowest sum of times of 3 contributing participants
//   3) Largest sum of ages of 3 contributing participants
//   4) Best result among women in scoring
//
// Five categories (no Ж50 — Ж49 covers all women 35+):
//   Ч35, Ч49, Ч50, Ж35, Ж49
// Category merging: if <5 participants in a category, merge into younger
//   category (m50→m49→m35, f49→f35).
// Category cancellation: if <=4 participants, the category is not "held" but
//   its athletes still contribute places to their team's scoring.
//
// Age flexibility:
// - Participants 35+ may compete in Ч35 / Ж35
// - Participants 50+ may compete in Ч35, Ч49
// - Women may replace men only in their own or younger age categories
//
// Main scoring logic is implemented in CyclingService.getTeamStandings().
// This file is kept for documentation and for parity with the
// sport_type_config.dart pattern used by the other sport modules.

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
