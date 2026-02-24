import 'package:sqflite/sqflite.dart';
import '../models/tournament_model.dart';
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
    await db.delete('CMP_ATTR_VALUE', where: 't_id = ?', whereArgs: [id]);
    await db.delete('CMP_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
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
}
