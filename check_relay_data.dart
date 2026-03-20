import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase('e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db');
  var results = await db.rawQuery('SELECT * FROM CMP_SWIMMING_RESULT WHERE category = "relay" LIMIT 5');
  for (var row in results) {
    print(row);
  }
  await db.close();
}
