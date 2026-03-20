import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase('e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db');
  var results = await db.rawQuery('SELECT t_id, COUNT(*) as c FROM CMP_SWIMMING_RESULT GROUP BY t_id');
  print('Tournaments with swimming results: $results');
  await db.close();
}
