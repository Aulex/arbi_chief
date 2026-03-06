import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/navigation_viewmodel.dart';
import '../viewmodels/nav_provider.dart';
import 'tournament_view.dart';
import 'tournament_add_screen.dart';
import 'tournament_edit_screen.dart';
import 'player_view.dart';
import 'team_view.dart';
import 'reports_list_view.dart';
import 'settings_view.dart';

class MainView extends ConsumerWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationProvider);
    // Watch the tournament sub-navigation
    final tournamentNav = ref.watch(tournamentNavProvider);

    // Swap content for Index 0
    Widget tournamentScreen;
    switch (tournamentNav.view) {
      case 'add':
        tournamentScreen = const TournamentAddScreen();
      case 'edit':
        tournamentScreen = TournamentEditScreen(
          tournament: tournamentNav.tournament!,
        );
      default:
        tournamentScreen = const TournamentView();
    }

    final List<Widget> screens = [
      tournamentScreen,
      const PlayerView(),
      const TeamView(),
      const ReportsListView(),
      const SettingsView(),
    ];

    final appBarTitle = tournamentNav.view == 'edit' && tournamentNav.tournament != null
        ? 'Менеджер турнірів: ${tournamentNav.tournament!.t_name}'
        : 'Менеджер турнірів';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
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
                label: Text('Турніри'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people),
                label: Text('Гравці'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.groups),
                label: Text('Команди'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.summarize),
                label: Text('Звіти'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Налаштування'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey<String>('$selectedIndex-${tournamentNav.view}-${tournamentNav.tournament?.t_id}'),
                child: screens[selectedIndex],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
