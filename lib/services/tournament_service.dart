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

  // --- Games (CMP_EVENT + CMP_PLAYER_EVENT) ---

  /// Ensure a default stage exists for the tournament, return its ts_id.
  Future<int> getOrCreateDefaultStage(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TOURNAMENT_STAGE',
      where: 't_id = ?',
      whereArgs: [tId],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['ts_id'] as int;
    return await db.insert('CMP_TOURNAMENT_STAGE', {
      't_id': tId,
      'ts_name': 'Основний етап',
    });
  }

  /// Create a game between two players and return the event_id.
  Future<int> createGame({
    required int tsId,
    required int whitePlayerId,
    required int blackPlayerId,
  }) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    final eventId = await db.insert('CMP_EVENT', {
      'ts_id': tsId,
      'event_date_begin': today,
    });
    await db.insert('CMP_PLAYER_EVENT', {
      'event_id': eventId,
      'player_id': whitePlayerId,
      'asgn_date': today,
    });
    await db.insert('CMP_PLAYER_EVENT', {
      'event_id': eventId,
      'player_id': blackPlayerId,
      'asgn_date': today,
    });
    return eventId;
  }

  /// Get all games for a tournament (via its stages).
  Future<List<({int eventId, Player white, Player black, String? dateBegin})>>
      getGamesForTournament(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT e.event_id, e.event_date_begin,
             p1.player_id AS w_id, p1.player_surname AS w_surname,
             p1.player_name AS w_name, p1.player_lastname AS w_lastname,
             p1.player_gender AS w_gender, p1.player_date_birth AS w_dob,
             p2.player_id AS b_id, p2.player_surname AS b_surname,
             p2.player_name AS b_name, p2.player_lastname AS b_lastname,
             p2.player_gender AS b_gender, p2.player_date_birth AS b_dob
      FROM CMP_EVENT e
      JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
      JOIN CMP_PLAYER_EVENT pe1 ON pe1.event_id = e.event_id
      JOIN CMP_PLAYER_EVENT pe2 ON pe2.event_id = e.event_id AND pe2.pe_id > pe1.pe_id
      JOIN CMP_PLAYER p1 ON pe1.player_id = p1.player_id
      JOIN CMP_PLAYER p2 ON pe2.player_id = p2.player_id
      WHERE ts.t_id = ?
      ORDER BY e.event_id
    ''', [tId]);
    return rows.map((r) {
      final white = Player(
        player_id: r['w_id'] as int,
        player_surname: r['w_surname'] as String? ?? '',
        player_name: r['w_name'] as String? ?? '',
        player_lastname: r['w_lastname'] as String? ?? '',
        player_gender: r['w_gender'] as int? ?? 0,
        player_date_birth: r['w_dob'] as String? ?? '',
      );
      final black = Player(
        player_id: r['b_id'] as int,
        player_surname: r['b_surname'] as String? ?? '',
        player_name: r['b_name'] as String? ?? '',
        player_lastname: r['b_lastname'] as String? ?? '',
        player_gender: r['b_gender'] as int? ?? 0,
        player_date_birth: r['b_dob'] as String? ?? '',
      );
      return (
        eventId: r['event_id'] as int,
        white: white,
        black: black,
        dateBegin: r['event_date_begin'] as String?,
      );
    }).toList();
  }

  /// Delete a game and its player events.
  Future<void> deleteGame(int eventId) async {
    final db = await _dbService.database;
    await db.delete('CMP_PLAYER_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
    await db.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
  }

  /// Get all games for a tournament grouped by board number, including results.
  Future<Map<int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult})>>>
      getGamesGroupedByBoard(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT e.event_id, e.event_date_begin,
             p1.player_id AS w_id, p1.player_surname AS w_surname,
             p1.player_name AS w_name, p1.player_lastname AS w_lastname,
             p1.player_gender AS w_gender, p1.player_date_birth AS w_dob,
             pe1.event_result AS w_result,
             p2.player_id AS b_id, p2.player_surname AS b_surname,
             p2.player_name AS b_name, p2.player_lastname AS b_lastname,
             p2.player_gender AS b_gender, p2.player_date_birth AS b_dob,
             pe2.event_result AS b_result,
             COALESCE(CAST(v1.attr_value AS INTEGER), 0) AS board_number
      FROM CMP_EVENT e
      JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
      JOIN CMP_PLAYER_EVENT pe1 ON pe1.event_id = e.event_id
      JOIN CMP_PLAYER_EVENT pe2 ON pe2.event_id = e.event_id AND pe2.pe_id > pe1.pe_id
      JOIN CMP_PLAYER p1 ON pe1.player_id = p1.player_id
      JOIN CMP_PLAYER p2 ON pe2.player_id = p2.player_id
      LEFT JOIN CMP_PLAYER_TEAM pt1 ON pt1.player_id = p1.player_id AND pt1.player_state = 0
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE v1 ON pt1.pte_id = v1.pte_id AND v1.attr_id = 9
      WHERE ts.t_id = ?
      ORDER BY board_number, e.event_id
    ''', [tId]);
    final result = <int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult})>>{};
    for (final r in rows) {
      final boardNum = r['board_number'] as int? ?? 0;
      final white = Player(
        player_id: r['w_id'] as int,
        player_surname: r['w_surname'] as String? ?? '',
        player_name: r['w_name'] as String? ?? '',
        player_lastname: r['w_lastname'] as String? ?? '',
        player_gender: r['w_gender'] as int? ?? 0,
        player_date_birth: r['w_dob'] as String? ?? '',
      );
      final black = Player(
        player_id: r['b_id'] as int,
        player_surname: r['b_surname'] as String? ?? '',
        player_name: r['b_name'] as String? ?? '',
        player_lastname: r['b_lastname'] as String? ?? '',
        player_gender: r['b_gender'] as int? ?? 0,
        player_date_birth: r['b_dob'] as String? ?? '',
      );
      result.putIfAbsent(boardNum, () => []).add((
        eventId: r['event_id'] as int,
        white: white,
        black: black,
        dateBegin: r['event_date_begin'] as String?,
        whiteResult: r['w_result'] as double?,
        blackResult: r['b_result'] as double?,
      ));
    }
    return result;
  }

  /// Save result for both players in a game.
  Future<void> saveGameResult(int eventId, double? whiteResult, double? blackResult) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_PLAYER_EVENT',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'pe_id',
    );
    if (rows.length >= 2) {
      await db.update(
        'CMP_PLAYER_EVENT',
        {'event_result': whiteResult},
        where: 'pe_id = ?',
        whereArgs: [rows[0]['pe_id']],
      );
      await db.update(
        'CMP_PLAYER_EVENT',
        {'event_result': blackResult},
        where: 'pe_id = ?',
        whereArgs: [rows[1]['pe_id']],
      );
    }
  }
}
