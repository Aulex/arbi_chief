import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var db = await databaseFactoryFfi.openDatabase('e:\\Projects\\arbi_chief\\build\\windows\\x64\\runner\\Debug\\databaseFile.db');
  var results = await db.rawQuery('SELECT e.t_id, COUNT(*) as c FROM CMP_SUBEVENT se JOIN CMP_EVENT e ON se.ev_id = e.event_id WHERE se.se_note IN (\'m35\',\'m49\',\'m50\',\'f35\',\'f49\',\'relay\') GROUP BY e.t_id');
  print('Tournaments with swimming results: $results');
  await db.close();
}
