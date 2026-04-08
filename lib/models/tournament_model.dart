class Tournament {
  final int? t_id;
  final int? t_type;
  final String t_name;
  final String t_date_begin;
  final String t_date_end;
  final int? t_location;
  final int? t_org;
  final String? sync_uid;

  const Tournament({
    this.t_id,
    this.t_type,
    required this.t_name,
    required this.t_date_begin,
    required this.t_date_end,
    this.t_location,
    this.t_org,
    this.sync_uid,
  });

  // --- Date Helpers (similar to Player model) ---

  String get beginDateForUI => _formatToUI(t_date_begin);
  String get endDateForUI => _formatToUI(t_date_end);

  String _formatToUI(String dbDate) {
    if (dbDate.isEmpty || !dbDate.contains('-')) return dbDate;
    List<String> parts = dbDate.split('-');
    return "${parts[2]}.${parts[1]}.${parts[0]}";
  }

  static String formatForDB(String uiDate) {
    if (!uiDate.contains('.')) return uiDate;
    List<String> parts = uiDate.split('.');
    return "${parts[2]}-${parts[1]}-${parts[0]}";
  }

  Tournament copyWith({
    int? t_id,
    int? t_type,
    String? t_name,
    String? t_date_begin,
    String? t_date_end,
    int? t_location,
    int? t_org,
    String? sync_uid,
  }) {
    return Tournament(
      t_id: t_id ?? this.t_id,
      t_type: t_type ?? this.t_type,
      t_name: t_name ?? this.t_name,
      t_date_begin: t_date_begin ?? this.t_date_begin,
      t_date_end: t_date_end ?? this.t_date_end,
      t_location: t_location ?? this.t_location,
      t_org: t_org ?? this.t_org,
      sync_uid: sync_uid ?? this.sync_uid,
    );
  }

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
    t_id: json['t_id'] as int?,
    t_type: json['t_type'] as int?,
    t_name: json['t_name'] as String? ?? '',
    t_date_begin: json['t_date_begin'] as String? ?? '',
    t_date_end: json['t_date_end'] as String? ?? '',
    t_location: json['t_location'] as int?,
    t_org: json['t_org'] as int?,
    sync_uid: json['sync_uid'] as String?,
  );

  Map<String, dynamic> toJson() => {
    't_id': t_id,
    't_type': t_type,
    't_name': t_name,
    't_date_begin': t_date_begin,
    't_date_end': t_date_end,
    't_location': t_location,
    't_org': t_org,
    'sync_uid': sync_uid,
  };
}
