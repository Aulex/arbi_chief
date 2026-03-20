import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final dbPath = 'e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db';
  var db = await databaseFactory.openDatabase(dbPath);

  final tRow = await db.rawQuery('SELECT e.t_id, count(*) as c FROM CMP_SUBEVENT se JOIN CMP_EVENT e ON se.ev_id = e.event_id WHERE se.se_note IN (\'m35\',\'m49\',\'m50\',\'f35\',\'f49\',\'relay\') GROUP BY e.t_id ORDER BY c DESC LIMIT 1');
  if (tRow.isEmpty) {
    print('No results');
    return;
  }
  final tId = tRow.first['t_id'] as int;

  final catRows = await db.rawQuery('SELECT se.se_note as category, count(*) as c FROM CMP_SUBEVENT se JOIN CMP_EVENT e ON se.ev_id = e.event_id WHERE e.t_id = ? AND se.se_note IN (\'m35\',\'m49\',\'m50\',\'f35\',\'f49\',\'relay\') GROUP BY se.se_note', [tId]);
  for (var row in catRows) {
    print('Category: "${row['category']}" - Count: ${row['c']}');
  }

  await db.close();
}
