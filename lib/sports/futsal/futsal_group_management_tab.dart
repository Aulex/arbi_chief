import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'futsal_providers.dart';

/// Group management tab for futsal tournaments with ≥ 9 teams.
///
/// Supports automatic random draw and manual reassignment.
/// Top 2 teams from each group advance to the finals stage.
class FutsalGroupManagementTab extends ConsumerStatefulWidget {
  final int tId;

  const FutsalGroupManagementTab({super.key, required this.tId});

  @override
  ConsumerState<FutsalGroupManagementTab> createState() => _FutsalGroupManagementTabState();
}

class _FutsalGroupManagementTabState extends ConsumerState<FutsalGroupManagementTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber})> _teams = [];
  Map<int, String> _groups = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final fSvc = ref.read(futsalServiceProvider);

    final teams = await teamSvc.getTeamListForTournament(widget.tId);
    final groups = await fSvc.getGroupAssignments(widget.tId);

    setState(() {
      _teams = teams;
      _groups = groups;
      _loading = false;
    });
  }

  Future<void> _autoAssignGroups() async {
    final fSvc = ref.read(futsalServiceProvider);
    final teamIds = _teams.map((t) => t.teamId).toList();
    await fSvc.autoAssignGroups(widget.tId, teamIds);
    await _loadData();
  }

  Future<void> _clearGroups() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистити групи?'),
        content: const Text('Всі призначення груп будуть видалені.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистити')),
        ],
      ),
    );
    if (confirmed != true) return;

    final fSvc = ref.read(futsalServiceProvider);
    await fSvc.clearGroupAssignments(widget.tId);
    await _loadData();
  }

  Future<void> _reassignTeam(int teamId, String currentGroup) async {
    final groupNames = _groups.values.toSet().toList()..sort();
    if (groupNames.isEmpty) return;

    final newGroup = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Перемістити в групу'),
        children: [
          for (final g in groupNames)
            if (g != currentGroup)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, g),
                child: Text('Група $g'),
              ),
        ],
      ),
    );

    if (newGroup == null) return;
    final fSvc = ref.read(futsalServiceProvider);
    await fSvc.setGroupAssignment(widget.tId, teamId, newGroup);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_teams.isEmpty) {
      return const Center(child: Text('Додайте команди для розподілу по групах'));
    }

    final groupNames = _groups.values.toSet().toList()..sort();
    final unassigned = _teams.where((t) => !_groups.containsKey(t.teamId)).toList();

    final groupSizes = <String, int>{};
    for (final g in groupNames) {
      groupSizes[g] = _groups.values.where((v) => v == g).length;
    }
    final isUnbalanced = groupSizes.isNotEmpty &&
        groupSizes.values.reduce((a, b) => a > b ? a : b) -
            groupSizes.values.reduce((a, b) => a < b ? a : b) > 1;

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
            Row(
              children: [
                const Text(
                  'Розподіл по групах (Футзал)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (isUnbalanced)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Tooltip(
                      message: 'Групи не збалансовані',
                      child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Жеребкування'),
                  onPressed: _autoAssignGroups,
                ),
                const SizedBox(width: 8),
                if (_groups.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Очистити'),
                    onPressed: _clearGroups,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Дві перші команди з підгрупи виходять у фінал (місця 1–8).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            if (groupNames.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_work_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Натисніть "Жеребкування" для автоматичного розподілу команд по групах',
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < groupNames.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(child: _buildGroupColumn(groupNames[i])),
                          ],
                        ],
                      ),
                      if (unassigned.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text(
                          'Без групи (${unassigned.length}):',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: unassigned.map((t) => ActionChip(
                            label: Text(t.teamName),
                            tooltip: 'Призначити в групу',
                            onPressed: () => _reassignTeamToNew(t.teamId),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupColumn(String groupName) {
    final teamsInGroup = _teams.where((t) => _groups[t.teamId] == groupName).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade200, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.indigo,
                  child: Text(
                    groupName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Група $groupName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${teamsInGroup.length} команд',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            const Divider(height: 16),
            for (final team in teamsInGroup)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.indigo.shade50,
                  child: Text(
                    '${team.teamNumber ?? teamsInGroup.indexOf(team) + 1}',
                    style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
                  ),
                ),
                title: Text(team.teamName, style: const TextStyle(fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  tooltip: 'Перемістити',
                  onPressed: () => _reassignTeam(team.teamId, groupName),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reassignTeamToNew(int teamId) async {
    final groupNames = _groups.values.toSet().toList()..sort();
    if (groupNames.isEmpty) return;

    final newGroup = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Призначити в групу'),
        children: [
          for (final g in groupNames)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text('Група $g'),
            ),
        ],
      ),
    );

    if (newGroup == null) return;
    final fSvc = ref.read(futsalServiceProvider);
    await fSvc.setGroupAssignment(widget.tId, teamId, newGroup);
    await _loadData();
  }
}
