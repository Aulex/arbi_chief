/// Volleyball tournament system types.
enum VolleyballTournamentSystem {
  /// Колова система в 1 коло (≤8 teams).
  roundRobin('Колова'),

  /// Змішана система (≥9 teams): subgroups → finals.
  mixed('Змішана');

  final String label;
  const VolleyballTournamentSystem(this.label);
}

/// A single volleyball match between two teams.
class VolleyballMatch {
  final int? id;
  final int tournamentId;

  /// Group name for mixed system (e.g. "А", "Б"), null for round-robin.
  final String? groupName;

  /// Stage: 'group' for group phase, 'final' for final round, 'consolation_9_16', etc.
  final String stage;

  final int homeTeamId;
  final int awayTeamId;

  /// Sets won by each team (0-2 in 3-set format).
  final int homeSets;
  final int awaySets;

  /// Points per set (nullable for unplayed sets).
  final int? set1Home;
  final int? set1Away;
  final int? set2Home;
  final int? set2Away;
  final int? set3Home;
  final int? set3Away;

  /// True if this match is a forfeit (неявка).
  final bool isForfeit;

  const VolleyballMatch({
    this.id,
    required this.tournamentId,
    this.groupName,
    this.stage = 'group',
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeSets = 0,
    this.awaySets = 0,
    this.set1Home,
    this.set1Away,
    this.set2Home,
    this.set2Away,
    this.set3Home,
    this.set3Away,
    this.isForfeit = false,
  });

  /// Display score like "2:0" or "1:2".
  String get scoreDisplay => '$homeSets:$awaySets';

  /// Whether the match has been played (has a result).
  bool get isPlayed => homeSets > 0 || awaySets > 0;

  /// Set scores formatted like "25:20 25:18" or "25:20 20:25 15:10".
  String get setScoresDisplay {
    final parts = <String>[];
    if (set1Home != null && set1Away != null) parts.add('$set1Home:$set1Away');
    if (set2Home != null && set2Away != null) parts.add('$set2Home:$set2Away');
    if (set3Home != null && set3Away != null) parts.add('$set3Home:$set3Away');
    return parts.join(' ');
  }

  /// Total points scored by home team across all sets.
  int get homePointsTotal =>
      (set1Home ?? 0) + (set2Home ?? 0) + (set3Home ?? 0);

  /// Total points scored by away team across all sets.
  int get awayPointsTotal =>
      (set1Away ?? 0) + (set2Away ?? 0) + (set3Away ?? 0);

  Map<String, dynamic> toMap() => {
        if (id != null) 'vm_id': id,
        't_id': tournamentId,
        'group_name': groupName,
        'stage': stage,
        'home_team_id': homeTeamId,
        'away_team_id': awayTeamId,
        'home_sets': homeSets,
        'away_sets': awaySets,
        'set1_home': set1Home,
        'set1_away': set1Away,
        'set2_home': set2Home,
        'set2_away': set2Away,
        'set3_home': set3Home,
        'set3_away': set3Away,
        'is_forfeit': isForfeit ? 1 : 0,
      };

  factory VolleyballMatch.fromMap(Map<String, dynamic> map) => VolleyballMatch(
        id: map['vm_id'] as int?,
        tournamentId: map['t_id'] as int,
        groupName: map['group_name'] as String?,
        stage: (map['stage'] as String?) ?? 'group',
        homeTeamId: map['home_team_id'] as int,
        awayTeamId: map['away_team_id'] as int,
        homeSets: (map['home_sets'] as int?) ?? 0,
        awaySets: (map['away_sets'] as int?) ?? 0,
        set1Home: map['set1_home'] as int?,
        set1Away: map['set1_away'] as int?,
        set2Home: map['set2_home'] as int?,
        set2Away: map['set2_away'] as int?,
        set3Home: map['set3_home'] as int?,
        set3Away: map['set3_away'] as int?,
        isForfeit: (map['is_forfeit'] as int?) == 1,
      );

  VolleyballMatch copyWith({
    int? id,
    int? tournamentId,
    String? groupName,
    String? stage,
    int? homeTeamId,
    int? awayTeamId,
    int? homeSets,
    int? awaySets,
    int? set1Home,
    int? set1Away,
    int? set2Home,
    int? set2Away,
    int? set3Home,
    int? set3Away,
    bool? isForfeit,
  }) =>
      VolleyballMatch(
        id: id ?? this.id,
        tournamentId: tournamentId ?? this.tournamentId,
        groupName: groupName ?? this.groupName,
        stage: stage ?? this.stage,
        homeTeamId: homeTeamId ?? this.homeTeamId,
        awayTeamId: awayTeamId ?? this.awayTeamId,
        homeSets: homeSets ?? this.homeSets,
        awaySets: awaySets ?? this.awaySets,
        set1Home: set1Home ?? this.set1Home,
        set1Away: set1Away ?? this.set1Away,
        set2Home: set2Home ?? this.set2Home,
        set2Away: set2Away ?? this.set2Away,
        set3Home: set3Home ?? this.set3Home,
        set3Away: set3Away ?? this.set3Away,
        isForfeit: isForfeit ?? this.isForfeit,
      );
}

/// Team standings entry for volleyball.
class VolleyballTeamStanding {
  final int teamId;
  final String teamName;

  /// Number of matches played.
  final int played;

  /// Number of wins.
  final int wins;

  /// Number of losses.
  final int losses;

  /// Points: win=2, loss=1, no-show=0.
  final int points;

  /// Total sets won.
  final int setsWon;

  /// Total sets lost.
  final int setsLost;

  /// Total rally points won.
  final int pointsWon;

  /// Total rally points lost.
  final int pointsLost;

  /// Number of forfeits (неявки).
  final int forfeits;

  /// Final place in standings.
  final int place;

  /// Set ratio for display.
  String get setRatio => '$setsWon:$setsLost';

  /// Points ratio for display.
  String get pointsRatio => '$pointsWon:$pointsLost';

  const VolleyballTeamStanding({
    required this.teamId,
    required this.teamName,
    this.played = 0,
    this.wins = 0,
    this.losses = 0,
    this.points = 0,
    this.setsWon = 0,
    this.setsLost = 0,
    this.pointsWon = 0,
    this.pointsLost = 0,
    this.forfeits = 0,
    this.place = 0,
  });
}

/// A group in a mixed-system tournament.
class VolleyballGroup {
  final String name;
  final List<int> teamIds;
  final List<VolleyballMatch> matches;
  final List<VolleyballTeamStanding> standings;

  const VolleyballGroup({
    required this.name,
    required this.teamIds,
    required this.matches,
    required this.standings,
  });
}
