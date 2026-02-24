import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath =
        Platform.isWindows ? Directory.current.path : await getDatabasesPath();

    // v6 to reflect the strict alignment with the SQL blueprint 📐
    final path = join(dbPath, 'tournament_blueprint_v7.db');

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        // 1. CMP_TOURNAMENT_TYPE
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_TYPE (
            type_id INTEGER PRIMARY KEY AUTOINCREMENT,
            type_code TEXT,
            type_name TEXT
          )
        ''');

        // 2. CMP_ATTR
        await db.execute('''
          CREATE TABLE CMP_ATTR (
            attr_id INTEGER PRIMARY KEY AUTOINCREMENT,
            attr_code TEXT,
            attr_name TEXT,
            attr_enable INTEGER,
            attr_visible INTEGER,
            attr_t_type INTEGER,
            attr_data_type TEXT,
            attr_entity_type INTEGER,
            FOREIGN KEY (attr_t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id)
          )
        ''');

        // 3. CMP_ATTR_DICT
        await db.execute('''
          CREATE TABLE CMP_ATTR_DICT (
            dict_id INTEGER PRIMARY KEY AUTOINCREMENT,
            attr_id INTEGER NOT NULL,
            dict_value TEXT,
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id)
          )
        ''');

        // 4. CMP_TOURNAMENT_LOCATION
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_LOCATION (
            location_id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_code TEXT,
            location_country TEXT,
            location_city TEXT,
            location_address TEXT
          )
        ''');

        // 5. CMP_TOURNAMENT_ORGANIZER
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_ORGANIZER (
            organizer_id INTEGER PRIMARY KEY AUTOINCREMENT,
            organizer_code TEXT,
            organizer_name TEXT,
            organizer_email TEXT,
            organizer_phone TEXT
          )
        ''');

        // 6. CMP_TOURNAMENT
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT (
            t_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_type INTEGER,
            t_name TEXT,
            t_date_begin TEXT,
            t_date_end TEXT,
            t_location INTEGER,
            t_org INTEGER,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id),
            FOREIGN KEY (t_location) REFERENCES CMP_TOURNAMENT_LOCATION (location_id),
            FOREIGN KEY (t_org) REFERENCES CMP_TOURNAMENT_ORGANIZER (organizer_id)
          )
        ''');

        // 7. CMP_ATTR_VALUE
        await db.execute('''
          CREATE TABLE CMP_ATTR_VALUE (
            ta_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            attr_id INTEGER,
            attr_value TEXT,
            att_value_dict_id INTEGER,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id),
            FOREIGN KEY (att_value_dict_id) REFERENCES CMP_ATTR_DICT (dict_id)
          )
        ''');

        // 8. CMP_TOURNAMENT_STAGE
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_STAGE (
            ts_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            ts_name TEXT,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id)
          )
        ''');

        // 9. CMP_EVENT
        await db.execute('''
          CREATE TABLE CMP_EVENT (
            event_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type INTEGER,
            event_date_begin TEXT,
            event_date_end TEXT,
            ts_id INTEGER,
            FOREIGN KEY (ts_id) REFERENCES CMP_TOURNAMENT_STAGE (ts_id)
          )
        ''');

        // 10. CMP_PLAYER (Cleaned up to match blueprint exactly 👤)
        await db.execute('''
          CREATE TABLE CMP_PLAYER (
            player_id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_surname TEXT,
            player_name TEXT,
            player_lastname TEXT,
            player_gender INTEGER,
            player_date_birth TEXT
          )
        ''');

        // 11. CMP_PLAYER_EVENT
        await db.execute('''
          CREATE TABLE CMP_PLAYER_EVENT (
            pe_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id INTEGER,
            player_id INTEGER,
            asgn_date TEXT,
            event_result REAL,
            event_result_valid INTEGER,
            FOREIGN KEY (event_id) REFERENCES CMP_EVENT (event_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id)
          )
        ''');

        // 12. CMP_TEAM
        await db.execute('''
          CREATE TABLE CMP_TEAM (
            team_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_code TEXT,
            team_name TEXT
          )
        ''');

        // 13. CMP_PLAYER_TEAM
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TEAM (
            pte_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id INTEGER,
            player_id INTEGER,
            asgn_date TEXT,
            player_state INTEGER,
            FOREIGN KEY (team_id) REFERENCES CMP_TEAM (team_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id)
          )
        ''');

        // 14. CMP_PLAYER_TOURNAMENT
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TOURNAMENT (
            pt_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            player_id INTEGER,
            asgn_date TEXT,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id)
          )
        ''');
      },
    );
  }
}
