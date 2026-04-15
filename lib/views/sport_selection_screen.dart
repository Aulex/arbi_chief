import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/sport_type_provider.dart';
import '../viewmodels/navigation_viewmodel.dart';
import '../viewmodels/nav_provider.dart';
import 'main_view.dart';

class SportSelectionScreen extends ConsumerStatefulWidget {
  const SportSelectionScreen({super.key});

  @override
  ConsumerState<SportSelectionScreen> createState() => _SportSelectionScreenState();
}

class _SportSelectionScreenState extends ConsumerState<SportSelectionScreen> {
  List<({int typeId, String typeName})> _types = [];
  bool _loading = true;

  /// Sports that are fully implemented and clickable.
  static const _enabledSports = {
    'Шахи',
    'Шашки',
    'Настільний теніс',
    'Плавання',
    'Волейбол',
    'Баскетбол',
    'Стрітбол',
  };

  /// Desired display order (excluding Спортивне орієнтування).
  static const _sportOrder = [
    'Футзал',
    'Шашки',
    'Гирьовий спорт',
    'Шахи',
    'Настільний теніс',
    'Плавання',
    'Армрестлінг',
    'Волейбол',
    'Стрітбол',
    'Легка атлетика',
    'Велоспорт',
    'Баскетбол',
    'Пауерліфтинг',
    'Перетягування канату',
  ];

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final svc = ref.read(tournamentServiceProvider);
    final types = await svc.getTournamentTypes();

    // Filter out Спортивне орієнтування and sort by the desired order.
    final filtered = types
        .where((t) => t.typeName != 'Спортивне орієнтування')
        .toList();

    filtered.sort((a, b) {
      final idxA = _sportOrder.indexOf(a.typeName);
      final idxB = _sportOrder.indexOf(b.typeName);
      // Sports not in the list go to the end.
      return (idxA == -1 ? 999 : idxA).compareTo(idxB == -1 ? 999 : idxB);
    });

    setState(() {
      _types = filtered;
      _loading = false;
    });
  }

  IconData _iconForType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('шах')) return Symbols.chess_rounded;              // Chess
    if (lower.contains('шашк')) return Symbols.grid_on_rounded;           // Checkers
    if (lower.contains('футзал')) return Symbols.sports_soccer_rounded;
    if (lower.contains('волейбол')) return Symbols.sports_volleyball_rounded;
    if (lower.contains('стрітбол')) return Symbols.sports_basketball_rounded;
    if (lower.contains('баскетбол')) return Symbols.sports_basketball_rounded;
    if (lower.contains('плаван')) return Symbols.pool_rounded;
    if (lower.contains('пауерліфтинг')) return Symbols.fitness_center_rounded;
    if (lower.contains('гирьов') || lower.contains('важк')) return Symbols.exercise_rounded;
    if (lower.contains('армрестлінг')) return Symbols.sports_martial_arts_rounded;
    if (lower.contains('легка атлетика')) return Symbols.sprint_rounded;
    if (lower.contains('настільний теніс')) return Symbols.sports_tennis_rounded;
    if (lower.contains('теніс')) return Symbols.sports_tennis_rounded;
    if (lower.contains('велоспорт')) return Symbols.directions_bike_rounded;
    if (lower.contains('перетяг') || lower.contains('канат')) return Symbols.group_work_rounded;
    if (lower.contains('орієнтуван')) return Symbols.explore_rounded;
    if (lower.contains('го') || lower == 'go') return Symbols.circle_rounded;
    return Symbols.emoji_events_rounded;
  }

  void _selectType(int typeId) {
    ref.read(selectedSportTypeProvider.notifier).select(typeId);
    ref.read(navigationProvider.notifier).setTab(0);
    ref.read(tournamentNavProvider.notifier).showList();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Оберіть вид спорту',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: _types.map((t) {
                      final enabled = _enabledSports.contains(t.typeName);
                      return _SportCard(
                        name: enabled
                            ? t.typeName
                            : '${t.typeName}\n(у розробці)',
                        icon: _iconForType(t.typeName),
                        enabled: enabled,
                        onTap: () => _selectType(t.typeId),
                      );
                    }).toList(),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SportCard extends StatefulWidget {
  final String name;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _SportCard({
    required this.name,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_SportCard> createState() => _SportCardState();
}

class _SportCardState extends State<_SportCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.enabled;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovering = true) : null,
      onExit: enabled ? (_) => setState(() => _hovering = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: !enabled
                ? (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200)
                : _hovering
                    ? Colors.indigo.shade50
                    : isDark
                        ? const Color(0xFF1B2838)
                        : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: !enabled
                  ? (isDark ? Colors.grey.shade700 : Colors.grey.shade400)
                  : _hovering
                      ? Colors.indigo
                      : (isDark ? const Color(0xFF2A3A4E) : Colors.grey.shade300),
              width: _hovering && enabled ? 2 : 1,
            ),
            boxShadow: _hovering && enabled
                ? [BoxShadow(color: Colors.indigo.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 48,
                  color: !enabled
                      ? Colors.grey
                      : _hovering
                          ? Colors.indigo
                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: enabled ? 16 : 13,
                    fontWeight: FontWeight.w600,
                    color: !enabled
                        ? Colors.grey
                        : _hovering
                            ? Colors.indigo
                            : (isDark ? Colors.grey.shade300 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
