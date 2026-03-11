import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'viewmodels/theme_provider.dart';
import 'views/sport_selection_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Менеджер турнірів',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF3F51B5), // Indigo seed
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        canvasColor: const Color(0xFF0D1B2A),
        cardColor: const Color(0xFF1B2838),
        dialogBackgroundColor: const Color(0xFF1B2838),
        dividerColor: const Color(0xFF2A3A4E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF152238),
          foregroundColor: Color(0xFFE0E6F0),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1B2838),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF152238),
        ),
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('uk'),
      supportedLocales: const [Locale('uk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SportSelectionScreen(),
    );
  }
}
