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

/// Config for volleyball (team-vs-team, no boards).
const volleyballConfig = SportTypeConfig(
  boardLabel: 'Корт',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: true,
  hasBoardCrossTables: false,
  boardLabelPlural: 'кортах',
  boardAbbrev: 'К',
);

/// Config for swimming (no boards, time-based).
const swimmingConfig = SportTypeConfig(
  boardLabel: 'Категорія',
  boardCount: 0,
  lastBoardWomenOnly: false,
  hasTeamCrossTable: false,
  hasBoardCrossTables: false,
  boardLabelPlural: 'категоріях',
  boardAbbrev: 'К',
);

/// Returns true if the sport type is swimming (Плавання).
bool isSwimming(int? typeId) => typeId == 6;

/// Returns true if the sport type is volleyball (Волейбол).
bool isVolleyball(int? typeId) => typeId == 3;

/// Map type_id → config. Falls back to chess config for unknown types.
SportTypeConfig getConfigForType(int? typeId) {
  switch (typeId) {
    case 1: return chessConfig;       // Шахи
    case 3: return volleyballConfig;  // Волейбол
    case 6: return swimmingConfig;    // Плавання
    case 7: return checkersConfig;    // Шашки
    case 11: return tableTennisConfig; // Настільний теніс
    default: return chessConfig;
  }
}
