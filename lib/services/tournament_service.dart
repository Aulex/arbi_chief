import 'package:sqflite/sqflite.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import 'database_service.dart';

class TournamentService {
  final DatabaseService _dbService;
  TournamentService(this._dbService);

  /// Get all tournament types from CMP_TOURNAMENT_TYPE.
  Future<List<({int typeId, String typeName})>> getTournamentTypes() async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_TOURNAMENT_TYPE', orderBy: 'type_id');
    return rows.map((r) => (
      typeId: r['type_id'] as int,
      typeName: r['type_name'] as String,
    )).toList();
  }

  Future<List<Tournament>> getAllTournaments({int? tType}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps;
    if (tType != null) {
      maps = await db.query('CMP_TOURNAMENT', where: 't_type = ?', whereArgs: [tType], orderBy: 't_date_begin DESC');
    } else {
      maps = await db.query('CMP_TOURNAMENT', orderBy: 't_date_begin DESC');
    }
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
    await db.transaction((txn) async {
      // Delete subevents and events for this tournament
      final events = await txn.query('CMP_EVENT', columns: ['event_id'], where: 't_id = ?', whereArgs: [id]);
      for (final e in events) {
        await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [e['event_id']]);
      }
      await txn.delete('CMP_EVENT', where: 't_id = ?', whereArgs: [id]);
      // Delete player-team attribute values, then player-team assignments
      final teamAssignments = await txn.query('CMP_PLAYER_TEAM', columns: ['pte_id'], where: 't_id = ?', whereArgs: [id]);
      for (final a in teamAssignments) {
        await txn.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ?', whereArgs: [a['pte_id']]);
      }
      await txn.delete('CMP_PLAYER_TEAM', where: 't_id = ?', whereArgs: [id]);
      await txn.delete('CMP_PLAYER_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
      await txn.delete('CMP_ATTR_VALUE', where: 't_id = ?', whereArgs: [id]);
      await txn.delete('CMP_TEAM_ATTR', where: 't_id = ?', whereArgs: [id]);
      await txn.delete('CMP_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
    });
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

  /// Bulk-add participants in a single transaction, skipping duplicates.
  Future<void> bulkAddParticipants(int tId, List<int> playerIds) async {
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final playerId in playerIds) {
        final existing = await txn.query(
          'CMP_PLAYER_TOURNAMENT',
          where: 't_id = ? AND player_id = ?',
          whereArgs: [tId, playerId],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        await txn.insert('CMP_PLAYER_TOURNAMENT', {
          't_id': tId,
          'player_id': playerId,
          'asgn_date': now,
        });
      }
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

  /// Delete all rows for one attr_id of a tournament.
  Future<void> deleteAttrValue({required int tId, required int attrId}) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_ATTR_VALUE',
      where: 't_id = ? AND attr_id = ?',
      whereArgs: [tId, attrId],
    );
  }

  // --- Games (CMP_EVENT + CMP_SUBEVENT) ---

  /// Create a game between two players and return the event_id.
  Future<int> createGame({
    required int tId,
    required int whitePlayerId,
    required int blackPlayerId,
  }) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    
    return await db.transaction((txn) async {
      // Get Entity IDs, creating them if missing (legacy players may lack one)
      final wEntId = await _dbService.ensurePlayerEntity(txn, whitePlayerId);
      final bEntId = await _dbService.ensurePlayerEntity(txn, blackPlayerId);

      final eventId = await txn.insert('CMP_EVENT', {
        't_id': tId,
        'event_date_begin': today,
        'et_id': 1, // Одиночний
      });
      
      await txn.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': wEntId,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_w_se',
      });
      await txn.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': bEntId,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_b_se',
      });
      
      return eventId;
    });
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
      -- Get two distinct entities for each event
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id > se1.entity_id
      JOIN CMP_PLAYER p1 ON se1.entity_id = p1.entity_id
      JOIN CMP_PLAYER p2 ON se2.entity_id = p2.entity_id
      WHERE e.t_id = ?
      -- Group to avoid duplicates if there are multiple sets (subevents)
      GROUP BY e.event_id
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

  /// Delete a game and its subevents.
  Future<void> deleteGame(int eventId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  /// Delete multiple games in a single transaction.
  Future<void> deleteGames(List<int> eventIds) async {
    if (eventIds.isEmpty) return;
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final eventId in eventIds) {
        await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
        await txn.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
      }
    });
  }

  /// Reset results to null for multiple games (keep the game records).
  Future<void> resetGameResults(List<int> eventIds) async {
    if (eventIds.isEmpty) return;
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final eventId in eventIds) {
        await txn.update(
          'CMP_SUBEVENT',
          {'se_result': null},
          where: 'ev_id = ?',
          whereArgs: [eventId],
        );
        await txn.update(
          'CMP_EVENT',
          {'event_result': null, 'es_id': null},
          where: 'event_id = ?',
          whereArgs: [eventId],
        );
      }
    });
  }

  /// Get all games for a tournament grouped by board number, including results.
  Future<Map<int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult, String? whiteDetail, String? blackDetail})>>>
      getGamesGroupedByBoard(int tId) async {
    final db = await _dbService.database;
    
    // Complex query: Join with subevents, but since there can be multiple sets, 
    // we need to aggregate them if we want to reconstruct the detail strings.
    // However, the simplest way for now is to get the overall result from CMP_EVENT
    // and just use the first subevent score for chess.
    
    final rows = await db.rawQuery('''
      SELECT e.event_id, e.event_date_begin, e.event_result,
             p1.player_id AS w_id, p1.player_surname AS w_surname,
             p1.player_name AS w_name, p1.player_lastname AS w_lastname,
             p1.player_gender AS w_gender, p1.player_date_birth AS w_dob,
             p2.player_id AS b_id, p2.player_surname AS b_surname,
             p2.player_name AS b_name, p2.player_lastname AS b_lastname,
             p2.player_gender AS b_gender, p2.player_date_birth AS b_dob,
             COALESCE(CAST(v1.attr_value AS INTEGER), 0) AS board_number
      FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id > se1.entity_id
      JOIN CMP_PLAYER p1 ON se1.entity_id = p1.entity_id
      JOIN CMP_PLAYER p2 ON se2.entity_id = p2.entity_id
      LEFT JOIN CMP_PLAYER_TEAM pt1 ON pt1.player_id = p1.player_id AND pt1.player_state = 0 AND pt1.t_id = e.t_id
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE v1 ON pt1.pte_id = v1.pte_id AND v1.attr_id = 9
      WHERE e.t_id = ?
      GROUP BY e.event_id
      ORDER BY board_number, e.event_id
    ''', [tId]);

    final result = <int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult, String? whiteDetail, String? blackDetail})>>{};
    
    for (final r in rows) {
      final boardNum = r['board_number'] as int? ?? 0;
      final eventId = r['event_id'] as int;
      
      // Get sub-event details for this specific match (all sets)
      final subEvents = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId], orderBy: 'se_id');
      
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

      // Determine which entity is "white"
      final wPlayerEntId = await _dbService.ensurePlayerEntity(db, white.player_id!);
      
      // Filter subevents per player
      final wSubs = subEvents.where((s) => s['entity_id'] == wPlayerEntId).toList();
      final bSubs = subEvents.where((s) => s['entity_id'] != wPlayerEntId).toList();

      double? wRes, bRes;
      String? wDet, bDet;

      if (wSubs.length == 1) {
        // Single-result game (chess)
        wRes = wSubs[0]['se_result'] as double?;
        bRes = bSubs.isNotEmpty ? bSubs[0]['se_result'] as double? : null;
      } else if (wSubs.length > 1) {
        // Multi-set game (table tennis): reconstruct "score:opponentScore" per set
        final wSets = <String>[];
        final bSets = <String>[];
        for (int i = 0; i < wSubs.length; i++) {
          final wScore = (wSubs[i]['se_result'] as num?)?.toInt() ?? 0;
          final bScore = i < bSubs.length ? (bSubs[i]['se_result'] as num?)?.toInt() ?? 0 : 0;
          wSets.add('$wScore:$bScore');
          bSets.add('$bScore:$wScore');
        }
        wDet = wSets.join(' ');
        bDet = bSets.join(' ');
        // Count sets won (score > opponent score) to determine overall win/loss
        int wSetsWon = 0, bSetsWon = 0;
        for (int i = 0; i < wSubs.length && i < bSubs.length; i++) {
          final ws = (wSubs[i]['se_result'] as num?)?.toInt() ?? 0;
          final bs = (bSubs[i]['se_result'] as num?)?.toInt() ?? 0;
          if (ws > bs) wSetsWon++;
          else if (bs > ws) bSetsWon++;
        }
        wRes = wSetsWon > bSetsWon ? 1.0 : (wSetsWon < bSetsWon ? 0.0 : null);
        bRes = wRes != null ? 1.0 - wRes! : null;
      }

      result.putIfAbsent(boardNum, () => []).add((
        eventId: eventId,
        white: white,
        black: black,
        dateBegin: r['event_date_begin'] as String?,
        whiteResult: wRes,
        blackResult: bRes,
        whiteDetail: wDet,
        blackDetail: bDet,
      ));
    }
    return result;
  }

  /// Mark a player as no-show: set all their games as losses (0) and opponents as wins (1).
  /// Creates games if they don't exist yet. All in a single transaction.
  Future<void> markPlayerNoShow(int tId, int playerId, List<int> opponentIds, {Set<int> alsoAbsentIds = const {}}) async {
    if (opponentIds.isEmpty) return;
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    
    // Get player's entity_id (create if missing)
    final playerEntId = await _dbService.ensurePlayerEntity(db, playerId);

    await db.transaction((txn) async {
      for (final opponentId in opponentIds) {
        // Get opponent's entity_id (create if missing)
        final opponentEntId = await _dbService.ensurePlayerEntity(txn, opponentId);

        // Find existing game
        final rows = await txn.rawQuery('''
          SELECT e.event_id
          FROM CMP_EVENT e
          JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ?
          JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ?
          WHERE e.t_id = ?
          LIMIT 1
        ''', [playerEntId, opponentEntId, tId]);

        int eventId;
        if (rows.isNotEmpty) {
          eventId = rows.first['event_id'] as int;
        } else {
          // Create game
          eventId = await txn.insert('CMP_EVENT', {
            't_id': tId,
            'event_date_begin': today,
            'et_id': 1,
          });
          await txn.insert('CMP_SUBEVENT', {
            'ev_id': eventId,
            'entity_id': playerEntId,
            'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ns_p',
          });
          await txn.insert('CMP_SUBEVENT', {
            'ev_id': eventId,
            'entity_id': opponentEntId,
            'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ns_o',
          });
        }

        // Both no-show → 0:0, otherwise no-show player loses (es_id 4: Неявка for loser, 1: Перемога for opponent)
        final bothAbsent = alsoAbsentIds.contains(opponentId);
        
        await txn.update('CMP_SUBEVENT', {
          'se_result': 0.0,
          'es_id': 4, // Неявка
          'se_note': bothAbsent ? 'Обопільна неявка' : 'Неявка',
        }, where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, playerEntId]);

        await txn.update('CMP_SUBEVENT', {
          'se_result': bothAbsent ? 0.0 : 1.0,
          'es_id': bothAbsent ? 4 : 1, // Неявка or Перемога
          'se_note': bothAbsent ? 'Обопільна неявка' : null,
        }, where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, opponentEntId]);
        
        await txn.update('CMP_EVENT', {
          'es_id': 4,
          'event_result': bothAbsent ? '0:0' : '0:1',
        }, where: 'event_id = ?', whereArgs: [eventId]);
      }
    });
  }

  /// Clear no-show: delete all games where this player's result is 0.0 (no-show losses).
  Future<void> clearPlayerNoShow(int tId, int playerId) async {
    final db = await _dbService.database;
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (pRows.isEmpty) return;
    final entId = pRows.first['entity_id'] as int?;
    if (entId == null) return;

    final rows = await db.rawQuery('''
      SELECT e.event_id
      FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id AND se.entity_id = ?
      WHERE e.t_id = ? AND se.es_id = 4
    ''', [entId, tId]);
    final eventIds = rows.map((r) => r['event_id'] as int).toList();
    await deleteGames(eventIds);
  }

  /// Find a game between two players in a tournament, return eventId if found.
  Future<int?> findGameBetweenPlayers(int tId, int player1Id, int player2Id) async {
    final db = await _dbService.database;
    // Get entity IDs for both players
    final ent1 = await _dbService.ensurePlayerEntity(db, player1Id);
    final ent2 = await _dbService.ensurePlayerEntity(db, player2Id);

    final rows = await db.rawQuery('''
      SELECT e.event_id
      FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ?
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ?
      WHERE e.t_id = ?
      LIMIT 1
    ''', [ent1, ent2, tId]);
    if (rows.isEmpty) return null;
    return rows.first['event_id'] as int;
  }

  /// Save result for a specific player in a game; sets complement for opponent.
  Future<void> saveResultForPlayer(int eventId, int playerId, double? playerResult) async {
    final db = await _dbService.database;
    
    // 1. Identify both players in this game
    final eventRows = await db.rawQuery('''
      SELECT se.entity_id, p.player_id
      FROM CMP_SUBEVENT se
      JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      WHERE se.ev_id = ?
    ''', [eventId]);
    
    if (eventRows.isEmpty) return;
    
    // Find who is the 'player' and who is the 'opponent'
    int? playerEntId;
    int? opponentEntId;
    
    for (final r in eventRows) {
      if (r['player_id'] == playerId) {
        playerEntId = r['entity_id'] as int;
      } else {
        opponentEntId = r['entity_id'] as int;
      }
    }
    
    if (playerEntId == null || opponentEntId == null) return;

    final complement = playerResult != null ? 1.0 - playerResult : null;

    await db.transaction((txn) async {
      await txn.update('CMP_SUBEVENT', {'se_result': playerResult}, 
          where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, playerEntId]);
      
      await txn.update('CMP_SUBEVENT', {'se_result': complement}, 
          where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, opponentEntId]);
      
      // Update overall event result summary
      if (playerResult != null) {
        int? esId;
        if (playerResult == 1.0) esId = 1;
        else if (playerResult == 0.0) esId = 2;
        else if (playerResult == 0.5) esId = 3;
        
        await txn.update('CMP_EVENT', {
          'event_result': playerResult.toString(),
          'es_id': esId,
        }, where: 'event_id = ?', whereArgs: [eventId]);
      } else {
        await txn.update('CMP_EVENT', {
          'event_result': null,
          'es_id': null,
        }, where: 'event_id = ?', whereArgs: [eventId]);
      }
    });
  }

  /// Save result for both players in a game.
  Future<void> saveGameResult(int eventId, double? whiteResult, double? blackResult) async {
    final db = await _dbService.database;
    final subRows = await db.query(
      'CMP_SUBEVENT',
      where: 'ev_id = ?',
      whereArgs: [eventId],
      orderBy: 'se_id',
    );
    if (subRows.length >= 2) {
      await db.transaction((txn) async {
        await txn.update(
          'CMP_SUBEVENT',
          {'se_result': whiteResult},
          where: 'se_id = ?',
          whereArgs: [subRows[0]['se_id']],
        );
        await txn.update(
          'CMP_SUBEVENT',
          {'se_result': blackResult},
          where: 'se_id = ?',
          whereArgs: [subRows[1]['se_id']],
        );
        // Update overall event result
        int? esId;
        if (whiteResult == 1.0) esId = 1;
        else if (whiteResult == 0.0) esId = 2;
        else if (whiteResult == 0.5) esId = 3;
        await txn.update('CMP_EVENT', {
          'event_result': whiteResult != null ? '$whiteResult:$blackResult' : null,
          'es_id': whiteResult != null ? esId : null,
        }, where: 'event_id = ?', whereArgs: [eventId]);
      });
    }
  }

  /// Check if a tournament has any game results (CMP_EVENT rows).
  Future<bool> hasGameResults(int tId) async {
    final db = await _dbService.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM CMP_EVENT WHERE t_id = ?', [tId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Delete all game results (CMP_EVENT + CMP_SUBEVENT) for a tournament.
  Future<void> clearAllGameResults(int tId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      final events = await txn.query('CMP_EVENT', columns: ['event_id'], where: 't_id = ?', whereArgs: [tId]);
      for (final e in events) {
        await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [e['event_id']]);
      }
      await txn.delete('CMP_EVENT', where: 't_id = ?', whereArgs: [tId]);
    });
  }

  /// Save player body weight (kg) via CMP_PLAYER_TEAM_ATTR_VALUE attr_id=17.
  /// Silently returns if no CMP_PLAYER_TEAM entry exists yet.
  Future<void> savePlayerWeight({required int playerId, required int tId, required double weight}) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ? AND attr_id = 17', whereArgs: [pteId]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId, 'attr_id': 17, 'attr_value': weight.toString(),
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pw_$playerId',
    });
  }

  /// Get player body weight (kg) for a player in a tournament.
  Future<double?> getPlayerWeight({required int playerId, required int tId}) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.player_id = ? AND pt.t_id = ? AND v.attr_id = 17
      LIMIT 1
    ''', [playerId, tId]);
    if (rows.isEmpty) return null;
    return double.tryParse(rows.first['attr_value'] as String? ?? '');
  }
}
