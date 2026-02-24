import '../models/team_model.dart';
import '../models/player_model.dart';
import 'database_service.dart';

class PlayerTeamAssignment {
  final int? pte_id;
  final int team_id;
  final int player_id;
  final int player_state; // 0 = active member, 1 = reserve

  const PlayerTeamAssignment({
    this.pte_id,
    required this.team_id,
    required this.player_id,
    required this.player_state,
  });

  factory PlayerTeamAssignment.fromJson(Map<String, dynamic> json) {
    return PlayerTeamAssignment(
      pte_id: json['pte_id'] as int?,
      team_id: json['team_id'] as int,
      player_id: json['player_id'] as int,
      player_state: json['player_state'] as int? ?? 0,
    );
  }
}

class TeamService {
  final DatabaseService _dbService;

  TeamService(this._dbService);

  Future<List<Team>> getAllTeams() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query('CMP_TEAM');
    return List.generate(maps.length, (i) => Team.fromJson(maps[i]));
  }

  Future<void> saveTeam(Team team) async {
    final db = await _dbService.database;
    final data = team.toJson();
    if (team.team_id == null) {
      await db.insert('CMP_TEAM', data);
    } else {
      await db.update(
        'CMP_TEAM',
        data,
        where: 'team_id = ?',
        whereArgs: [team.team_id],
      );
    }
  }

  Future<void> deleteTeam(int id) async {
    final db = await _dbService.database;
    // Delete attr values for all player-team assignments of this team
    final assignments = await db.query(
      'CMP_PLAYER_TEAM',
      columns: ['pte_id'],
      where: 'team_id = ?',
      whereArgs: [id],
    );
    for (final a in assignments) {
      await db.delete(
        'CMP_PLAYER_TEAM_ATTR_VALUE',
        where: 'pte_id = ?',
        whereArgs: [a['pte_id']],
      );
    }
    await db.delete('CMP_PLAYER_TEAM', where: 'team_id = ?', whereArgs: [id]);
    await db.delete('CMP_TEAM', where: 'team_id = ?', whereArgs: [id]);
  }

  Future<List<PlayerTeamAssignment>> getTeamAssignments(int teamId) async {
    final db = await _dbService.database;
    final maps = await db.query(
      'CMP_PLAYER_TEAM',
      where: 'team_id = ?',
      whereArgs: [teamId],
    );
    return maps.map((m) => PlayerTeamAssignment.fromJson(m)).toList();
  }

  /// Saves player-team assignments.
  /// [members] - list of player IDs for active members (player_state = 0)
  /// [reserves] - list of player IDs for reserves (player_state = 1)
  Future<void> saveAssignments(int teamId, List<int> members, List<int> reserves) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    // Remove old assignments for this team
    await db.delete('CMP_PLAYER_TEAM', where: 'team_id = ?', whereArgs: [teamId]);
    // Insert active members
    for (final playerId in members) {
      await db.insert('CMP_PLAYER_TEAM', {
        'team_id': teamId,
        'player_id': playerId,
        'player_state': 0,
        'asgn_date': today,
      });
    }
    // Insert reserves
    for (final playerId in reserves) {
      await db.insert('CMP_PLAYER_TEAM', {
        'team_id': teamId,
        'player_id': playerId,
        'player_state': 1,
        'asgn_date': today,
      });
    }
  }

  // --- Player-Team Attribute Values (CMP_PLAYER_TEAM_ATTR_VALUE) ---

  /// Look up dict_id by attr_id + dict_value text.
  Future<int?> getDictId(int attrId, String dictValue) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_ATTR_DICT',
      columns: ['dict_id'],
      where: 'attr_id = ? AND dict_value = ?',
      whereArgs: [attrId, dictValue],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['dict_id'] as int;
  }

  /// Get the dict_value text for a player-team's dictionary-based attribute.
  Future<String?> getPteAttrDictValue(int pteId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value
      FROM CMP_PLAYER_TEAM_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.pte_id = ? AND v.attr_id = ?
      LIMIT 1
    ''', [pteId, attrId]);
    if (rows.isEmpty) return null;
    return rows.first['dict_value'] as String;
  }

  /// Get plain attr_value text for a player-team attribute (non-dict).
  Future<String?> getPteAttrValue(int pteId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_PLAYER_TEAM_ATTR_VALUE',
      columns: ['attr_value'],
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, attrId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['attr_value'] as String?;
  }

  /// Get multiple dict_value->attr_value pairs for a multi-row attribute.
  Future<Map<String, String>> getPteAttrDictValueMap(int pteId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value, v.attr_value
      FROM CMP_PLAYER_TEAM_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.pte_id = ? AND v.attr_id = ?
    ''', [pteId, attrId]);
    return {
      for (final r in rows)
        r['dict_value'] as String: (r['attr_value'] as String?) ?? '',
    };
  }

  /// Get list of selected dict_values for a multi-row attribute.
  Future<List<String>> getPteAttrDictValueList(int pteId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value
      FROM CMP_PLAYER_TEAM_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.pte_id = ? AND v.attr_id = ?
    ''', [pteId, attrId]);
    return rows.map((r) => r['dict_value'] as String).toList();
  }

  /// Save one attribute value for a player-team assignment.
  Future<void> savePteAttrValue({
    required int pteId,
    required int attrId,
    String? attrValue,
    int? dictId,
  }) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, attrId],
    );
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId,
      'attr_id': attrId,
      'attr_value': attrValue,
      'att_value_dict_id': dictId,
    });
  }

  /// Save multiple rows for one attr_id on a player-team assignment.
  Future<void> savePteAttrValues({
    required int pteId,
    required int attrId,
    required List<({int? dictId, String? attrValue})> values,
  }) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, attrId],
    );
    for (final v in values) {
      await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
        'pte_id': pteId,
        'attr_id': attrId,
        'attr_value': v.attrValue,
        'att_value_dict_id': v.dictId,
      });
    }
  }
}
