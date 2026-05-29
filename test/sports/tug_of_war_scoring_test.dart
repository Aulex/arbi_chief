import 'package:flutter_test/flutter_test.dart';
import 'package:arbi_chief/sports/tug_of_war/tug_of_war_scoring.dart';

void main() {
  // Helper: teams keyed so teamId == entityId for readability.
  List<({int teamId, String teamName, int? entityId, double? weight})> mkTeams(
    Map<int, ({String name, double? weight})> spec,
  ) =>
      [
        for (final e in spec.entries)
          (teamId: e.key, teamName: e.value.name, entityId: e.key, weight: e.value.weight),
      ];

  group('scoring points (Win=2, Loss=1, No-show=0)', () {
    test('win and loss award 2 and 1 points', () {
      final s = calculateStandings(
        teams: mkTeams({1: (name: 'A', weight: null), 2: (name: 'B', weight: null)}),
        games: {(1, 2): '1:0'},
      );
      final a = s.firstWhere((x) => x.teamId == 1);
      final b = s.firstWhere((x) => x.teamId == 2);
      expect(a.matchPoints, 2);
      expect(a.wins, 1);
      expect(b.matchPoints, 1);
      expect(b.losses, 1);
      expect(a.rank, 1);
      expect(b.rank, 2);
    });

    test('no-show gives 0 points to absentee and a win to the opponent', () {
      final s = calculateStandings(
        teams: mkTeams({1: (name: 'A', weight: null), 2: (name: 'B', weight: null)}),
        games: {(1, 2): 'N:W'}, // team A (entity 1) did not show up
      );
      final a = s.firstWhere((x) => x.teamId == 1);
      final b = s.firstWhere((x) => x.teamId == 2);
      expect(a.matchPoints, 0);
      expect(a.noShows, 1);
      expect(a.losses, 1);
      expect(b.matchPoints, 2);
      expect(b.wins, 1);
    });
  });

  group('tie-breakers', () {
    test('2-way tie broken by head-to-head', () {
      // A and B both finish on 4 pts; A beat B in their direct meeting.
      final s = calculateStandings(
        teams: mkTeams({
          1: (name: 'A', weight: null),
          2: (name: 'B', weight: null),
          3: (name: 'C', weight: 700),
          4: (name: 'D', weight: 750),
        }),
        games: {
          (1, 2): '1:0', // A>B  -> A+2, B+1
          (1, 3): '1:0', // A>C  -> A+2  => A = 4
          (2, 3): '1:0', // B>C  -> B+2
          (2, 4): '0:1', // B<D  -> B+1  => B = 4 ; D+2
        },
      );
      // A=4, B=4 (A wins H2H), C=2, D=2 (C lighter).
      expect(s.map((x) => x.teamId).toList(), [1, 2, 3, 4]);
    });

    test('3-way head-to-head cycle falls through to lower weight', () {
      // A beat B, B beat C, C beat A. Each also beats D so all three sit on
      // equal points and form a cyclic head-to-head — must resolve by weight.
      final s = calculateStandings(
        teams: mkTeams({
          1: (name: 'A', weight: 790),
          2: (name: 'B', weight: 770),
          3: (name: 'C', weight: 780),
          4: (name: 'D', weight: 800),
        }),
        games: {
          (1, 2): '1:0', // A>B
          (2, 3): '1:0', // B>C
          (3, 1): '1:0', // C>A
          (1, 4): '1:0',
          (2, 4): '1:0',
          (3, 4): '1:0',
        },
      );
      // A, B, C each: 2 (vs D) + win + loss within cycle => same points.
      // H2H within {A,B,C} is a 3-cycle (each 2+1), so weight decides: B(770) < C(780) < A(790).
      final top3 = s.where((x) => x.teamId != 4).map((x) => x.teamId).toList();
      expect(top3, [2, 3, 1]);
      expect(s.firstWhere((x) => x.teamId == 4).rank, 4);
    });

    test('equal points and no head-to-head separation use lower weight', () {
      final s = calculateStandings(
        teams: mkTeams({
          1: (name: 'A', weight: 800),
          2: (name: 'B', weight: 700),
        }),
        games: const {}, // never met
      );
      expect(s.map((x) => x.teamId).toList(), [2, 1]); // lighter first
    });
  });

  group('removal (2nd no-show / unsporting conduct)', () {
    test('removed team is annulled: no points, rank 0, results void for opponents', () {
      final s = calculateStandings(
        teams: mkTeams({
          1: (name: 'A', weight: null),
          2: (name: 'B', weight: null),
        }),
        games: {(2, 1): '1:0'}, // B had beaten A
        removedTeamIds: {1},
      );
      final a = s.firstWhere((x) => x.teamId == 1);
      final b = s.firstWhere((x) => x.teamId == 2);
      expect(a.isRemoved, true);
      expect(a.rank, 0);
      expect(a.matchPoints, 0);
      // B's win over the removed team must not count.
      expect(b.matchPoints, 0);
      expect(b.rank, 1);
    });
  });

  group('2nd no-show reminder flag', () {
    test('flag raised at two no-shows, not before', () {
      final s = calculateStandings(
        teams: mkTeams({
          1: (name: 'A', weight: null),
          2: (name: 'B', weight: null),
          3: (name: 'C', weight: null),
        }),
        games: {(1, 2): 'N:W', (1, 3): 'N:W'}, // A missed two bouts
      );
      final a = s.firstWhere((x) => x.teamId == 1);
      expect(a.noShows, 2);
      expect(a.mustBeRemovedForNoShows, true);
      expect(s.firstWhere((x) => x.teamId == 2).mustBeRemovedForNoShows, false);
    });
  });
}
