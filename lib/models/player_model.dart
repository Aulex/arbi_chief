class Player {
  final int? player_id;
  final String player_surname;
  final String player_name;
  final String player_lastname;
  final int player_gender;
  final String player_date_birth; // Stored as yyyy-mm-dd in SQLite
  final int? t_type;
  final int? entity_id;
  final String? sync_uid;

  const Player({
    this.player_id,
    required this.player_surname,
    required this.player_name,
    required this.player_lastname,
    required this.player_gender,
    required this.player_date_birth,
    this.t_type,
    this.entity_id,
    this.sync_uid,
  });

  // --- Date Helpers ---

  // Converts DB format (1995-05-15) to UI format (15.05.1995) 🖥️
  String get birthDateForUI {
    if (player_date_birth.isEmpty || !player_date_birth.contains('-'))
      return "";
    List<String> parts = player_date_birth.split('-');
    return "${parts[2]}.${parts[1]}.${parts[0]}";
  }

  // Converts UI format (15.05.1995) to DB format (1995-05-15) 📥
  static String formatForDB(String uiDate) {
    if (!uiDate.contains('.')) return uiDate;
    List<String> parts = uiDate.split('.');
    return "${parts[2]}-${parts[1]}-${parts[0]}";
  }

  // --- Gender Detection ---

  /// Detect gender from Ukrainian patronymic (по батькові) or name.
  /// Returns 0 for male, 1 for female.
  static int detectGender(String name, String lastname) {
    final lc = lastname.toLowerCase().trim();
    // Patronymic is the most reliable indicator
    if (lc.isNotEmpty) {
      if (lc.endsWith('ович') || lc.endsWith('ич') || lc.endsWith('йович')) return 0;
      if (lc.endsWith('івна') || lc.endsWith('ївна') || lc.endsWith('інна')) return 1;
    }
    // Fallback: detect by first name
    final nc = name.toLowerCase().trim();
    if (nc.isNotEmpty) {
      // Common female endings
      if (nc.endsWith('а') || nc.endsWith('я') || nc.endsWith('і')) return 1;
      // Exceptions: male names ending in -а (Микола, Ілля, Кузьма)
      const maleExceptions = ['микола', 'ілля', 'кузьма', 'хома', 'сава', 'лука', 'нікіта', 'данила'];
      if (maleExceptions.contains(nc)) return 0;
    }
    return 0; // default male
  }

  // --- Logic Helpers ---

  String get fullName =>
      "$player_surname $player_name $player_lastname"
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  Player copyWith({
    int? player_id,
    String? player_surname,
    String? player_name,
    String? player_lastname,
    int? player_gender,
    String? player_date_birth,
    int? t_type,
    int? entity_id,
  }) {
    return Player(
      player_id: player_id ?? this.player_id,
      player_surname: player_surname ?? this.player_surname,
      player_name: player_name ?? this.player_name,
      player_lastname: player_lastname ?? this.player_lastname,
      player_gender: player_gender ?? this.player_gender,
      player_date_birth: player_date_birth ?? this.player_date_birth,
      t_type: t_type ?? this.t_type,
      entity_id: entity_id ?? this.entity_id,
    );
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      player_id: json['player_id'] as int?,
      player_surname: json['player_surname'] as String? ?? '',
      player_name: json['player_name'] as String? ?? '',
      player_lastname: json['player_lastname'] as String? ?? '',
      player_gender: json['player_gender'] as int? ?? 0,
      player_date_birth: json['player_date_birth'] as String? ?? '',
      t_type: json['t_type'] as int?,
      entity_id: json['entity_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': player_id,
      'player_surname': player_surname,
      'player_name': player_name,
      'player_lastname': player_lastname,
      'player_gender': player_gender,
      'player_date_birth': player_date_birth,
      't_type': t_type,
      'entity_id': entity_id,
    };
  }
}
