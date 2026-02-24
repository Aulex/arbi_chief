import 'package:sqflite/sqflite.dart';
import '../models/tournament_model.dart';
import 'database_service.dart';

class TournamentService {
  final DatabaseService _dbService;
  TournamentService(this._dbService);

  // Fetch all tournaments from the CMP_TOURNAMENT table 🏆
  Future<List<Tournament>> getAllTournaments() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'CMP_TOURNAMENT',
      orderBy: 't_id DESC',
    );
    return List.generate(maps.length, (i) => Tournament.fromJson(maps[i]));
  }

  // Insert or Update a tournament 💾
  Future<void> saveTournament(Tournament tournament) async {
    final db = await _dbService.database;
    final data = tournament.toJson();

    if (tournament.t_id == null) {
      // New record: remove t_id to let SQLite autoincrement 🔑
      await db.insert('CMP_TOURNAMENT', data);
    } else {
      // Update existing record
      await db.update(
        'CMP_TOURNAMENT',
        data,
        where: 't_id = ?',
        whereArgs: [tournament.t_id],
      );
    }
  }

  // Remove a tournament 🗑️
  Future<void> deleteTournament(int id) async {
    final db = await _dbService.database;
    await db.delete('CMP_TOURNAMENT', where: 't_id = ?', whereArgs: [id]);
  }
}
