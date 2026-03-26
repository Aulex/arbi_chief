import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Generates a globally-unique sync identifier for each row.
/// Format: `<timestamp_ms>_<machine_id>_<random>`
/// [machineId] should be loaded once from SharedPreferences at app start.
class SyncUidGenerator {
  static String? _machineId;

  static Future<String> getMachineId() async {
    if (_machineId != null) return _machineId!;
    final prefs = await SharedPreferences.getInstance();
    _machineId = prefs.getString('sync_machine_id');
    if (_machineId == null) {
      _machineId = _randomHex(8);
      await prefs.setString('sync_machine_id', _machineId!);
    }
    return _machineId!;
  }

  static String _randomHex(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  static Future<String> generate() async {
    final mid = await getMachineId();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rnd = _randomHex(6);
    return '${ts}_${mid}_$rnd';
  }
}

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = Platform.isWindows
        ? File(Platform.resolvedExecutable).parent.path
        : await getDatabasesPath();

    // v6 to reflect the strict alignment with the SQL blueprint 📐
    final path = join(dbPath, 'databaseFile.db');

    return await openDatabase(
      path,
      version: 12,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE CMP_PLAYER ADD COLUMN t_type INTEGER REFERENCES CMP_TOURNAMENT_TYPE(type_id)');
          await db.execute('ALTER TABLE CMP_TEAM ADD COLUMN t_type INTEGER REFERENCES CMP_TOURNAMENT_TYPE(type_id)');
          // Default existing players/teams to type 1 (Шахи)
          await db.execute('UPDATE CMP_PLAYER SET t_type = 1');
          await db.execute('UPDATE CMP_TEAM SET t_type = 1');
        }
        if (oldVersion < 3) {
          // Add table tennis specific tie-breakers
          await db.insert('CMP_ATTR_DICT', {
            'attr_id': '8',
            'dict_value': 'Різниця партій (між командами)',
          });
          await db.insert('CMP_ATTR_DICT', {
            'attr_id': '8',
            'dict_value': 'Різниця м\'ячів (між командами)',
          });
          await db.insert('CMP_ATTR_DICT', {
            'attr_id': '8',
            'dict_value': 'Різниця партій (у турнірі)',
          });
          await db.insert('CMP_ATTR_DICT', {
            'attr_id': '8',
            'dict_value': 'Результат жіночої ракетки',
          });
        }
        if (oldVersion < 5) {
          // Add sync_uid column to every user table for reliable duplicate detection during sync.
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
          );
          final machineId = await SyncUidGenerator.getMachineId();
          final rng = Random.secure();
          for (final row in tables) {
            final table = row['name'] as String;
            final cols = await db.rawQuery('PRAGMA table_info($table)');
            final hasSyncUid = cols.any((c) => c['name'] == 'sync_uid');
            if (!hasSyncUid) {
              await db.execute('ALTER TABLE $table ADD COLUMN sync_uid TEXT');
              // Backfill existing rows with unique sync_uid
              final pkCol = cols.firstWhere((c) => (c['pk'] as int) == 1)['name'] as String;
              final existing = await db.rawQuery('SELECT $pkCol FROM $table');
              for (final r in existing) {
                final pk = r[pkCol];
                final ts = DateTime.now().microsecondsSinceEpoch;
                final rnd = List.generate(6, (_) => rng.nextInt(16).toRadixString(16)).join();
                final uid = '${ts}_${machineId}_$rnd';
                await db.execute('UPDATE $table SET sync_uid = ? WHERE $pkCol = ?', [uid, pk]);
              }
            }
          }
        }
        if (oldVersion < 6) {
          // Swimming results table (legacy, will be dropped in v8)
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_SWIMMING_RESULT (
              sr_id INTEGER PRIMARY KEY AUTOINCREMENT,
              t_id INTEGER,
              player_id INTEGER,
              team_id INTEGER,
              category TEXT NOT NULL,
              time_min INTEGER NOT NULL DEFAULT 0,
              time_sec INTEGER NOT NULL DEFAULT 0,
              time_dsec INTEGER NOT NULL DEFAULT 0,
              time_total INTEGER NOT NULL DEFAULT 0,
              sync_uid TEXT,
              FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
              FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id),
              FOREIGN KEY (team_id) REFERENCES CMP_TEAM (team_id)
            )
          ''');
        }
        if (oldVersion < 7) {
          // 1. CMP_ENTITY
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_ENTITY (
              ent_id INTEGER PRIMARY KEY AUTOINCREMENT,
              sync_uid TEXT
            )
          ''');
          // 2. CMP_EVENT_STATE
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_EVENT_STATE (
              es_id INTEGER PRIMARY KEY AUTOINCREMENT,
              es_name TEXT,
              es_note TEXT,
              sync_uid TEXT
            )
          ''');
          // 3. CMP_EVENT_TYPE
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_EVENT_TYPE (
              et_id INTEGER PRIMARY KEY AUTOINCREMENT,
              et_name TEXT,
              sync_uid TEXT
            )
          ''');
          // 4. CMP_SUBEVENT
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
          // 5. Add entity_id to CMP_PLAYER and CMP_TEAM
          await db.execute('ALTER TABLE CMP_PLAYER ADD COLUMN entity_id INTEGER REFERENCES CMP_ENTITY(ent_id)');
          await db.execute('ALTER TABLE CMP_TEAM ADD COLUMN entity_id INTEGER REFERENCES CMP_ENTITY(ent_id)');
          // 6. Update CMP_EVENT with et_id, event_result, es_id
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN et_id INTEGER REFERENCES CMP_EVENT_TYPE(et_id)');
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN event_result TEXT');
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN es_id INTEGER REFERENCES CMP_EVENT_STATE(es_id)');

          // Seed EVENT_STATE
          final states = ['перемога', 'поразка', 'нічия', 'неявка'];
          for (final s in states) {
            await db.insert('CMP_EVENT_STATE', {'es_name': s});
          }
          // Seed EVENT_TYPE
          final types = ['одиночний', 'командний'];
          for (final t in types) {
            await db.insert('CMP_EVENT_TYPE', {'et_name': t});
          }
        }
        if (oldVersion < 8) {
          // Add t_id directly to CMP_EVENT (replacing ts_id → stage → tournament)
          await db.execute('ALTER TABLE CMP_EVENT ADD COLUMN t_id INTEGER REFERENCES CMP_TOURNAMENT(t_id)');
          // Populate t_id from the stage's tournament
          await db.execute('''
            UPDATE CMP_EVENT SET t_id = (
              SELECT ts.t_id FROM CMP_TOURNAMENT_STAGE ts
              WHERE ts.ts_id = CMP_EVENT.ts_id
            )
          ''');
          // Drop the legacy tables
          await db.execute('DROP TABLE IF EXISTS CMP_TOURNAMENT_STAGE');
          await db.execute('DROP TABLE IF EXISTS CMP_SWIMMING_RESULT');
        }
        if (oldVersion < 9) {
          // Recreate CMP_EVENT without the old ts_id foreign key to
          // CMP_TOURNAMENT_STAGE (which was dropped in v8). SQLite does not
          // support DROP COLUMN / DROP CONSTRAINT, so we rebuild the table.
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.execute('''
            CREATE TABLE CMP_EVENT_NEW (
              event_id INTEGER PRIMARY KEY AUTOINCREMENT,
              t_id INTEGER,
              et_id INTEGER,
              event_date_begin TEXT,
              event_date_end TEXT,
              event_result TEXT,
              es_id INTEGER,
              sync_uid TEXT,
              FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
              FOREIGN KEY (et_id) REFERENCES CMP_EVENT_TYPE (et_id),
              FOREIGN KEY (es_id) REFERENCES CMP_EVENT_STATE (es_id)
            )
          ''');
          await db.execute('''
            INSERT INTO CMP_EVENT_NEW (event_id, t_id, et_id, event_date_begin, event_date_end, event_result, es_id, sync_uid)
            SELECT event_id, t_id, et_id, event_date_begin, event_date_end, event_result, es_id, sync_uid
            FROM CMP_EVENT
          ''');
          await db.execute('DROP TABLE CMP_EVENT');
          await db.execute('ALTER TABLE CMP_EVENT_NEW RENAME TO CMP_EVENT');
          await db.execute('PRAGMA foreign_keys = ON');
        }
        if (oldVersion < 10) {
          // 1. Create CMP_ENTITY_TYPE
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_ENTITY_TYPE (
              entity_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
              entity_type_name TEXT,
              sync_uid TEXT
            )
          ''');
          // 2. Seed ENTITY_TYPE
          await db.insert('CMP_ENTITY_TYPE', {'entity_type_name': 'Гравець'});
          await db.insert('CMP_ENTITY_TYPE', {'entity_type_name': 'Команда'});
          
          // 3. Add entity_type_id to CMP_ENTITY
          await db.execute('ALTER TABLE CMP_ENTITY ADD COLUMN entity_type_id INTEGER REFERENCES CMP_ENTITY_TYPE(entity_type_id)');
          
          // 4. Backfill existing entities (if any remained, though we cleared db)
          // We can't easily know if an ent_id belongs to a player or team just from CMP_ENTITY,
          // but since we just cleared the DB, there should be 0 rows.
        }
        if (oldVersion < 11) {
          // CMP_TEAM_ATTR: per-team-per-tournament attributes (group assignment, removal flag)
          await db.execute('''
            CREATE TABLE IF NOT EXISTS CMP_TEAM_ATTR (
              ta_id INTEGER PRIMARY KEY AUTOINCREMENT,
              team_id INTEGER,
              t_id INTEGER,
              attr_id INTEGER,
              attr_value TEXT,
              sync_uid TEXT UNIQUE,
              FOREIGN KEY (team_id) REFERENCES CMP_TEAM(team_id),
              FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT(t_id),
              FOREIGN KEY (attr_id) REFERENCES CMP_ATTR(attr_id)
            )
          ''');
          // Seed "Група" attribute for volleyball (attr_entity_type=3 for team-tournament)
          await db.insert('CMP_ATTR', {
            'attr_id': '11',
            'attr_name': 'Група',
            'attr_data_type': 'TEXT',
            'attr_entity_type': 3,
            'attr_t_type': 3,
          });
        }
        if (oldVersion < 12) {
          // Volleyball tournament settings: finals, cross-group matches, cycle places
          await db.insert('CMP_ATTR', {
            'attr_id': 12,
            'attr_name': 'Місця до фіналу',
            'attr_data_type': 'TEXT',
            'attr_entity_type': 1,
          });
          await db.insert('CMP_ATTR', {
            'attr_id': 13,
            'attr_name': 'Місця для стикових матчів',
            'attr_data_type': 'TEXT',
            'attr_entity_type': 1,
          });
          await db.insert('CMP_ATTR', {
            'attr_id': 14,
            'attr_name': 'Місця для колових матчів',
            'attr_data_type': 'TEXT',
            'attr_entity_type': 1,
          });
        }
      },
      onCreate: (db, version) async {
        // 1. CMP_TOURNAMENT_TYPE
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_TYPE (
            type_id INTEGER PRIMARY KEY AUTOINCREMENT,
            type_name TEXT,
            sync_uid TEXT
          )
        ''');

        // 2. CMP_ENTITY (Modified in v10)
        await db.execute('''
          CREATE TABLE CMP_ENTITY (
            ent_id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (entity_type_id) REFERENCES CMP_ENTITY_TYPE (entity_type_id)
          )
        ''');

        // [NEW in v10] 2.1 CMP_ENTITY_TYPE
        await db.execute('''
          CREATE TABLE CMP_ENTITY_TYPE (
            entity_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type_name TEXT,
            sync_uid TEXT
          )
        ''');

        // 3. CMP_EVENT_STATE
        await db.execute('''
          CREATE TABLE CMP_EVENT_STATE (
            es_id INTEGER PRIMARY KEY AUTOINCREMENT,
            es_name TEXT,
            es_note TEXT,
            sync_uid TEXT
          )
        ''');

        // 4. CMP_EVENT_TYPE
        await db.execute('''
          CREATE TABLE CMP_EVENT_TYPE (
            et_id INTEGER PRIMARY KEY AUTOINCREMENT,
            et_name TEXT,
            sync_uid TEXT
          )
        ''');

        // 5. CMP_ATTR
        await db.execute('''
          CREATE TABLE CMP_ATTR (
            attr_id INTEGER PRIMARY KEY AUTOINCREMENT,
            attr_name TEXT,
            attr_enable INTEGER DEFAULT 1,
            attr_visible INTEGER DEFAULT 1,
            attr_t_type INTEGER DEFAULT 1,
            attr_data_type TEXT,
            attr_entity_type INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (attr_t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id)
          )
        ''');

        // 6. CMP_ATTR_DICT
        await db.execute('''
          CREATE TABLE CMP_ATTR_DICT (
            dict_id INTEGER PRIMARY KEY AUTOINCREMENT,
            attr_id INTEGER NOT NULL,
            dict_value TEXT,
            sync_uid TEXT,
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id)
          )
        ''');

        // 7. CMP_TOURNAMENT_LOCATION
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_LOCATION (
            location_id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_country TEXT,
            location_city TEXT,
            location_address TEXT,
            sync_uid TEXT
          )
        ''');

        // 8. CMP_TOURNAMENT_ORGANIZER
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_ORGANIZER (
            organizer_id INTEGER PRIMARY KEY AUTOINCREMENT,
            organizer_name TEXT,
            organizer_email TEXT,
            organizer_phone TEXT,
            sync_uid TEXT
          )
        ''');

        // 9. CMP_TOURNAMENT
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT (
            t_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_type INTEGER,
            t_name TEXT,
            t_date_begin TEXT,
            t_date_end TEXT,
            t_location INTEGER,
            t_org INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id),
            FOREIGN KEY (t_location) REFERENCES CMP_TOURNAMENT_LOCATION (location_id),
            FOREIGN KEY (t_org) REFERENCES CMP_TOURNAMENT_ORGANIZER (organizer_id)
          )
        ''');

        // 10. CMP_ATTR_VALUE
        await db.execute('''
          CREATE TABLE CMP_ATTR_VALUE (
            ta_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            attr_id INTEGER,
            attr_value TEXT,
            att_value_dict_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id),
            FOREIGN KEY (att_value_dict_id) REFERENCES CMP_ATTR_DICT (dict_id)
          )
        ''');

        // 11. CMP_EVENT
        await db.execute('''
          CREATE TABLE CMP_EVENT (
            event_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            et_id INTEGER,
            event_date_begin TEXT,
            event_date_end TEXT,
            event_result TEXT,
            es_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
            FOREIGN KEY (et_id) REFERENCES CMP_EVENT_TYPE (et_id),
            FOREIGN KEY (es_id) REFERENCES CMP_EVENT_STATE (es_id)
          )
        ''');

        // 13. CMP_PLAYER
        await db.execute('''
          CREATE TABLE CMP_PLAYER (
            player_id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_surname TEXT,
            player_name TEXT,
            player_lastname TEXT,
            player_gender INTEGER,
            player_date_birth TEXT,
            t_type INTEGER,
            entity_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id),
            FOREIGN KEY (entity_id) REFERENCES CMP_ENTITY (ent_id)
          )
        ''');

        // 14. CMP_TEAM
        await db.execute('''
          CREATE TABLE CMP_TEAM (
            team_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_name TEXT,
            t_type INTEGER,
            entity_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id),
            FOREIGN KEY (entity_id) REFERENCES CMP_ENTITY (ent_id)
          )
        ''');

        // 16. CMP_SUBEVENT
        await db.execute('''
          CREATE TABLE CMP_SUBEVENT (
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

        // 16b. CMP_TEAM_ATTR (NEW in v11)
        await db.execute('''
          CREATE TABLE CMP_TEAM_ATTR (
            ta_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id INTEGER,
            t_id INTEGER,
            attr_id INTEGER,
            attr_value TEXT,
            sync_uid TEXT UNIQUE,
            FOREIGN KEY (team_id) REFERENCES CMP_TEAM(team_id),
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT(t_id),
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR(attr_id)
          )
        ''');

        // 17. CMP_PLAYER_TEAM
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TEAM (
            pte_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id INTEGER,
            player_id INTEGER,
            t_id INTEGER,
            team_number INTEGER,
            asgn_date TEXT,
            player_state INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (team_id) REFERENCES CMP_TEAM (team_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id),
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id)
          )
        ''');

        // 18. CMP_PLAYER_TEAM_ATTR_VALUE
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TEAM_ATTR_VALUE (
            pta_id INTEGER PRIMARY KEY AUTOINCREMENT,
            pte_id INTEGER,
            attr_id INTEGER,
            attr_value TEXT,
            att_value_dict_id INTEGER,
            sync_uid TEXT,
            FOREIGN KEY (pte_id) REFERENCES CMP_PLAYER_TEAM (pte_id),
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id),
            FOREIGN KEY (att_value_dict_id) REFERENCES CMP_ATTR_DICT (dict_id)
          )
        ''');

        // 19. CMP_PLAYER_TOURNAMENT
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TOURNAMENT (
            pt_id INTEGER PRIMARY KEY AUTOINCREMENT,
            t_id INTEGER,
            player_id INTEGER,
            asgn_date TEXT,
            sync_uid TEXT,
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id)
          )
        ''');

        // ── Seed data ──

        // Event States
        await db.insert('CMP_EVENT_STATE', {'es_name': 'перемога'});
        await db.insert('CMP_EVENT_STATE', {'es_name': 'поразка'});
        await db.insert('CMP_EVENT_STATE', {'es_name': 'нічия'});
        await db.insert('CMP_EVENT_STATE', {'es_name': 'неявка'});

        // Event Types
        await db.insert('CMP_EVENT_TYPE', {'et_name': 'одиночний'});
        await db.insert('CMP_EVENT_TYPE', {'et_name': 'командний'});

        // Tournament types
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Шахи'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Футзал'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Волейбол'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Баскетбол'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Стрітбол'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Плавання'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Шашки'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Пауерліфтинг'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Армрестлінг'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Легка атлетика'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Настільний теніс'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Велоспорт'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Гирьовий спорт'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Перетягування канату'});
        await db.insert('CMP_TOURNAMENT_TYPE', {'type_name': 'Спортивне орієнтування'});
        // CMP_ENTITY records are created dynamically when players/teams are added

        // Entity Types (NEW in v10)
        await db.insert('CMP_ENTITY_TYPE', {'entity_type_name': 'Гравець'});
        await db.insert('CMP_ENTITY_TYPE', {'entity_type_name': 'Команда'});

        await db.insert('CMP_ATTR', {
          'attr_id': '1',
          'attr_name': 'Тип контролю часу',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '2',
          'attr_name': 'Система жеребкування',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '3',
          'attr_name': 'Кількість кіл',
          'attr_data_type': 'INTEGER',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '4',
          'attr_name': 'Сортування стартового списку',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '5',
          'attr_name': 'Формат заліку',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '6',
          'attr_name': 'Запасні гравці',
          'attr_data_type': 'INTEGER',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '7',
          'attr_name': 'Система нарахування очок',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });
        await db.insert('CMP_ATTR', {
          'attr_id': '8',
          'attr_name': 'Тай-брейки',
          'attr_data_type': 'DICT',
          'attr_entity_type': '1',
        });

        await db.insert('CMP_ATTR', {
          'attr_id': '9',
          'attr_name': 'Дошка',
          'attr_data_type': 'INTEGER',
          'attr_entity_type': '2',
        });

        // Неявка attribute for player-team (1 = no-show)
        await db.insert('CMP_ATTR', {
          'attr_id': '10',
          'attr_name': 'Неявка',
          'attr_data_type': 'INTEGER',
          'attr_entity_type': '2',
        });

        // Група attribute for volleyball team-tournament (NEW in v11)
        await db.insert('CMP_ATTR', {
          'attr_id': '11',
          'attr_name': 'Група',
          'attr_data_type': 'TEXT',
          'attr_entity_type': 3,
          'attr_t_type': 3,
        });

        // Volleyball tournament settings (NEW in v12)
        await db.insert('CMP_ATTR', {
          'attr_id': 12,
          'attr_name': 'Місця до фіналу',
          'attr_data_type': 'TEXT',
          'attr_entity_type': 1,
        });
        await db.insert('CMP_ATTR', {
          'attr_id': 13,
          'attr_name': 'Місця для стикових матчів',
          'attr_data_type': 'TEXT',
          'attr_entity_type': 1,
        });
        await db.insert('CMP_ATTR', {
          'attr_id': 14,
          'attr_name': 'Місця для колових матчів',
          'attr_data_type': 'TEXT',
          'attr_entity_type': 1,
        });

        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '1',
          'dict_value': 'Рапід',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '1',
          'dict_value': 'Бліц',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '1',
          'dict_value': 'Класика',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '2',
          'dict_value': 'Швейцарська',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '2',
          'dict_value': 'Колова',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '2',
          'dict_value': 'Олімпійська (на вибування)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '4',
          'dict_value': 'За алфавітом',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '4',
          'dict_value': 'За рейтингом',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '5',
          'dict_value': 'Особистий',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '5',
          'dict_value': 'Командний',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '5',
          'dict_value': 'Особисто-командний',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '7',
          'dict_value': 'Перемога',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '7',
          'dict_value': 'Нічия',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '7',
          'dict_value': 'Поразка',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Особиста зустріч',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Бухгольц (повний)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Бухгольц (усічений)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Зоннеборн-Бергер',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Кількість перемог',
        });

        // Table tennis specific tie-breakers
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Різниця партій (між командами)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Різниця м\'ячів (між командами)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Різниця партій (у турнірі)',
        });
        await db.insert('CMP_ATTR_DICT', {
          'attr_id': '8',
          'dict_value': 'Результат жіночої ракетки',
        });
      },
    );
  }
  /// Ensure a player has a CMP_ENTITY row; create one if missing (legacy data).
  Future<int> ensurePlayerEntity(dynamic db, int playerId) async {
    final rows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (rows.isEmpty) throw Exception('Player not found: $playerId');
    final existing = rows.first['entity_id'] as int?;
    if (existing != null) return existing;
    final entId = await db.insert('CMP_ENTITY', {
      'entity_type_id': 1, // Гравець
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ent_p',
    });
    await db.update('CMP_PLAYER', {'entity_id': entId}, where: 'player_id = ?', whereArgs: [playerId]);
    return entId;
  }

  /// Ensure a team has a CMP_ENTITY row; create one if missing (legacy data).
  Future<int> ensureTeamEntity(dynamic db, int teamId) async {
    final rows = await db.query('CMP_TEAM', columns: ['entity_id'], where: 'team_id = ?', whereArgs: [teamId]);
    if (rows.isEmpty) throw Exception('Team not found: $teamId');
    final existing = rows.first['entity_id'] as int?;
    if (existing != null) return existing;
    final entId = await db.insert('CMP_ENTITY', {
      'entity_type_id': 2, // Команда
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ent_t',
    });
    await db.update('CMP_TEAM', {'entity_id': entId}, where: 'team_id = ?', whereArgs: [teamId]);
    return entId;
  }
}
