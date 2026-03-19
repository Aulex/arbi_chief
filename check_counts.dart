import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final dbPath = 'e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\tournament_blueprint_v14.db';
  var db = await databaseFactory.openDatabase(dbPath);

  final tRow = await db.rawQuery('SELECT t_id, count(*) as c FROM CMP_SWIMMING_RESULT GROUP BY t_id ORDER BY c DESC LIMIT 1');
  if (tRow.isEmpty) {
    print('No results');
    return;
  }
  final tId = tRow.first['t_id'] as int;

  final catRows = await db.rawQuery('SELECT category, count(*) as c FROM CMP_SWIMMING_RESULT WHERE t_id = ? GROUP BY category', [tId]);
  for (var row in catRows) {
    print('Category: "${row['category']}" - Count: ${row['c']}');
  }

  await db.close();
}
