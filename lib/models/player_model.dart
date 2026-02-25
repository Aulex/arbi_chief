class Player {
  final int? player_id;
  final String player_surname;
  final String player_name;
  final String player_lastname;
  final int player_gender;
  final String player_date_birth; // Stored as yyyy-mm-dd in SQLite

  const Player({
    this.player_id,
    required this.player_surname,
    required this.player_name,
    required this.player_lastname,
    required this.player_gender,
    required this.player_date_birth,
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
  }) {
    return Player(
      player_id: player_id ?? this.player_id,
      player_surname: player_surname ?? this.player_surname,
      player_name: player_name ?? this.player_name,
      player_lastname: player_lastname ?? this.player_lastname,
      player_gender: player_gender ?? this.player_gender,
      player_date_birth: player_date_birth ?? this.player_date_birth,
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
    };
  }
}
