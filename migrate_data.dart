import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase(
    'e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db',
    options: OpenDatabaseOptions(
      version: 7,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          print('Upgrading schema to v7...');
          await db.execute('CREATE TABLE IF NOT EXISTS CMP_ENTITY (ent_id INTEGER PRIMARY KEY AUTOINCREMENT, sync_uid TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS CMP_EVENT_STATE (es_id INTEGER PRIMARY KEY AUTOINCREMENT, es_name TEXT, es_note TEXT, sync_uid TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS CMP_EVENT_TYPE (et_id INTEGER PRIMARY KEY AUTOINCREMENT, et_name TEXT, sync_uid TEXT)');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_SUBEVENT (
              se_id INTEGER PRIMARY KEY AUTOINCREMENT,
              ev_id INTEGER,
              entity_id INTEGER,
              se_result REAL,
              se_note TEXT,
              es_id INTEGER,
              sync_uid TEXT,
              FOREIGN KEY (ev_id) REFERENCES CMP_EVENT (event_id),
              FOREIGN KEY (entity_id) REFERENCES CMP_ENTITY (ent_id),
              FOREIGN KEY (es_id) REFERENCES CMP_EVENT_STATE (es_id)
            )
          ''');
          await db.execute('ALTER TABLE CMP_PLAYER ADD COLUMN entity_id INTEGER REFERENCES CMP_ENTITY(ent_id)');
          await db.execute('ALTER TABLE CMP_TEAM ADD COLUMN entity_id INTEGER REFERENCES CMP_ENTITY(ent_id)');
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN et_id INTEGER REFERENCES CMP_EVENT_TYPE(et_id)');
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN event_result TEXT');
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN es_id INTEGER REFERENCES CMP_EVENT_STATE(es_id)');

          final states = ['перемога', 'поразка', 'нічия', 'неявка'];
          for (final s in states) {
            await db.insert('CMP_EVENT_STATE', {'es_name': s});
          }
          final types = ['одиночний', 'командний'];
          for (final t in types) {
            await db.insert('CMP_EVENT_TYPE', {'et_name': t});
          }
        }
      },
    ),
  );
  
  print('Starting migration...');

  await db.transaction((txn) async {
    // 1. Players -> Entities
    print('Migrating Players...');
    var players = await txn.query('CMP_PLAYER');
    for (var p in players) {
      if (p['entity_id'] != null) continue;
      var entId = await txn.insert('CMP_ENTITY', {'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_mig_p_${p['player_id']}'});
      await txn.update('CMP_PLAYER', {'entity_id': entId}, where: 'player_id = ?', whereArgs: [p['player_id']]);
    }

    // 2. Teams -> Entities
    print('Migrating Teams...');
    var teams = await txn.query('CMP_TEAM');
    for (var t in teams) {
      if (t['entity_id'] != null) continue;
      var entId = await txn.insert('CMP_ENTITY', {'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_mig_t_${t['team_id']}'});
      await txn.update('CMP_TEAM', {'entity_id': entId}, where: 'team_id = ?', whereArgs: [t['team_id']]);
    }

    // 3. PlayerEvent -> SubEvents
    print('Migrating PlayerEvents to SubEvents...');
    var pes = await txn.rawQuery('''
      SELECT pe.*, p.entity_id as ent_id 
      FROM CMP_PLAYER_EVENT pe
      JOIN CMP_PLAYER p ON pe.player_id = p.player_id
    ''');
    
    for (var pe in pes) {
      var detail = pe['event_result_detail'] as String?;
      if (detail != null && detail.trim().isNotEmpty) {
        var sets = detail.trim().split(RegExp(r'\s+'));
        for (int i = 0; i < sets.length; i++) {
          var set = sets[i];
          var scores = set.split(':');
          if (scores.length >= 1) {
            var myScore = double.tryParse(scores[0]);
            if (myScore != null) {
              await txn.insert('CMP_SUBEVENT', {
                'ev_id': pe['event_id'],
                'entity_id': pe['ent_id'],
                'se_result': myScore,
                'se_note': 'Set ${i + 1}',
                'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_mig_pe_${pe['pe_id']}_s$i',
              });
            }
          }
        }
      } else if (pe['event_result'] != null) {
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': pe['event_id'],
          'entity_id': pe['ent_id'],
          'se_result': pe['event_result'],
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_mig_pe_${pe['pe_id']}',
        });
      }
    }

    // 4. Swimming migration removed (CMP_SWIMMING_RESULT table dropped)
  });

  print('Migration complete!');
  await db.close();
}
