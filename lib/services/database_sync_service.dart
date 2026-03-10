import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'database_service.dart';

/// Describes a single column in a table.
class ColumnInfo {
  final String name;
  final String type;
  ColumnInfo(this.name, this.type);

  Map<String, dynamic> toJson() => {'name': name, 'type': type};
}

/// Service that handles database synchronisation (import from external .db
/// files, handling schema differences) and JSON export of both structure and
/// data.
class DatabaseSyncService {
  final DatabaseService _dbService;

  DatabaseSyncService(this._dbService);

  // ──────────────────────────────────────────────
  //  Canonical table order (used for sync & export)
  // ──────────────────────────────────────────────
  static const List<String> _tableOrder = [
    'CMP_TOURNAMENT_TYPE',
    'CMP_ENTITY',
    'CMP_ATTR',
    'CMP_ATTR_DICT',
    'CMP_TOURNAMENT_LOCATION',
    'CMP_TOURNAMENT_ORGANIZER',
    'CMP_TOURNAMENT',
    'CMP_ATTR_VALUE',
    'CMP_TOURNAMENT_STAGE',
    'CMP_EVENT',
    'CMP_PLAYER',
    'CMP_PLAYER_EVENT',
    'CMP_TEAM',
    'CMP_PLAYER_TEAM',
    'CMP_PLAYER_TEAM_ATTR_VALUE',
    'CMP_PLAYER_TOURNAMENT',
  ];

