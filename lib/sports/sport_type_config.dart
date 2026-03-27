enum ScoringStrategy {
  matchPoints, // Standard league table (Futsal, Basketball, etc.)
  placeSum, // Sum of places in categories (Swimming, Athletics, etc.)
  individualMatches, // Team result from board results (Chess, TT)
}

/// Sport-specific configuration for UI labels and behavior.
class SportTypeConfig {
  /// Label for individual playing positions (e.g. "Дошка" for chess, "Ракетка" for table tennis).
  final String boardLabel;

  /// Number of boards/rackets per team.
  final int boardCount;

  /// Whether board 3 (last board) is women-only.
  final bool lastBoardWomenOnly;

  /// Has team cross table.
  final bool hasTeamCrossTable;

  /// Has individual cross tables per board.
  final bool hasBoardCrossTables;

  /// Plural form for "розподіліть по дошках/ракетках".
  final String boardLabelPlural;

  /// Short abbreviation prefix (e.g. "Д" for Дошка, "Р" for Ракетка).
  final String boardAbbrev;

  /// Strategy used for calculating standings.
  final ScoringStrategy scoringStrategy;

  /// Points awarded for various match results.
  final double pointsWin;
  final double pointsDraw;
  final double pointsLoss;
  final double pointsNoShow;

  /// Legacy multiplier for display formatting (1 for chess/checkers, 2 for others).
  final int pointsMultiplier;

  const SportTypeConfig({
    required this.boardLabel,
    this.boardCount = 3,
    this.lastBoardWomenOnly = true,
    this.hasTeamCrossTable = true,
    this.hasBoardCrossTables = true,
    required this.boardLabelPlural,
    required this.boardAbbrev,
    this.scoringStrategy = ScoringStrategy.individualMatches,
    this.pointsWin = 2.0,
    this.pointsDraw = 1.0,
    this.pointsLoss = 0.0,
    this.pointsNoShow = 0.0,
    this.pointsMultiplier = 1,
  });

  /// Tab label: "Дошка 1" or "Ракетка 1", with optional "(жіноча)".
  String tabLabel(int boardNum) {
    if (lastBoardWomenOnly && boardNum == boardCount) {
      return '$boardLabel $boardNum (жіноча)';
    }
    return '$boardLabel $boardNum';
  }

  /// Short tab label without gender suffix (for tab bar).
  String shortTabLabel(int boardNum) => '$boardLabel $boardNum';
}

/// Default config for chess (1).
const chessConfig = SportTypeConfig(
  boardLabel: 'Дошка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'дошках',
  boardAbbrev: 'Д',
  scoringStrategy: ScoringStrategy.individualMatches,
);

/// Config for futsal (2).
const futsalConfig = SportTypeConfig(
  boardLabel: 'Гравець',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'гравцях',
  boardAbbrev: 'Г',
  scoringStrategy: ScoringStrategy.matchPoints,
  pointsWin: 3.0,
  pointsDraw: 1.0,
  pointsLoss: 0.0,
  pointsNoShow: 0.0,
);

/// Config for volleyball (3).
const volleyballConfig = SportTypeConfig(
  boardLabel: 'Корт',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'кортах',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.matchPoints,
  pointsWin: 2.0,
  pointsDraw: 0.0, // No draws in volleyball
  pointsLoss: 1.0,
  pointsNoShow: 0.0,
);

/// Config for basketball (4).
const basketballConfig = SportTypeConfig(
  boardLabel: 'Корт',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'кортах',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.matchPoints,
  pointsWin: 2.0,
  pointsDraw: 0.0, // No draws in basketball (overtime)
  pointsLoss: 1.0,
  pointsNoShow: 0.0,
);

/// Config for streetball (5).
const streetballConfig = SportTypeConfig(
  boardLabel: 'Корт',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'кортах',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.matchPoints,
  pointsWin: 2.0,
  pointsDraw: 0.0,
  pointsLoss: 1.0,
  pointsNoShow: 0.0,
);

/// Config for swimming (6).
const swimmingConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for checkers (7).
const checkersConfig = SportTypeConfig(
  boardLabel: 'Дошка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'дошках',
  boardAbbrev: 'Д',
  scoringStrategy: ScoringStrategy.individualMatches,
);

/// Config for powerlifting (8).
const powerliftingConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for arm wrestling (9).
const armWrestlingConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for athletics (10).
const athleticsConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for table tennis (11).
const tableTennisConfig = SportTypeConfig(
  boardLabel: 'Ракетка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'ракетках',
  boardAbbrev: 'Р',
  scoringStrategy: ScoringStrategy.individualMatches,
);

/// Config for cycling (12).
const cyclingConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for kettlebell sport (13).
const kettlebellConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
  scoringStrategy: ScoringStrategy.placeSum,
);

/// Config for tug of war (14).
const tugOfWarConfig = SportTypeConfig(
  boardLabel: 'Поєдинок',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'поєдинках',
  boardAbbrev: 'П',
  scoringStrategy: ScoringStrategy.matchPoints,
  pointsWin: 2.0,
  pointsDraw: 0.0,
  pointsLoss: 0.0,
  pointsNoShow: 0.0,
);

/// Map type_id → config. Falls back to chess config for unknown types.
SportTypeConfig getConfigForType(int? typeId) {
  switch (typeId) {
    case 1: return chessConfig;
    case 2: return futsalConfig;
    case 3: return volleyballConfig;
    case 4: return basketballConfig;
    case 5: return streetballConfig;
    case 6: return swimmingConfig;
    case 7: return checkersConfig;
    case 8: return powerliftingConfig;
    case 9: return armWrestlingConfig;
    case 10: return athleticsConfig;
    case 11: return tableTennisConfig;
    case 12: return cyclingConfig;
    case 13: return kettlebellConfig;
    case 14: return tugOfWarConfig;
    default: return chessConfig;
  }
}

/// Helper to check sport type by ID.
bool isSwimming(int? typeId) => typeId == 6;
bool isVolleyball(int? typeId) => typeId == 3;
bool isArmWrestling(int? typeId) => typeId == 9;
bool isTableTennis(int? typeId) => typeId == 11;
