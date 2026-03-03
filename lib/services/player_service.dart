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

  // Insert or Update a player 💾
  Future<void> savePlayer(Player player) async {
    final db = await _dbService.database;
    final data = player.toJson();

    // Check if player_id is null (New Player) or has a value (Update)
    if (player.player_id == null) {
      // For a new record, we let the database handle the ID
      // player_id is already excluded or null in toJson() logic for new entries
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

  // Remove a player from the database 🗑️
  Future<void> deletePlayer(int id) async {
    final db = await _dbService.database;
    await db.delete('CMP_PLAYER', where: 'player_id = ?', whereArgs: [id]);
  }
}