  // ──────────────────────────────────────────────
  //  Helper: get columns for a table
  // ──────────────────────────────────────────────
  Future<List<ColumnInfo>> _getColumns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) {
      return ColumnInfo(
        r['name'] as String,
        (r['type'] as String?) ?? 'TEXT',
      );
    }).toList();
  }

  /// Returns all user tables (excluding sqlite internal ones).
  Future<List<String>> _getUserTables(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' "
      "ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  // ──────────────────────────────────────────────
  //  SYNCHRONISE from an external .db file
  // ──────────────────────────────────────────────

  /// Synchronise data from [externalDbPath] into the current database.
  ///
  /// 1. Opens the external DB.
  /// 2. For each known table, adds any missing columns to the external DB so
  ///    that the schemas match (handles old DB files).
  /// 3. Reads all rows from the external DB and inserts them into the current
  ///    DB, skipping rows whose primary key already exists.
  ///
  /// Returns a human-readable log of what happened.
  Future<String> synchroniseFrom(String externalDbPath) async {
    final log = StringBuffer();
    final currentDb = await _dbService.database;

    // Open the external database (read-write so we can add missing columns).
    final extDb = await openDatabase(
      externalDbPath,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
    );

    try {
      final extTables = await _getUserTables(extDb);

      for (final table in _tableOrder) {
        if (!extTables.contains(table)) {
          log.writeln('[$table] — таблиця відсутня у зовнішній БД, пропуск.');
          continue;
        }

        // ── Align schemas: add missing columns to external DB ──
        final currentCols = await _getColumns(currentDb, table);
        final extCols = await _getColumns(extDb, table);
        final extColNames = extCols.map((c) => c.name).toSet();

        for (final col in currentCols) {
          if (!extColNames.contains(col.name)) {
            await extDb.execute(
              'ALTER TABLE $table ADD COLUMN ${col.name} ${col.type}',
            );
            log.writeln(
              '[$table] додано відсутню колонку "${col.name}" (${col.type}).',
            );
          }
        }

        // ── Read data from external DB ──
        final rows = await extDb.query(table);
        if (rows.isEmpty) continue;

        // Determine primary key column name (first column by convention).
        final pkCol = currentCols.first.name;

        int inserted = 0;
        int skipped = 0;

        await currentDb.transaction((txn) async {
          for (final row in rows) {
            // Check if the row already exists.
            final pkValue = row[pkCol];
            if (pkValue != null) {
              final existing = await txn.query(
                table,
                where: '$pkCol = ?',
                whereArgs: [pkValue],
              );
              if (existing.isNotEmpty) {
                skipped++;
                continue;
              }
            }

            // Only insert columns that exist in the current schema.
            final validRow = <String, dynamic>{};
            final currentColNames = currentCols.map((c) => c.name).toSet();
            for (final entry in row.entries) {
              if (currentColNames.contains(entry.key)) {
                validRow[entry.key] = entry.value;
              }
            }

            await txn.insert(table, validRow,
                conflictAlgorithm: ConflictAlgorithm.ignore);
            inserted++;
          }
        });

        if (inserted > 0 || skipped > 0) {
          log.writeln(
            '[$table] додано: $inserted, пропущено (дублі): $skipped.',
          );
        }
      }
    } finally {
      await extDb.close();
    }

    if (log.isEmpty) {
      return 'Синхронізацію завершено. Змін не виявлено.';
    }
    return log.toString().trimRight();
  }

  // ──────────────────────────────────────────────
  //  EXPORT database structure (schema) as JSON
  // ──────────────────────────────────────────────

  /// Returns a JSON string describing the structure of every table:
  /// ```json
  /// {
  ///   "export_type": "structure",
  ///   "exported_at": "...",
  ///   "tables": {
  ///     "TABLE_NAME": {
  ///       "columns": [ { "name": "...", "type": "..." }, ... ],
  ///       "create_sql": "CREATE TABLE ..."
  ///     }
  ///   }
  /// }
  /// ```
  Future<String> exportStructureJson() async {
    final db = await _dbService.database;
    final tables = await _getUserTables(db);

    final tablesMap = <String, dynamic>{};
    for (final table in tables) {
      final cols = await _getColumns(db, table);

      // Grab the original CREATE TABLE statement.
      final sqlRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      final createSql =
          sqlRows.isNotEmpty ? sqlRows.first['sql'] as String? : null;

      tablesMap[table] = {
        'columns': cols.map((c) => c.toJson()).toList(),
        if (createSql != null) 'create_sql': createSql,
      };
    }

    final result = {
      'export_type': 'structure',
      'exported_at': DateTime.now().toIso8601String(),
      'database_name': 'tournament_blueprint_v14.db',
      'tables': tablesMap,
    };

    return const JsonEncoder.withIndent('  ').convert(result);
  }

  // ──────────────────────────────────────────────
  //  EXPORT database data as JSON
  // ──────────────────────────────────────────────

  /// Returns a JSON string with every row of every table:
  /// ```json
  /// {
  ///   "export_type": "data",
  ///   "exported_at": "...",
  ///   "tables": {
  ///     "TABLE_NAME": [ { row }, { row }, ... ]
  ///   }
  /// }
  /// ```
  Future<String> exportDataJson() async {
    final db = await _dbService.database;

    final tablesMap = <String, dynamic>{};
    for (final table in _tableOrder) {
      final rows = await db.query(table);
      tablesMap[table] = rows;
    }

    final result = {
      'export_type': 'data',
      'exported_at': DateTime.now().toIso8601String(),
      'database_name': 'tournament_blueprint_v14.db',
      'tables': tablesMap,
    };

    return const JsonEncoder.withIndent('  ').convert(result);
  }

  // ──────────────────────────────────────────────
  //  EXPORT both structure + data combined
  // ──────────────────────────────────────────────

  /// Convenience: exports structure AND data in one JSON file.
  Future<String> exportFullJson() async {
    final db = await _dbService.database;
    final tables = await _getUserTables(db);

    final tablesMap = <String, dynamic>{};
    for (final table in tables) {
      final cols = await _getColumns(db, table);
      final sqlRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      final createSql =
          sqlRows.isNotEmpty ? sqlRows.first['sql'] as String? : null;
      final rows = await db.query(table);

      tablesMap[table] = {
        'columns': cols.map((c) => c.toJson()).toList(),
        if (createSql != null) 'create_sql': createSql,
        'row_count': rows.length,
        'data': rows,
      };
    }

    final result = {
      'export_type': 'full',
      'exported_at': DateTime.now().toIso8601String(),
      'database_name': 'tournament_blueprint_v14.db',
      'tables': tablesMap,
    };

    return const JsonEncoder.withIndent('  ').convert(result);
  }

  // ──────────────────────────────────────────────
  //  Save JSON string to file
  // ──────────────────────────────────────────────

  /// Writes [jsonContent] to [filePath]. Creates parent directories if needed.
  Future<void> saveJsonToFile(String jsonContent, String filePath) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonContent, flush: true);
  }
}
