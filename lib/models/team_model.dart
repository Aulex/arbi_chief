class Team {
  final int? team_id;
  final String team_code;
  final String team_name;

  const Team({
    this.team_id,
    required this.team_code,
    required this.team_name,
  });

  String get displayName => team_name.isEmpty ? team_code : team_name;

  Team copyWith({
    int? team_id,
    String? team_code,
    String? team_name,
  }) {
    return Team(
      team_id: team_id ?? this.team_id,
      team_code: team_code ?? this.team_code,
      team_name: team_name ?? this.team_name,
    );
  }

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      team_id: json['team_id'] as int?,
      team_code: json['team_code'] as String? ?? '',
      team_name: json['team_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'team_id': team_id,
      'team_code': team_code,
      'team_name': team_name,
    };
  }
}
