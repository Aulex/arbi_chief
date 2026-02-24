import 'package:sqflite/sqflite.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import 'database_service.dart';

class TournamentService {
  final DatabaseService _dbService;
  TournamentService(this._dbService);

  Future<List<Tournament>> getAllTournaments() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'CMP_TOURNAMENT',
      orderBy: 't_id DESC',
    );
    return List.generate(maps.length, (i) => Tournament.fromJson(maps[i]));
  }

  /// Returns the new t_id on insert, or the existing t_id on update.
  Future<int> saveTournament(Tournament tournament) async {
    final db = await _dbService.database;
    final data = tournament.toJson();

    if (tournament.t_id == null) {
      return await db.insert('CMP_TOURNAMENT', data);
    } else {
      await db.update(
        'CMP_TOURNAMENT',
        data,
        where: 't_id = ?',
        whereArgs: [tournament.t_id],
      );
      return tournament.t_id!;
    }
  }

  Future<void> deleteTournament(int id) async {
    final db = await _dbService.database;
    await db.delete('CMP_PLAYER_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
    await db.delete('CMP_ATTR_VALUE', where: 't_id = ?', whereArgs: [id]);
    await db.delete('CMP_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
  }

  // --- Tournament Participants (CMP_PLAYER_TOURNAMENT) ---

  Future<List<Player>> getParticipants(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT p.*
      FROM CMP_PLAYER p
      JOIN CMP_PLAYER_TOURNAMENT pt ON p.player_id = pt.player_id
      WHERE pt.t_id = ?
      ORDER BY p.player_surname, p.player_name
    ''', [tId]);
    return rows.map((r) => Player.fromJson(r)).toList();
  }

  Future<void> addParticipant(int tId, int playerId) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'CMP_PLAYER_TOURNAMENT',
      where: 't_id = ? AND player_id = ?',
      whereArgs: [tId, playerId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('CMP_PLAYER_TOURNAMENT', {
      't_id': tId,
      'player_id': playerId,
      'asgn_date': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeParticipant(int tId, int playerId) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_PLAYER_TOURNAMENT',
      where: 't_id = ? AND player_id = ?',
      whereArgs: [tId, playerId],
    );
  }

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

  /// Get the dict_value text for a tournament's dictionary-based attribute.
  Future<String?> getAttrDictValue(int tId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value
      FROM CMP_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.t_id = ? AND v.attr_id = ?
      LIMIT 1
    ''', [tId, attrId]);
    if (rows.isEmpty) return null;
    return rows.first['dict_value'] as String;
  }

  /// Get plain attr_value text for a tournament attribute (non-dict).
  Future<String?> getAttrValue(int tId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_ATTR_VALUE',
      columns: ['attr_value'],
      where: 't_id = ? AND attr_id = ?',
      whereArgs: [tId, attrId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['attr_value'] as String?;
  }

  /// Get multiple dict_value→attr_value pairs for a multi-row attribute (e.g. scoring points).
  Future<Map<String, String>> getAttrDictValueMap(int tId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value, v.attr_value
      FROM CMP_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.t_id = ? AND v.attr_id = ?
    ''', [tId, attrId]);
    return {
      for (final r in rows)
        r['dict_value'] as String: (r['attr_value'] as String?) ?? '',
    };
  }

  /// Get list of selected dict_values for a multi-row attribute (e.g. tiebreakers).
  Future<List<String>> getAttrDictValueList(int tId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT d.dict_value
      FROM CMP_ATTR_VALUE v
      JOIN CMP_ATTR_DICT d ON v.att_value_dict_id = d.dict_id
      WHERE v.t_id = ? AND v.attr_id = ?
    ''', [tId, attrId]);
    return rows.map((r) => r['dict_value'] as String).toList();
  }

  /// Save one attribute value for a tournament.
  Future<void> saveAttrValue({
    required int tId,
    required int attrId,
    String? attrValue,
    int? dictId,
  }) async {
    final db = await _dbService.database;
    // Delete old value for this tournament+attr, then insert new
    await db.delete(
      'CMP_ATTR_VALUE',
      where: 't_id = ? AND attr_id = ?',
      whereArgs: [tId, attrId],
    );
    await db.insert('CMP_ATTR_VALUE', {
      't_id': tId,
      'attr_id': attrId,
      'attr_value': attrValue,
      'att_value_dict_id': dictId,
    });
  }

  /// Save multiple rows for one attr_id (e.g. scoring points or tiebreakers).
  Future<void> saveAttrValues({
    required int tId,
    required int attrId,
    required List<({int? dictId, String? attrValue})> values,
  }) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_ATTR_VALUE',
      where: 't_id = ? AND attr_id = ?',
      whereArgs: [tId, attrId],
    );
    for (final v in values) {
      await db.insert('CMP_ATTR_VALUE', {
        't_id': tId,
        'attr_id': attrId,
        'attr_value': v.attrValue,
        'att_value_dict_id': v.dictId,
      });
    }
  }
}
