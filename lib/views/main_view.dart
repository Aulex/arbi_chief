import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/navigation_viewmodel.dart';
import '../viewmodels/nav_provider.dart'; // Import the new one
import 'player_view.dart';
import 'tournament_view.dart';
import 'tournament_add_screen.dart';

class MainView extends ConsumerWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationProvider);
    // Watch the tournament sub-navigation
    final tournamentState = ref.watch(tournamentNavProvider);

    // Swap content for Index 0
    final List<Widget> screens = [
      tournamentState == 'list'
          ? const TournamentView()
          : const TournamentAddScreen(),
      const PlayerView(),
      const Center(child: Text('Games Screen')),
      const Center(child: Text('Settings Screen')),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Tournament Manager Pro'), elevation: 2),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              // Using your Notifier method
              ref.read(navigationProvider.notifier).setTab(index);

              // Reset tournament view to list if user switches away and back
              if (index != 0) {
                ref.read(tournamentNavProvider.notifier).showList();
              }
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.emoji_events),
                label: Text('Tournaments'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people),
                label: Text('Players'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.sports_esports),
                label: Text('Games'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              // Key needs to change when either the main tab or the sub-view changes
              child: Container(
                key: ValueKey<String>('$selectedIndex-$tournamentState'),
                child: screens[selectedIndex],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
