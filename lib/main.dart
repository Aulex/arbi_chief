import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'theme/app_themes.dart';
import 'viewmodels/font_scale_provider.dart';
import 'viewmodels/high_contrast_provider.dart';
import 'viewmodels/theme_provider.dart';
import 'views/sport_selection_screen.dart';
import 'views/standings_window.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if this is a sub-window created by desktop_multi_window.
  // Sub-windows have arguments set via WindowConfiguration.
  try {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isNotEmpty) {
      runApp(StandingsWindowApp(
        controller: controller,
        argument: controller.arguments,
      ));
      return;
    }
  } catch (_) {
    // Not a sub-window — proceed as main window
  }

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
    final fontScale = ref.watch(fontScaleProvider);
    final highContrast = ref.watch(highContrastProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tournament Manager',
      theme: buildLightTheme(highContrast: highContrast),
      darkTheme: buildDarkTheme(highContrast: highContrast),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('uk'),
      supportedLocales: const [Locale('uk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child!,
        );
      },
      home: const SportSelectionScreen(),
    );
  }
}
