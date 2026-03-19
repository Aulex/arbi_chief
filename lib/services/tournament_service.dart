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
    // Delete subevents and events for all stages of this tournament
    final stages = await db.query('CMP_TOURNAMENT_STAGE', columns: ['ts_id'], where: 't_id = ?', whereArgs: [id]);
    for (final s in stages) {
      final tsId = s['ts_id'] as int;
      final events = await db.query('CMP_EVENT', columns: ['event_id'], where: 'ts_id = ?', whereArgs: [tsId]);
      for (final e in events) {
        await db.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [e['event_id']]);
      }
      await db.delete('CMP_EVENT', where: 'ts_id = ?', whereArgs: [tsId]);
    }
    await db.delete('CMP_TOURNAMENT_STAGE', where: 't_id = ?', whereArgs: [id]);
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

  // --- Games (CMP_EVENT + CMP_SUBEVENT) ---

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
    
    // Get Entity IDs
    final wRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [whitePlayerId]);
    final bRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [blackPlayerId]);
    final wEntId = wRows.first['entity_id'] as int;
    final bEntId = bRows.first['entity_id'] as int;

    final eventId = await db.insert('CMP_EVENT', {
      'ts_id': tsId,
      'event_date_begin': today,
      'et_id': 1, // Одиночний
    });
    
    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': wEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_w_se',
    });
    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': bEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_b_se',
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
      -- Get two distinct entities for each event
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id > se1.entity_id
      JOIN CMP_PLAYER p1 ON se1.entity_id = p1.entity_id
      JOIN CMP_PLAYER p2 ON se2.entity_id = p2.entity_id
      WHERE ts.t_id = ?
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
    await db.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
    await db.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
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
      JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id > se1.entity_id
      JOIN CMP_PLAYER p1 ON se1.entity_id = p1.entity_id
      JOIN CMP_PLAYER p2 ON se2.entity_id = p2.entity_id
      LEFT JOIN CMP_PLAYER_TEAM pt1 ON pt1.player_id = p1.player_id AND pt1.player_state = 0 AND pt1.t_id = ts.t_id
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE v1 ON pt1.pte_id = v1.pte_id AND v1.attr_id = 9
      WHERE ts.t_id = ?
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

      // Determine which entity is "white" (p1 from the SQL = lower entity_id)
      // The SQL joins: se1.entity_id < se2.entity_id, so p1 = lower entity_id
      final wPlayer = white;
      final bPlayer = black;
      final wPlayerEntId = (await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [wPlayer.player_id])).first['entity_id'] as int;

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
  Future<void> markPlayerNoShow(int tId, int tsId, int playerId, List<int> opponentIds, {Set<int> alsoAbsentIds = const {}}) async {
    if (opponentIds.isEmpty) return;
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    
    // Get player's entity_id
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    final playerEntId = pRows.first['entity_id'] as int;

    await db.transaction((txn) async {
      for (final opponentId in opponentIds) {
        // Get opponent's entity_id
        final oRows = await txn.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [opponentId]);
        final opponentEntId = oRows.first['entity_id'] as int;

        // Find existing game
        final rows = await txn.rawQuery('''
          SELECT e.event_id
          FROM CMP_EVENT e
          JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
          JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ?
          JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ?
          WHERE ts.t_id = ?
          LIMIT 1
        ''', [playerEntId, opponentEntId, tId]);

        int eventId;
        if (rows.isNotEmpty) {
          eventId = rows.first['event_id'] as int;
        } else {
          // Create game
          eventId = await txn.insert('CMP_EVENT', {
            'ts_id': tsId,
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
    final entId = pRows.first['entity_id'] as int;

    final rows = await db.rawQuery('''
      SELECT e.event_id
      FROM CMP_EVENT e
      JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id AND se.entity_id = ?
      WHERE ts.t_id = ? AND se.es_id = 4
    ''', [entId, tId]);
    final eventIds = rows.map((r) => r['event_id'] as int).toList();
    await deleteGames(eventIds);
  }

  /// Find a game between two players in a tournament, return eventId if found.
  Future<int?> findGameBetweenPlayers(int tId, int player1Id, int player2Id) async {
    final db = await _dbService.database;
    // Get entity IDs for both players
    final p1Rows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [player1Id]);
    final p2Rows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [player2Id]);
    if (p1Rows.isEmpty || p2Rows.isEmpty) return null;
    final ent1 = p1Rows.first['entity_id'] as int?;
    final ent2 = p2Rows.first['entity_id'] as int?;
    if (ent1 == null || ent2 == null) return null;

    final rows = await db.rawQuery('''
      SELECT e.event_id
      FROM CMP_EVENT e
      JOIN CMP_TOURNAMENT_STAGE ts ON e.ts_id = ts.ts_id
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ?
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ?
      WHERE ts.t_id = ?
      LIMIT 1
    ''', [ent1, ent2, tId]);
    if (rows.isEmpty) return null;
    return rows.first['event_id'] as int;
  }

  /// Save result for a specific player in a game; sets complement for opponent.
  /// When playerResult is null, also clears event_result_detail.
  Future<void> saveResultForPlayer(int eventId, int playerId, double? playerResult) async {
    final db = await _dbService.database;
    
    // Get Entity ID for the player
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    final playerEntId = pRows.first['entity_id'] as int;

    // Get all subevents for this event
    final subRows = await db.query(
      'CMP_SUBEVENT',
      where: 'ev_id = ?',
      whereArgs: [eventId],
      orderBy: 'se_id',
    );
    if (subRows.length < 2) return;

    final complement = playerResult != null ? 1.0 - playerResult : null;

    await db.transaction((txn) async {
      for (final row in subRows) {
        final entId = row['entity_id'] as int;
        if (entId == playerEntId) {
          await txn.update('CMP_SUBEVENT', {'se_result': playerResult}, 
              where: 'se_id = ?', whereArgs: [row['se_id']]);
        } else {
          await txn.update('CMP_SUBEVENT', {'se_result': complement}, 
              where: 'se_id = ?', whereArgs: [row['se_id']]);
        }
      }
      
      // Update overall event result summary
      if (playerResult != null) {
        // Find which outcome name matches
        int? esId;
        if (playerResult == 1.0) esId = 1; // Перемога (hardcoded for now as per seed)
        else if (playerResult == 0.0) esId = 2; // Поразка
        else if (playerResult == 0.5) esId = 3; // Нічия
        
        await txn.update('CMP_EVENT', {
          'event_result': playerResult.toString(),
          'es_id': esId,
        }, where: 'event_id = ?', whereArgs: [eventId]);
      }
    });
  }

  /// Save table tennis match result with set-by-set scores.
  /// [rowPlayerSets] is the detail string for the row player (e.g. "11:7 11:4 8:11").
  /// [colPlayerSets] is the mirror detail for the opponent (e.g. "7:11 4:11 11:8").
  /// Win/loss (1.0/0.0) is derived from who won more sets.
  Future<void> saveTableTennisResult(int eventId, int rowPlayerId, {
    required double rowResult,
    required String rowDetail,
    required String colDetail,
  }) async {
    final db = await _dbService.database;
    
    // Get Entity ID for the row player
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [rowPlayerId]);
    final rowEntId = pRows.first['entity_id'] as int;

    final subRows = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
    if (subRows.length < 2) return;

    await db.transaction((txn) async {
      // Clear old subevents for this event to rebuild from sets
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      
      // Parse rowDetail (e.g. "11:7 11:4")
      final rowSets = rowDetail.trim().split(RegExp(r'\s+'));
      final colSets = colDetail.trim().split(RegExp(r'\s+'));
      
      // Find the entity IDs
      final otherEntId = subRows.firstWhere((r) => r['entity_id'] != rowEntId)['entity_id'] as int;

      for (int i = 0; i < rowSets.length; i++) {
        final rScore = double.tryParse(rowSets[i].split(':')[0]) ?? 0.0;
        final cScore = double.tryParse(colSets[i].split(':')[0]) ?? 0.0;
        
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': rowEntId,
          'se_result': rScore,
          'se_note': 'Set ${i+1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_r_s$i',
        });
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': otherEntId,
          'se_result': cScore,
          'se_note': 'Set ${i+1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_c_s$i',
        });
      }

      // Update redundant overall summary in CMP_EVENT
      int? esId;
      if (rowResult == 1.0) esId = 1; // Перемога
      else if (rowResult == 0.0) esId = 2; // Поразка

      await txn.update('CMP_EVENT', {
        'event_result': '$rowResult:$colDetail', // We could store a summary string here
        'es_id': esId,
      }, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  /// Get set score details for a specific player in a game.
  /// For multi-set games (table tennis), reconstructs "11:7 11:4" format from subevents.
  Future<String?> getResultDetail(int eventId, int playerId) async {
    final db = await _dbService.database;
    // Get entity ID for the player
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (pRows.isEmpty) return null;
    final playerEntId = pRows.first['entity_id'] as int?;
    if (playerEntId == null) return null;

    // Get all subevents for this event, ordered by se_id
    final subRows = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId], orderBy: 'se_id');

    // For single-result games (chess), no detail string needed
    final playerSubs = subRows.where((s) => s['entity_id'] == playerEntId).toList();
    final opponentSubs = subRows.where((s) => s['entity_id'] != playerEntId).toList();
    if (playerSubs.length <= 1) return null;

    // Multi-set: reconstruct "score:score" per set
    final sets = <String>[];
    for (int i = 0; i < playerSubs.length; i++) {
      final pScore = (playerSubs[i]['se_result'] as num?)?.toInt() ?? 0;
      final oScore = i < opponentSubs.length ? (opponentSubs[i]['se_result'] as num?)?.toInt() ?? 0 : 0;
      sets.add('$pScore:$oScore');
    }
    return sets.join(' ');
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
}
