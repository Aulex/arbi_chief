import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/volleyball_model.dart';
import '../viewmodels/volleyball_viewmodel.dart';

/// Tab for entering and viewing volleyball match results.
class VolleyballResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const VolleyballResultsTab({super.key, required this.tId});

  @override
  ConsumerState<VolleyballResultsTab> createState() =>
      _VolleyballResultsTabState();
}

class _VolleyballResultsTabState extends ConsumerState<VolleyballResultsTab> {
  List<VolleyballMatch> _matches = [];
  Map<int, String> _teamNames = {};
  List<String> _groups = [];
  String? _selectedGroup;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = ref.read(volleyballServiceProvider);
    final teams = await svc.getTeamsForTournament(widget.tId);
    final groups = await svc.getGroups(widget.tId);

    final teamNames = <int, String>{};
    for (final t in teams) {
      teamNames[t.teamId] = t.teamName;
    }

    // If no groups, it's a round-robin tournament
    List<VolleyballMatch> matches;
    if (_selectedGroup != null) {
      matches = await svc.getMatches(widget.tId, groupName: _selectedGroup);
    } else if (groups.isNotEmpty) {
      matches = await svc.getMatches(widget.tId, groupName: groups.first);
    } else {
      matches = await svc.getMatches(widget.tId);
    }

