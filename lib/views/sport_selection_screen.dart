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

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final svc = ref.read(tournamentServiceProvider);
    final types = await svc.getTournamentTypes();
    setState(() {
      _types = types;
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
                      return _SportCard(
                        name: t.typeName,
                        icon: _iconForType(t.typeName),
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

  const _SportCard({required this.name, required this.icon, required this.onTap});

  @override
  State<_SportCard> createState() => _SportCardState();
}

class _SportCardState extends State<_SportCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: _hovering
                ? Colors.indigo.shade50
                : Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1B2838)
                    : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovering ? Colors.indigo : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A3A4E) : Colors.grey.shade300),
              width: _hovering ? 2 : 1,
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: Colors.indigo.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 48, color: _hovering ? Colors.indigo : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade700)),
              const SizedBox(height: 12),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _hovering ? Colors.indigo : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade300 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
