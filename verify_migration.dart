import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase('e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\tournament_blueprint_v14.db');
  
  print('--- Verification Report ---');
  
  var entityCount = (await db.rawQuery('SELECT COUNT(*) as count FROM CMP_ENTITY')).first['count'];
  print('Total Entities: $entityCount');
  
  var subEventCount = (await db.rawQuery('SELECT COUNT(*) as count FROM CMP_SUBEVENT')).first['count'];
  print('Total SubEvents: $subEventCount');
  
  var playerUnlinked = (await db.rawQuery('SELECT COUNT(*) as count FROM CMP_PLAYER WHERE entity_id IS NULL')).first['count'];
  print('Players without Entity: $playerUnlinked');

  var teamUnlinked = (await db.rawQuery('SELECT COUNT(*) as count FROM CMP_TEAM WHERE entity_id IS NULL')).first['count'];
  print('Teams without Entity: $teamUnlinked');
  
  print('\n--- Sample SubEvents ---');
  var sampleSubs = await db.query('CMP_SUBEVENT', limit: 5);
  for (var s in sampleSubs) {
    print(s);
  }

  await db.close();
}
