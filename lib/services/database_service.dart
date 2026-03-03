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
    final dbPath = Platform.isWindows
        ? File(Platform.resolvedExecutable).parent.path
        : await getDatabasesPath();

    // v6 to reflect the strict alignment with the SQL blueprint 📐
    final path = join(dbPath, 'tournament_blueprint_v14.db');

    return await openDatabase(
      path,
      version: 3,
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
      },
      onCreate: (db, version) async {
        // 1. CMP_TOURNAMENT_TYPE
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_TYPE (
            type_id INTEGER PRIMARY KEY AUTOINCREMENT,
            type_name TEXT
          )
        ''');

        // 2. CMP_ENTITY
        await db.execute('''
          CREATE TABLE CMP_ENTITY (
            ent_id INTEGER PRIMARY KEY AUTOINCREMENT,
            ent_t_type INTEGER,
            ent_name TEXT,
            FOREIGN KEY (ent_t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id)
          )
        ''');

        // 3. CMP_ATTR
        await db.execute('''
          CREATE TABLE CMP_ATTR (
            attr_id INTEGER PRIMARY KEY AUTOINCREMENT,
            attr_name TEXT,
            attr_enable INTEGER DEFAULT 1,
            attr_visible INTEGER DEFAULT 1,
            attr_t_type INTEGER DEFAULT 1,
            attr_data_type TEXT,
            attr_entity_type INTEGER,
            FOREIGN KEY (attr_t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id),
            FOREIGN KEY (attr_entity_type) REFERENCES CMP_ENTITY (ent_id)
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
            location_country TEXT,
            location_city TEXT,
            location_address TEXT
          )
        ''');

        // 5. CMP_TOURNAMENT_ORGANIZER
        await db.execute('''
          CREATE TABLE CMP_TOURNAMENT_ORGANIZER (
            organizer_id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            player_date_birth TEXT,
            t_type INTEGER,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id)
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
            team_name TEXT,
            t_type INTEGER,
            FOREIGN KEY (t_type) REFERENCES CMP_TOURNAMENT_TYPE (type_id)
          )
        ''');

        // 13. CMP_PLAYER_TEAM
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TEAM (
            pte_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id INTEGER,
            player_id INTEGER,
            t_id INTEGER,
            team_number INTEGER,
            asgn_date TEXT,
            player_state INTEGER,
            FOREIGN KEY (team_id) REFERENCES CMP_TEAM (team_id),
            FOREIGN KEY (player_id) REFERENCES CMP_PLAYER (player_id),
            FOREIGN KEY (t_id) REFERENCES CMP_TOURNAMENT (t_id)
          )
        ''');

        // 14. CMP_PLAYER_TEAM_ATTR_VALUE
        await db.execute('''
          CREATE TABLE CMP_PLAYER_TEAM_ATTR_VALUE (
            pta_id INTEGER PRIMARY KEY AUTOINCREMENT,
            pte_id INTEGER,
            attr_id INTEGER,
            attr_value TEXT,
            att_value_dict_id INTEGER,
            FOREIGN KEY (pte_id) REFERENCES CMP_PLAYER_TEAM (pte_id),
            FOREIGN KEY (attr_id) REFERENCES CMP_ATTR (attr_id),
            FOREIGN KEY (att_value_dict_id) REFERENCES CMP_ATTR_DICT (dict_id)
          )
        ''');

        // 15. CMP_PLAYER_TOURNAMENT
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

        // ── Seed data ──

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
        await db.insert('CMP_ENTITY', {
          'ent_t_type': '1',
          'ent_name': 'Tournament',
        });
        await db.insert('CMP_ENTITY', {
          'ent_t_type': '1',
          'ent_name': 'Player',
        });
        await db.insert('CMP_ENTITY', {'ent_t_type': '1', 'ent_name': 'Team'});
        await db.insert('CMP_ENTITY', {'ent_t_type': '1', 'ent_name': 'Event'});

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
}
