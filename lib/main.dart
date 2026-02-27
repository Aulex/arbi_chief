import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'views/main_view.dart';
import 'views/tv_display_screen.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Check if this is a sub-window
  if (args.firstOrNull == 'multi_window') {
    final argument = args.length > 2 ? args[2] : '{}';
    final parsed = jsonDecode(argument) as Map<String, dynamic>;

    if (parsed['type'] == 'tv_display') {
      runApp(ProviderScope(
        child: _TvDisplayApp(
          tournamentId: parsed['tournamentId'] as int,
          tournamentName: parsed['tournamentName'] as String,
        ),
      ));
      return;
    }
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Менеджер турнірів',
      theme: ThemeData(useMaterial3: true),
      locale: const Locale('uk'),
      supportedLocales: const [Locale('uk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainView(),
    );
  }
}

class _TvDisplayApp extends StatelessWidget {
  final int tournamentId;
  final String tournamentName;
  const _TvDisplayApp({required this.tournamentId, required this.tournamentName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Результати - $tournamentName',
      theme: ThemeData(useMaterial3: true),
      locale: const Locale('uk'),
      supportedLocales: const [Locale('uk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: TvDisplayScreen(
        tournamentId: tournamentId,
        tournamentName: tournamentName,
      ),
    );
  }
}
