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

  const SportTypeConfig({
    required this.boardLabel,
    this.boardCount = 3,
    this.lastBoardWomenOnly = true,
    this.hasTeamCrossTable = true,
    this.hasBoardCrossTables = true,
    required this.boardLabelPlural,
    required this.boardAbbrev,
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

/// Default config for chess.
const chessConfig = SportTypeConfig(
  boardLabel: 'Дошка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'дошках',
  boardAbbrev: 'Д',
);

/// Config for table tennis.
const tableTennisConfig = SportTypeConfig(
  boardLabel: 'Ракетка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'ракетках',
  boardAbbrev: 'Р',
);

/// Config for checkers.
const checkersConfig = SportTypeConfig(
  boardLabel: 'Дошка',
  boardCount: 3,
  lastBoardWomenOnly: true,
  hasTeamCrossTable: true,
  hasBoardCrossTables: true,
  boardLabelPlural: 'дошках',
  boardAbbrev: 'Д',
);

/// Map type_id → config. Falls back to chess config for unknown types.
SportTypeConfig getConfigForType(int? typeId) {
  switch (typeId) {
    case 1: return chessConfig;       // Шахи
    case 7: return checkersConfig;    // Шашки
    case 11: return tableTennisConfig; // Настільний теніс
    default: return chessConfig;
  }
}
