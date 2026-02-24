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
}
