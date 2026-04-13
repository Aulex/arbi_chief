import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'tournament_add_screen.dart';
import 'tournament_players_tab.dart';
import 'tournament_teams_tab.dart';
import 'tournament_cross_table_tab.dart';
import '../sports/swimming/swimming_results_tab.dart';
import '../sports/swimming/swimming_team_standings_tab.dart';
import '../sports/volleyball/volleyball_cross_table_tab.dart';
import '../sports/volleyball/volleyball_group_management_tab.dart';
import '../sports/arm_wrestling/arm_wrestling_team_standings_tab.dart';
import '../sports/futsal/futsal_cross_table_tab.dart';
import '../sports/basketball/basketball_cross_table_tab.dart';
import '../sports/basketball/basketball_group_management_tab.dart';
import '../sports/streetball/streetball_cross_table_tab.dart';
import '../sports/streetball/streetball_group_management_tab.dart';
import '../sports/tug_of_war/tug_of_war_cross_table_tab.dart';
import '../sports/athletics/athletics_results_tab.dart';
import '../sports/athletics/athletics_team_standings_tab.dart';
import '../sports/powerlifting/powerlifting_results_tab.dart';
import '../sports/powerlifting/powerlifting_team_standings_tab.dart';
import '../sports/cycling/cycling_results_tab.dart';
import '../sports/cycling/cycling_team_standings_tab.dart';
import '../sports/kettlebell/kettlebell_results_tab.dart';
import '../sports/kettlebell/kettlebell_team_standings_tab.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/standings_window_provider.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  final Tournament tournament;
  const TournamentEditScreen({super.key, required this.tournament});

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen>
    with TickerProviderStateMixin {
  SportTypeConfig get _sportConfig => getConfigForType(widget.tournament.t_type);
  bool get _isSwimming => isSwimming(widget.tournament.t_type);
  bool get _isVolleyball => isVolleyball(widget.tournament.t_type);
  bool get _isStreetball => widget.tournament.t_type == 5;
  bool get _isBasketball => widget.tournament.t_type == 4;
  bool get _isArmWrestling => isArmWrestling(widget.tournament.t_type);
  int _volleyballTeamCount = 0;
  int _basketballTeamCount = 0;
  int _streetballTeamCount = 0;
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  int get _currentTabCount {
    if (_isSwimming) return 5;
    if (_isArmWrestling) return 5;
    if (widget.tournament.t_type == 10) return 5; // Athletics
    if (widget.tournament.t_type == 12) return 5; // Cycling
    if (widget.tournament.t_type == 8) return 5; // Powerlifting
    if (widget.tournament.t_type == 13) return 5; // Kettlebell
    if (_isVolleyball) return _volleyballTeamCount >= 9 ? 5 : 4;
    if (_isBasketball) return _basketballTeamCount >= 9 ? 5 : 4;
    if (_isStreetball) return _streetballTeamCount >= 9 ? 5 : 4;
    return 4;
  }

  void _ensureTabController() {
    final neededLength = _currentTabCount;
    if (_tabController == null || _tabController!.length != neededLength) {
      int newIndex = _tabController?.index ?? 0;
      
      // If tab count changes for Volleyball (Groups tab added/removed), adjust index
      if (_tabController != null && (_isVolleyball || _isBasketball || _isStreetball)) {
        if (_tabController!.length == 4 && neededLength == 5) {
          // Groups tab added at index 1
          if (newIndex >= 1) newIndex++;
        } else if (_tabController!.length == 5 && neededLength == 4) {
          // Groups tab removed from index 1
          if (newIndex > 1) newIndex--;
          else if (newIndex == 1) newIndex = 0; // If they were magically on Groups, go to Table
        }
      }

      _tabController?.dispose();
      _tabController = TabController(
        length: neededLength,
        vsync: this,
        initialIndex: newIndex.clamp(0, neededLength - 1),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureTabController();
    if (_isVolleyball) {
      _loadVolleyballTeamCount();
    }
    if (_isBasketball) {
      _loadBasketballTeamCount();
    }
    if (_isStreetball) {
      _loadStreetballTeamCount();
    }
  }

  Future<void> _loadBasketballTeamCount() async {
    final teamSvc = ref.read(teamServiceProvider);
    final teams = await teamSvc.getTeamListForTournament(widget.tournament.t_id!);
    if (mounted) {
      setState(() {
        _basketballTeamCount = teams.length;
        _ensureTabController();
      });
    }
  }

  Future<void> _loadVolleyballTeamCount() async {
    final teamSvc = ref.read(teamServiceProvider);
    final teams = await teamSvc.getTeamListForTournament(widget.tournament.t_id!);
    if (mounted) {
      setState(() {
        _volleyballTeamCount = teams.length;
        _ensureTabController();
      });
    }
  }

  Future<void> _loadStreetballTeamCount() async {
    final teamSvc = ref.read(teamServiceProvider);
    final teams = await teamSvc.getTeamListForTournament(widget.tournament.t_id!);
    if (mounted) {
      setState(() {
        _streetballTeamCount = teams.length;
        _ensureTabController();
      });
    }
  }

  Future<void> _openStandingsWindow() async {
    // If already open, bring it to focus
    final existing = ref.read(standingsWindowControllerProvider);
    if (existing != null) {
      try {
        await existing.show();
        // Send latest standings data
        final snapshot = ref.read(standingsSnapshotProvider);
        if (snapshot != null) {
          await sendStandingsToWindow(existing, snapshot);
        }
        return;
      } catch (_) {
        // Window was closed, create new one
        ref.read(standingsWindowControllerProvider.notifier).setController(null);
      }
    }

    final snapshot = ref.read(standingsSnapshotProvider);
    final initialData = snapshot != null ? jsonEncode(snapshot.toJson()) : '{}';

    final window = await WindowController.create(
      WindowConfiguration(arguments: initialData),
    );
    await window.show();

    ref.read(standingsWindowControllerProvider.notifier).setController(window);
  }

  @override
  Widget build(BuildContext context) {
    final int tabCount;
    final List<Widget> tabs;
    final List<Widget> tabViews;

    if (_isSwimming) {
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pool_outlined, size: 18), SizedBox(width: 6), Text('Результати')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        SwimmingResultsTab(tId: widget.tournament.t_id!),
        SwimmingTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (_isArmWrestling) {
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        CrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name, config: _sportConfig, tType: widget.tournament.t_type),
        ArmWrestlingTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 10) { // Athletics
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pool_outlined, size: 18), SizedBox(width: 6), Text('Результати')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        AthleticsResultsTab(tId: widget.tournament.t_id!),
        AthleticsTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 12) { // Cycling
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pool_outlined, size: 18), SizedBox(width: 6), Text('Результати')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        CyclingResultsTab(tId: widget.tournament.t_id!),
        CyclingTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 8) { // Powerlifting
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pool_outlined, size: 18), SizedBox(width: 6), Text('Результати')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        PowerliftingResultsTab(tId: widget.tournament.t_id!),
        PowerliftingTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 13) { // Kettlebell
      tabCount = 5;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pool_outlined, size: 18), SizedBox(width: 6), Text('Результати')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Командний залік')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        KettlebellResultsTab(tId: widget.tournament.t_id!),
        KettlebellTeamStandingsTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (_isVolleyball) {
      final showGroups = _volleyballTeamCount >= 9;
      tabCount = showGroups ? 5 : 4;
      tabs = [
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        if (showGroups)
          const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.group_work_outlined, size: 18), SizedBox(width: 6), Text('Групи')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        VolleyballCrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name),
        if (showGroups)
          VolleyballGroupManagementTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig, onTeamsChanged: _loadVolleyballTeamCount),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 2) { // Futsal
      tabCount = 4;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        FutsalCrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (_isBasketball) { // Basketball
      final showGroups = _basketballTeamCount >= 9;
      tabCount = showGroups ? 5 : 4;
      tabs = [
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        if (showGroups)
          const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.group_work_outlined, size: 18), SizedBox(width: 6), Text('Групи')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        BasketballCrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name),
        if (showGroups)
          BasketballGroupManagementTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig, onTeamsChanged: _loadBasketballTeamCount),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (_isStreetball) { // Streetball
      final showGroups = _streetballTeamCount >= 9;
      tabCount = showGroups ? 5 : 4;
      tabs = [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        if (showGroups)
          const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.group_work_outlined, size: 18), SizedBox(width: 6), Text('Групи')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        StreetballCrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name),
        if (showGroups)
          StreetballGroupManagementTab(tId: widget.tournament.t_id!),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig, onTeamsChanged: _loadStreetballTeamCount),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else if (widget.tournament.t_type == 14) { // Tug of War
      tabCount = 4;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        TugOfWarCrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    } else {
      tabCount = 4;
      tabs = const [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
      ];
      tabViews = [
        CrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name, config: _sportConfig, tType: widget.tournament.t_type),
        TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
        TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
        TournamentAddScreen(tournament: widget.tournament, isEditMode: true),
      ];
    }

    _ensureTabController();

    return Padding(
        padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
        child: Column(
          children: [
            // Header with back arrow | tabs
            Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        onPressed: () {
                          ref
                              .read(tournamentNavProvider.notifier)
                              .showList();
                        },
                      ),
                      SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          thickness: 1,
                          width: 24,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      Expanded(
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: Colors.indigo,
                          indicatorColor: Colors.indigo,
                          indicatorWeight: 2,
                          tabAlignment: TabAlignment.start,
                          tabs: tabs,
                        ),
                      ),
                      if (!_isSwimming && !_isVolleyball && !_isArmWrestling) ...[
                        SizedBox(
                          height: 32,
                          child: VerticalDivider(
                            thickness: 1,
                            width: 24,
                            color: Colors.grey.shade300,
                          ),
                        ),
                        Tooltip(
                          message: 'Відкрити таблицю на другому моніторі',
                          child: IconButton(
                            icon: const Icon(Icons.open_in_new, size: 20),
                            onPressed: _openStandingsWindow,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: tabViews,
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildBoardsTab() {
    final tId = widget.tournament.t_id!;
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    return FutureBuilder<String?>(
      future: svc.getAttrDictValue(tId, 2), // attr_id=2: Система жеребкування
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final pairingSystem = snapshot.data;

        if (pairingSystem == 'Колова') {
          return _buildRoundRobinPairing(teamSvc, tId);
        }

        // Placeholder for other systems
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Дошки',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  pairingSystem != null
                      ? 'Система жеребкування: $pairingSystem (в розробці)'
                      : 'Система жеребкування не обрана.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoundRobinPairing(dynamic teamSvc, int tId) {
    return FutureBuilder<
        Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>>>(
      future: teamSvc.getBoardAssignmentsForTournament(tId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final boards = snapshot.data ?? {};

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_sportConfig.boardLabel}и — Колова система',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Розподіл гравців по ${_sportConfig.boardLabelPlural} з командних складів.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int boardNum = 1; boardNum <= _sportConfig.boardCount; boardNum++) ...[
                    if (boardNum > 1) const SizedBox(width: 16),
                    Expanded(
                      child: _buildBoardPairingCard(
                        boardNum,
                        boards[boardNum] ?? [],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoardPairingCard(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> entries,
  ) {
    final isWomenBoard = _sportConfig.lastBoardWomenOnly && boardNum == _sportConfig.boardCount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isWomenBoard ? Colors.pink.shade200 : Colors.grey.shade300,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      isWomenBoard ? Colors.pink : Colors.indigo,
                  child: Text(
                    '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _sportConfig.tabLabel(boardNum),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (entries.isEmpty)
              Text(
                'Немає гравців на цій позиції',
                style: TextStyle(color: Colors.grey.shade500),
              )
            else
              ...entries.map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(e.player.fullName),
                    subtitle: Text(e.teamName),
                  )),
          ],
        ),
      ),
    );
  }
}