    setState(() {
      _teamNames = teamNames;
      _groups = groups;
      if (_selectedGroup == null && groups.isNotEmpty) {
        _selectedGroup = groups.first;
      }
      _matches = matches;
      _loading = false;
    });
  }

  Future<void> _reloadMatches() async {
    final svc = ref.read(volleyballServiceProvider);
    final matches = _selectedGroup != null
        ? await svc.getMatches(widget.tId, groupName: _selectedGroup)
        : await svc.getMatches(widget.tId);
    setState(() => _matches = matches);
  }

  Future<void> _generateMatches() async {
    final svc = ref.read(volleyballServiceProvider);
    final teams = await svc.getTeamsForTournament(widget.tId);
    final teamIds = teams.map((t) => t.teamId).toList();

    if (teamIds.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Потрібно мінімум 2 команди')),
        );
      }
      return;
    }

    if (_groups.isNotEmpty && _selectedGroup != null) {
      // Generate for specific group - get teams in this group from existing matches
      final groupMatches =
          await svc.getMatches(widget.tId, groupName: _selectedGroup);
      final groupTeamIds = <int>{};
      for (final m in groupMatches) {
        groupTeamIds.add(m.homeTeamId);
        groupTeamIds.add(m.awayTeamId);
      }
      if (groupTeamIds.isEmpty) {
        // No matches yet, generate for all teams
        await svc.generateRoundRobinMatches(widget.tId, teamIds,
            groupName: _selectedGroup);
      }
    } else {
      // Simple round-robin for all teams
      await svc.generateRoundRobinMatches(widget.tId, teamIds);
    }

    await _reloadMatches();
  }

  Future<void> _showMatchResultDialog(VolleyballMatch match) async {
    final result = await showDialog<VolleyballMatch>(
      context: context,
      builder: (ctx) => _MatchResultDialog(
        match: match,
        homeTeamName: _teamNames[match.homeTeamId] ?? '?',
        awayTeamName: _teamNames[match.awayTeamId] ?? '?',
      ),
    );
    if (result != null) {
      final svc = ref.read(volleyballServiceProvider);
      await svc.saveMatch(result);
      await _reloadMatches();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Group selector (if mixed system)
        if (_groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Text('Підгрупа: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                ..._groups.map((g) => Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: ChoiceChip(
                        label: Text('Група $g'),
                        selected: _selectedGroup == g,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedGroup = g);
                            _reloadMatches();
                          }
                        },
                      ),
                    )),
              ],
            ),
          ),
        // Action buttons
        Row(
          children: [
            FilledButton.icon(
              onPressed: _generateMatches,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Згенерувати ігри'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Match list
        Expanded(
          child: _matches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_volleyball,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Немає ігор. Додайте команди та згенеруйте ігри.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _matches.length,
                  itemBuilder: (ctx, idx) {
                    final m = _matches[idx];
                    final homeName = _teamNames[m.homeTeamId] ?? '?';
                    final awayName = _teamNames[m.awayTeamId] ?? '?';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: m.isPlayed
                              ? Colors.green.shade200
                              : Colors.grey.shade300,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showMatchResultDialog(m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 12.0),
                          child: Row(
                            children: [
                              // Match number
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Home team
                              Expanded(
                                flex: 3,
                                child: Text(
                                  homeName,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontWeight: m.isPlayed &&
                                            m.homeSets > m.awaySets
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Score
                              SizedBox(
                                width: 80,
                                child: Center(
                                  child: m.isPlayed
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              m.scoreDisplay,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (m.setScoresDisplay.isNotEmpty)
                                              Text(
                                                m.setScoresDisplay,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        )
                                      : Text(
                                          'vs',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              // Away team
                              Expanded(
                                flex: 3,
                                child: Text(
                                  awayName,
                                  style: TextStyle(
                                    fontWeight: m.isPlayed &&
                                            m.awaySets > m.homeSets
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Forfeit indicator
                              if (m.isForfeit)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Tooltip(
                                    message: 'Неявка',
                                    child: Icon(Icons.warning_amber,
                                        size: 18, color: Colors.orange.shade700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Dialog for entering a volleyball match result.
class _MatchResultDialog extends StatefulWidget {
  final VolleyballMatch match;
  final String homeTeamName;
  final String awayTeamName;

  const _MatchResultDialog({
    required this.match,
    required this.homeTeamName,
    required this.awayTeamName,
  });

  @override
  State<_MatchResultDialog> createState() => _MatchResultDialogState();
}

class _MatchResultDialogState extends State<_MatchResultDialog> {
  late final TextEditingController _s1Home, _s1Away;
  late final TextEditingController _s2Home, _s2Away;
  late final TextEditingController _s3Home, _s3Away;
  bool _isForfeit = false;
  int? _forfeitTeamId; // which team didn't show up

  @override
  void initState() {
    super.initState();
    _s1Home = TextEditingController(
        text: widget.match.set1Home?.toString() ?? '');
    _s1Away = TextEditingController(
        text: widget.match.set1Away?.toString() ?? '');
    _s2Home = TextEditingController(
        text: widget.match.set2Home?.toString() ?? '');
    _s2Away = TextEditingController(
        text: widget.match.set2Away?.toString() ?? '');
    _s3Home = TextEditingController(
        text: widget.match.set3Home?.toString() ?? '');
    _s3Away = TextEditingController(
        text: widget.match.set3Away?.toString() ?? '');
    _isForfeit = widget.match.isForfeit;
    if (_isForfeit) {
      _forfeitTeamId = widget.match.homeSets < widget.match.awaySets
          ? widget.match.homeTeamId
          : widget.match.awayTeamId;
    }
  }

  @override
  void dispose() {
    _s1Home.dispose();
    _s1Away.dispose();
    _s2Home.dispose();
    _s2Away.dispose();
    _s3Home.dispose();
    _s3Away.dispose();
    super.dispose();
  }

  VolleyballMatch? _buildResult() {
    if (_isForfeit && _forfeitTeamId != null) {
      final isHomeForfeit = _forfeitTeamId == widget.match.homeTeamId;
      return widget.match.copyWith(
        homeSets: isHomeForfeit ? 0 : 2,
        awaySets: isHomeForfeit ? 2 : 0,
        set1Home: isHomeForfeit ? 0 : 25,
        set1Away: isHomeForfeit ? 25 : 0,
        set2Home: isHomeForfeit ? 0 : 25,
        set2Away: isHomeForfeit ? 25 : 0,
        set3Home: null,
        set3Away: null,
        isForfeit: true,
      );
    }

    final s1h = int.tryParse(_s1Home.text);
    final s1a = int.tryParse(_s1Away.text);
    final s2h = int.tryParse(_s2Home.text);
    final s2a = int.tryParse(_s2Away.text);
    final s3h = int.tryParse(_s3Home.text);
    final s3a = int.tryParse(_s3Away.text);

    if (s1h == null || s1a == null || s2h == null || s2a == null) return null;

    // Determine sets won
    int homeSets = 0;
    int awaySets = 0;
    if (s1h > s1a) {
      homeSets++;
    } else {
      awaySets++;
    }
    if (s2h > s2a) {
      homeSets++;
    } else {
      awaySets++;
    }

    // If 1:1, need set 3
    if (homeSets == 1 && awaySets == 1) {
      if (s3h == null || s3a == null) return null;
      if (s3h > s3a) {
        homeSets++;
      } else {
        awaySets++;
      }
    }

    return widget.match.copyWith(
      homeSets: homeSets,
      awaySets: awaySets,
      set1Home: s1h,
      set1Away: s1a,
      set2Home: s2h,
      set2Away: s2a,
      set3Home: s3h,
      set3Away: s3a,
      isForfeit: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final needSet3 = _needsThirdSet();

    return AlertDialog(
      title: Text(
        '${widget.homeTeamName}  vs  ${widget.awayTeamName}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Forfeit toggle
            CheckboxListTile(
              title: const Text('Неявка'),
              value: _isForfeit,
              onChanged: (v) => setState(() {
                _isForfeit = v ?? false;
                if (!_isForfeit) _forfeitTeamId = null;
              }),
            ),
            if (_isForfeit) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Хто не з\'явився: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _forfeitTeamId,
                      items: [
                        DropdownMenuItem(
                          value: widget.match.homeTeamId,
                          child: Text(widget.homeTeamName),
                        ),
                        DropdownMenuItem(
                          value: widget.match.awayTeamId,
                          child: Text(widget.awayTeamName),
                        ),
                      ],
                      onChanged: (v) => setState(() => _forfeitTeamId = v),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              // Set scores header
              Row(
                children: [
                  const SizedBox(width: 80),
                  Expanded(
                      child: Text(widget.homeTeamName,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Text(widget.awayTeamName,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                ],
              ),
              const SizedBox(height: 8),
              _buildSetRow('Партія 1', _s1Home, _s1Away),
              const SizedBox(height: 8),
              _buildSetRow('Партія 2', _s2Home, _s2Away),
              if (needSet3) ...[
                const SizedBox(height: 8),
                _buildSetRow('Партія 3', _s3Home, _s3Away),
              ],
            ],
          ],
        ),
      ),
      actions: [
        // Clear result button
        if (widget.match.isPlayed)
          TextButton(
            onPressed: () {
              final cleared = widget.match.copyWith(
                homeSets: 0,
                awaySets: 0,
                set1Home: null,
                set1Away: null,
                set2Home: null,
                set2Away: null,
                set3Home: null,
                set3Away: null,
                isForfeit: false,
              );
              Navigator.of(context).pop(cleared);
            },
            child: const Text('Очистити'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () {
            final result = _buildResult();
            if (result != null) {
              Navigator.of(context).pop(result);
            }
          },
          child: const Text('Зберегти'),
        ),
      ],
    );
  }

  bool _needsThirdSet() {
    if (_isForfeit) return false;
    final s1h = int.tryParse(_s1Home.text);
    final s1a = int.tryParse(_s1Away.text);
    final s2h = int.tryParse(_s2Home.text);
    final s2a = int.tryParse(_s2Away.text);
    if (s1h == null || s1a == null || s2h == null || s2a == null) return true;
    int homeSets = 0, awaySets = 0;
    if (s1h > s1a) homeSets++;
    else awaySets++;
    if (s2h > s2a) homeSets++;
    else awaySets++;
    return homeSets == 1 && awaySets == 1;
  }

  Widget _buildSetRow(
      String label, TextEditingController home, TextEditingController away) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: TextField(
            controller: home,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: TextField(
            controller: away,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
