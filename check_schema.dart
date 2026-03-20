import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase('e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db');
  var columns = await db.rawQuery('PRAGMA table_info(CMP_SWIMMING_RESULT)');
  for (var col in columns) {
    print('${col['name']} (${col['type']})');
  }
  await db.close();
}
