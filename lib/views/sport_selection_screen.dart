import 'package:flutter/material.dart';
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
    if (lower.contains('шах')) return Icons.grid_view_rounded;
    if (lower.contains('шашк')) return Icons.apps_rounded;
    if (lower.contains('футзал')) return Icons.sports_soccer;
    if (lower.contains('волейбол')) return Icons.sports_volleyball;
    if (lower.contains('баскетбол') || lower.contains('стрітбол')) return Icons.sports_basketball;
    if (lower.contains('плаван')) return Icons.pool;
    if (lower.contains('пауерліфтинг') || lower.contains('гирьов')) return Icons.fitness_center;
    if (lower.contains('армрестлінг')) return Icons.sports_martial_arts;
    if (lower.contains('легка атлетика')) return Icons.directions_run;
    if (lower.contains('теніс')) return Icons.sports_tennis;
    if (lower.contains('велоспорт')) return Icons.directions_bike;
    if (lower.contains('канат')) return Icons.group;
    if (lower.contains('орієнтуван')) return Icons.explore;
    if (lower.contains('го') || lower == 'go') return Icons.circle_outlined;
    return Icons.emoji_events;
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
            color: _hovering ? Colors.indigo.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovering ? Colors.indigo : Colors.grey.shade300,
              width: _hovering ? 2 : 1,
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: Colors.indigo.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 48, color: _hovering ? Colors.indigo : Colors.grey.shade700),
              const SizedBox(height: 12),
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _hovering ? Colors.indigo : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
