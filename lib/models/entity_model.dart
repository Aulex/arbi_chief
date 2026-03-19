class Entity {
  final int? ent_id;
  final String? sync_uid;

  const Entity({
    this.ent_id,
    this.sync_uid,
  });

  factory Entity.fromJson(Map<String, dynamic> json) {
    return Entity(
      ent_id: json['ent_id'] as int?,
      sync_uid: json['sync_uid'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ent_id': ent_id,
      'sync_uid': sync_uid,
    };
  }
}
