/// Powerlifting scoring logic (FPU rules).
///
/// Each athlete performs three lifts — squat (присідання), bench press
/// (жим лежачи) and deadlift (станова тяга) — three attempts each. The best
/// valid attempt of each lift is summed into a total. If the squat scores 0
/// (no valid attempt) the athlete is not admitted to the remaining lifts and
/// receives no place. A 0 in the bench press or deadlift still yields a final
/// total and a place.
///
/// Individual placing is done inside each of the seven weight categories by
/// the largest total. If a category (other than 105+) has fewer than five
/// registered athletes its athletes move up into the next heavier category;
/// a 105+ category with fewer than five athletes merges down into 105. When
/// categories are merged the placing is determined by the Wilks formula. A
/// (merged) category that still has fewer than five athletes is not held and
/// no places are awarded in it.
///
/// Ties are broken by lower body weight, then by an earlier lot (жереб).
///
/// Team placing uses the lowest sum of points scored by the three best
/// athletes from three different weight categories (1st place = 1 point, etc.).
/// Missing athletes are charged the last place of the largest category plus one
/// penalty point.
library;

/// The seven official weight categories, lightest to heaviest.
const List<String> kPowerliftingCategories = [
  'до 59 кг',
  'до 66 кг',
  'до 74 кг',
  'до 83 кг',
  'до 93 кг',
  'до 105 кг',
  'понад 105 кг',
];

/// Minimum number of registered athletes for a category to be held.
const int kMinCategorySize = 5;

/// Wilks coefficient for a body weight (kg) and gender (0 = male, 1 = female).
double wilksCoefficient(double bodyWeight, int gender) {
  final double a, b, c, d, e, f;
  if (gender == 1) {
    a = 594.31747775582;
    b = -27.23842536447;
    c = 0.82112226871;
    d = -0.00930733913;
    e = 0.00004731582;
    f = -0.00000009054;
  } else {
    a = -216.0475144;
    b = 16.2606339;
    c = -0.002388645;
    d = -0.00113732;
    e = 0.00000701863;
    f = -0.00000000129;
  }
  final x = bodyWeight;
  final denom =
      a + b * x + c * x * x + d * x * x * x + e * x * x * x * x + f * x * x * x * x * x;
  if (denom == 0) return 0;
  return 500 / denom;
}

/// A single athlete's raw results for individual scoring.
class PowerliftingAthlete {
  final int playerId;
  final int teamId;
  final String teamName;
  final String playerName;
  final String category; // one of kPowerliftingCategories, or '' if unset
  final double bodyWeight; // kg
  final int gender; // 0 male, 1 female
  final int lot; // start order / жереб (0 if unset; smaller = earlier)
  final double bestSquat; // kg, 0 = no valid attempt
  final double bestBench; // kg
  final double bestDeadlift; // kg

  const PowerliftingAthlete({
    required this.playerId,
    required this.teamId,
    required this.teamName,
    required this.playerName,
    required this.category,
    required this.bodyWeight,
    required this.gender,
    required this.lot,
    required this.bestSquat,
    required this.bestBench,
    required this.bestDeadlift,
  });

  /// True when the squat was successfully lifted, so the athlete is admitted to
  /// the rest of the competition and can be placed.
  bool get squatValid => bestSquat > 0;

  /// Final total. Zero (and unplaceable) when the squat scored 0.
  double get total => squatValid ? bestSquat + bestBench + bestDeadlift : 0;

  double get wilks => wilksCoefficient(bodyWeight, gender) * total;

  bool get hasAnyResult =>
      bestSquat != 0 || bestBench != 0 || bestDeadlift != 0;
}

/// Computed individual result for one athlete.
class PowerliftingIndividualResult {
  final PowerliftingAthlete athlete;

  /// The category group the athlete competed in after any merging.
  final String group;

  /// Final place inside the group, or null when not placed.
  final int? place;

  /// Whether the group was ranked by the Wilks formula (merged categories).
  final bool useWilks;

  /// Human readable status when the athlete is not placed.
  final String? statusNote;

  const PowerliftingIndividualResult({
    required this.athlete,
    required this.group,
    required this.place,
    required this.useWilks,
    this.statusNote,
  });
}

