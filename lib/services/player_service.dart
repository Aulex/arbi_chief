import 'package:sqflite/sqflite.dart';
import '../models/player_model.dart';
import 'database_service.dart';

class PlayerService {
  final DatabaseService _dbService;

  PlayerService(this._dbService);

  // Fetch players filtered by sport type
  Future<List<Player>> getAllPlayers({int? tType}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps;
    if (tType != null) {
      maps = await db.query('CMP_PLAYER', where: 't_type = ?', whereArgs: [tType]);
    } else {
      maps = await db.query('CMP_PLAYER');
    }
    return List.generate(maps.length, (i) => Player.fromJson(maps[i]));
  }

  // Insert or Update a player
  Future<void> savePlayer(Player player) async {
    final db = await _dbService.database;
    final data = player.toJson();

    if (player.player_id == null) {
      // New player: create CMP_ENTITY first, then insert player with entity_id
      final entId = await db.insert('CMP_ENTITY', {
        'entity_type_id': 1,
        'sync_uid': await SyncUidGenerator.generate(),
      });
      data['entity_id'] = entId;
      data['sync_uid'] = await SyncUidGenerator.generate();
      await db.insert('CMP_PLAYER', data);
    } else {
      // Update existing record where player_id matches
      await db.update(
        'CMP_PLAYER',
        data,
        where: 'player_id = ?',
        whereArgs: [player.player_id],
      );
    }
  }

  /// Bulk-insert new players in a single transaction. Returns the list of
  /// generated player IDs in the same order as [players].
  Future<List<int>> bulkSavePlayers(List<Player> players) async {
    final db = await _dbService.database;
    final ids = <int>[];
    await db.transaction((txn) async {
      for (final player in players) {
        final data = player.toJson();
        // Create CMP_ENTITY for each new player
        final entId = await txn.insert('CMP_ENTITY', {
          'entity_type_id': 1,
          'sync_uid': await SyncUidGenerator.generate(),
        });
        data['entity_id'] = entId;
        data['sync_uid'] = await SyncUidGenerator.generate();
        final id = await txn.insert('CMP_PLAYER', data);
        ids.add(id);
      }
    });
    return ids;
  }

  // Remove a player and all related records
  Future<void> deletePlayer(int id) async {
    final db = await _dbService.database;
    final entityId = await _dbService.ensurePlayerEntity(db, id);

    // Delete CMP_SUBEVENT records referencing this entity
    if (entityId != null) {
      await db.delete('CMP_SUBEVENT', where: 'entity_id = ?', whereArgs: [entityId]);
    }
    // Delete CMP_PLAYER_TEAM_ATTR_VALUE for all assignments
    final assignments = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'], where: 'player_id = ?', whereArgs: [id]);
    for (final a in assignments) {
      await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ?', whereArgs: [a['pte_id']]);
    }
    // Delete CMP_PLAYER_TEAM records
    await db.delete('CMP_PLAYER_TEAM', where: 'player_id = ?', whereArgs: [id]);
    // Delete CMP_PLAYER_TOURNAMENT records
    await db.delete('CMP_PLAYER_TOURNAMENT', where: 'player_id = ?', whereArgs: [id]);
    // Delete the player
    await db.delete('CMP_PLAYER', where: 'player_id = ?', whereArgs: [id]);
    // Delete orphaned CMP_ENTITY
    if (entityId != null) {
      await db.delete('CMP_ENTITY', where: 'ent_id = ?', whereArgs: [entityId]);
    }
  }
}
