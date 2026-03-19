class Team {
  final int? team_id;
  final String team_name;
  final int? t_type;
  final int? entity_id;

  const Team({
    this.team_id,
    required this.team_name,
    this.t_type,
    this.entity_id,
  });

  String get displayName => team_name;

  Team copyWith({
    int? team_id,
    String? team_name,
    int? t_type,
    int? entity_id,
  }) {
    return Team(
      team_id: team_id ?? this.team_id,
      team_name: team_name ?? this.team_name,
      t_type: t_type ?? this.t_type,
      entity_id: entity_id ?? this.entity_id,
    );
  }

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      team_id: json['team_id'] as int?,
      team_name: json['team_name'] as String? ?? '',
      t_type: json['t_type'] as int?,
      entity_id: json['entity_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'team_id': team_id,
      'team_name': team_name,
      't_type': t_type,
      'entity_id': entity_id,
    };
  }
}