/// Computes individual standings grouped by (possibly merged) weight category.
///
/// Returns one [PowerliftingIndividualResult] per athlete that has a known
/// category. Athletes without a category are ignored.
List<PowerliftingIndividualResult> calculateIndividualStandings(
  List<PowerliftingAthlete> athletes,
) {
  // Bucket athletes by their nominal category, preserving canonical order.
  final buckets = <String, List<PowerliftingAthlete>>{
    for (final cat in kPowerliftingCategories) cat: <PowerliftingAthlete>[],
  };
  for (final a in athletes) {
    if (buckets.containsKey(a.category)) {
      buckets[a.category]!.add(a);
    }
  }

  // Categories that became "merged" (mixed body-weight classes) → use Wilks.
  final mergedGroups = <String>{};

  // Cascade light categories (59..93) upward into the next heavier one when a
  // category has fewer than the minimum number of athletes.
  for (int i = 0; i < kPowerliftingCategories.length - 2; i++) {
    final cat = kPowerliftingCategories[i];
    final next = kPowerliftingCategories[i + 1];
    final list = buckets[cat]!;
    if (list.isNotEmpty && list.length < kMinCategorySize) {
      buckets[next]!.addAll(list);
      mergedGroups.add(next);
      buckets[cat] = [];
    }
  }

  // 105+ merges down into 105 when undersized.
  const heaviest = 'понад 105 кг';
  const sub = 'до 105 кг';
  final heaviestList = buckets[heaviest]!;
  if (heaviestList.isNotEmpty && heaviestList.length < kMinCategorySize) {
    buckets[sub]!.addAll(heaviestList);
    mergedGroups.add(sub);
    buckets[heaviest] = [];
  }

  final results = <PowerliftingIndividualResult>[];

  for (final cat in kPowerliftingCategories) {
    final group = buckets[cat]!;
    if (group.isEmpty) continue;

    final useWilks = mergedGroups.contains(cat);

    // A (merged) category with fewer than the minimum is not held.
    if (group.length < kMinCategorySize) {
      for (final a in group) {
        results.add(PowerliftingIndividualResult(
          athlete: a,
          group: cat,
          place: null,
          useWilks: useWilks,
          statusNote: 'Категорія не проводиться (менше $kMinCategorySize)',
        ));
      }
      continue;
    }

    // Split admitted (valid squat) from disqualified athletes.
    final admitted = group.where((a) => a.squatValid).toList();
    final disqualified = group.where((a) => !a.squatValid).toList();

    admitted.sort((a, b) {
      final scoreA = useWilks ? a.wilks : a.total;
      final scoreB = useWilks ? b.wilks : b.total;
      final cmp = scoreB.compareTo(scoreA); // higher score = better
      if (cmp != 0) return cmp;
      // Tie: lower body weight wins.
      final wCmp = a.bodyWeight.compareTo(b.bodyWeight);
      if (wCmp != 0) return wCmp;
      // Then earlier lot (smaller lot number).
      final aLot = a.lot == 0 ? 1 << 30 : a.lot;
      final bLot = b.lot == 0 ? 1 << 30 : b.lot;
      return aLot.compareTo(bLot);
    });

    for (int i = 0; i < admitted.length; i++) {
      results.add(PowerliftingIndividualResult(
        athlete: admitted[i],
        group: cat,
        place: i + 1,
        useWilks: useWilks,
      ));
    }
    for (final a in disqualified) {
      results.add(PowerliftingIndividualResult(
        athlete: a,
        group: cat,
        place: null,
        useWilks: useWilks,
        statusNote: 'Не допущено (0 у присіданні)',
      ));
    }
  }

  return results;
}

class PowerliftingStanding {
  final int teamId;
  final String teamName;
  int totalPoints;
  List<int> places;
  List<String> contributingCategories;
  double totalBodyWeight;
  int rank;
  bool isRemoved;

  PowerliftingStanding({
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

/// Computes the team standings from already-placed individual results.
///
/// Each team contributes its best three results, one from each of three
/// different weight categories. Missing contributions are charged the penalty
/// place (last place of the largest category + 1). The lowest sum wins.
List<PowerliftingStanding> calculateTeamStandings({
  required List<({int teamId, String teamName})> teams,
  required List<PowerliftingIndividualResult> individualResults,
  int maxResultsPerTeam = 3,
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, PowerliftingStanding>{
    for (final t in teams)
      t.teamId: PowerliftingStanding(
        teamId: t.teamId,
        teamName: t.teamName,
        isRemoved: removedTeamIds.contains(t.teamId),
      ),
  };

  // Only placed athletes count.
  final placed =
      individualResults.where((r) => r.place != null).toList(growable: false);

  // Penalty place = size of the largest held group + 1.
  final groupSizes = <String, int>{};
  for (final r in placed) {
    groupSizes[r.group] = (groupSizes[r.group] ?? 0) + 1;
  }
  int maxGroupSize = 0;
  for (final s in groupSizes.values) {
    if (s > maxGroupSize) maxGroupSize = s;
  }
  final penaltyPlace = maxGroupSize + 1;

  // Best (lowest place) result per category for each team.
  final perTeam =
      <int, Map<String, ({int place, double bodyWeight})>>{};
  for (final r in placed) {
    final teamId = r.athlete.teamId;
    if (standings[teamId] == null) continue;
    final byCat = perTeam.putIfAbsent(teamId, () => {});
    final existing = byCat[r.group];
    if (existing == null || r.place! < existing.place) {
      byCat[r.group] = (place: r.place!, bodyWeight: r.athlete.bodyWeight);
    }
  }

  for (final teamId in standings.keys) {
    final byCat = perTeam[teamId];
    if (byCat == null || byCat.isEmpty) continue;

    final entries = byCat.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));

    final places = <int>[];
    final cats = <String>[];
    double weight = 0;
    for (int i = 0; i < maxResultsPerTeam; i++) {
      if (i < entries.length) {
        places.add(entries[i].value.place);
        cats.add(entries[i].key);
        weight += entries[i].value.bodyWeight;
      } else {
        places.add(penaltyPlace);
      }
    }

    standings[teamId]!
      ..places = places
      ..contributingCategories = cats
      ..totalPoints = places.fold(0, (s, p) => s + p)
      ..totalBodyWeight = weight;
  }

  final result = standings.values.toList();
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final aScored = a.totalPoints > 0;
    final bScored = b.totalPoints > 0;
    if (!aScored && !bScored) return a.teamName.compareTo(b.teamName);
    if (!aScored) return 1;
    if (!bScored) return -1;
    final ptsCmp = a.totalPoints.compareTo(b.totalPoints);
    if (ptsCmp != 0) return ptsCmp;
    // Tie: more 1st, then 2nd, then 3rd places, etc.
    for (int i = 1; i <= 50; i++) {
      final aCount = a.countPlace(i);
      final bCount = b.countPlace(i);
      if (aCount != bCount) return bCount.compareTo(aCount);
    }
    // Then lower total body weight of contributing athletes.
    if (a.totalBodyWeight != b.totalBodyWeight &&
        a.totalBodyWeight > 0 &&
        b.totalBodyWeight > 0) {
      return a.totalBodyWeight.compareTo(b.totalBodyWeight);
    }
    return a.teamName.compareTo(b.teamName);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }
  return result;
}
