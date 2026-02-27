import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../services/tournament_service.dart';

class TournamentAddScreen extends ConsumerStatefulWidget {
  final Tournament? tournament;
  final bool isEditMode;

  const TournamentAddScreen({
    super.key,
    this.tournament,
    this.isEditMode = false,
  });

  @override
  ConsumerState<TournamentAddScreen> createState() =>
      _TournamentAddScreenState();
}

class _TournamentAddScreenState extends ConsumerState<TournamentAddScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // All your controllers...
  final tNameController = TextEditingController();
  final roundsController = TextEditingController(text: "1");
  String selectedTimeControl = "Рапід";
  String selectedPairingSystem = "Колова";
  String _scoringFormat = "Особистий";
  bool _allowSubstitutes = false;
  bool _isLoading = false;
  String _startingListSort = "За алфавітом";

  final _winPointsController = TextEditingController(text: '1');
  final _drawPointsController = TextEditingController(text: '0,5');
  final _lossPointsController = TextEditingController(text: '0');
  final Map<String, bool> _tieBreakers = {
    'Особиста зустріч': true,
    'Бухгольц (повний)': false,
    'Бухгольц (усічений)': false,
    'Зоннеборн-Бергер': false,
    'Кількість перемог': false,
  };

  // Controllers for the first tab
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _organizerNameController = TextEditingController();
  final _organizerSiteController = TextEditingController();
  final _organizerPhoneController = TextEditingController();
  DateTime? _startDateTime;
  DateTime? _endDateTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.isEditMode && widget.tournament != null) {
      final t = widget.tournament!;
      tNameController.text = t.t_name;
      if (t.t_date_begin.isNotEmpty && t.t_date_end.isNotEmpty) {
        _startDateTime = DateTime.parse(t.t_date_begin);
        _endDateTime = DateTime.parse(t.t_date_end);
      }
      if (t.t_id != null) {
        _loadAttrValues(t.t_id!);
      }
    }
  }

  Future<void> _loadAttrValues(int tId) async {
    final svc = ref.read(tournamentServiceProvider);
    final timeControl = await svc.getAttrDictValue(tId, 1);
    final pairingSystem = await svc.getAttrDictValue(tId, 2);
    final rounds = await svc.getAttrValue(tId, 3);
    final startingListSort = await svc.getAttrDictValue(tId, 4);
    final scoringFormat = await svc.getAttrDictValue(tId, 5);
    final substitutes = await svc.getAttrValue(tId, 6);
    final scoringPoints = await svc.getAttrDictValueMap(tId, 7);
    final tieBreakers = await svc.getAttrDictValueList(tId, 8);
    if (!mounted) return;
    setState(() {
      if (timeControl != null) selectedTimeControl = timeControl;
      if (pairingSystem != null) selectedPairingSystem = pairingSystem;
      if (rounds != null) roundsController.text = rounds;
      if (startingListSort != null) _startingListSort = startingListSort;
      if (scoringFormat != null) _scoringFormat = scoringFormat;
      if (substitutes != null) _allowSubstitutes = substitutes == '1';
      if (scoringPoints.containsKey('Перемога')) {
        _winPointsController.text = scoringPoints['Перемога']!;
      }
      if (scoringPoints.containsKey('Нічия')) {
        _drawPointsController.text = scoringPoints['Нічия']!;
      }
      if (scoringPoints.containsKey('Поразка')) {
        _lossPointsController.text = scoringPoints['Поразка']!;
      }
      for (final key in _tieBreakers.keys) {
        _tieBreakers[key] = tieBreakers.contains(key);
      }
    });
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal().toString().split(' ')[0];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d $h:$m';
  }

  @override
  void dispose() {
    _tabController.dispose();
    tNameController.dispose();
    roundsController.dispose();
    _winPointsController.dispose();
    _drawPointsController.dispose();
    _lossPointsController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _organizerNameController.dispose();
    _organizerSiteController.dispose();
    _organizerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _saveTournament() async {
    if (tNameController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    final dateBegin = _startDateTime != null
        ? '${_startDateTime!.day.toString().padLeft(2, '0')}.${_startDateTime!.month.toString().padLeft(2, '0')}.${_startDateTime!.year}'
        : '';
    final dateEnd = _endDateTime != null
        ? '${_endDateTime!.day.toString().padLeft(2, '0')}.${_endDateTime!.month.toString().padLeft(2, '0')}.${_endDateTime!.year}'
        : '';

    final selectedTieBreakers = _tieBreakers.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    await ref.read(tournamentProvider.notifier).addTournament(
      existingId: widget.isEditMode ? widget.tournament?.t_id : null,
      name: tNameController.text.trim(),
      dateBegin: dateBegin,
      dateEnd: dateEnd,
      selectedTimeControl: selectedTimeControl,
      selectedPairingSystem: selectedPairingSystem,
      rounds: roundsController.text.trim(),
      selectedStartingListSort: _startingListSort,
      selectedScoringFormat: _scoringFormat,
      allowSubstitutes: _allowSubstitutes,
      scoringPoints: {
        'Перемога': _winPointsController.text.trim(),
        'Нічия': _drawPointsController.text.trim(),
        'Поразка': _lossPointsController.text.trim(),
      },
      selectedTieBreakers: selectedTieBreakers,
    );

    setState(() => _isLoading = false);
    ref.read(tournamentNavProvider.notifier).showList();
  }

  @override
  Widget build(BuildContext context) {
    const _disabledTabs = {1, 2, 3}; // Б, В, Г
    return Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue,
            indicatorColor: Colors.blue,
            onTap: (index) {
              if (_disabledTabs.contains(index)) {
                _tabController.index = _tabController.previousIndex;
              }
            },
            tabs: [
              const Tab(text: "А: Загальна інформація"),
              Tab(child: Text("Б: Система проведення", style: TextStyle(color: Colors.grey.shade400))),
              Tab(child: Text("В: Командні налаштування", style: TextStyle(color: Colors.grey.shade400))),
              Tab(child: Text("Г: Очки та Тай-брейки", style: TextStyle(color: Colors.grey.shade400))),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGeneralInfoTab(),
                _buildConductionSystemTab(),
                _buildTeamSettingsTab(),
                _buildScoringTab(),
              ],
            ),
          ),
          // Actions bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      () => ref.read(tournamentNavProvider.notifier).showList(),
                  child: const Text("Скасувати"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveTournament,
                  child: Text(
                    widget.isEditMode ? "Зберегти зміни" : "Створити турнір",
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildGeneralInfoTab() {
    return _buildTab([
      const Text(
        'Загальна інформація',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      const Text('Назва турніру'),
      TextFormField(
        controller: tNameController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      const Text('Терміни проведення'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Початок'),
                const SizedBox(height: 8),
                TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: _startDateTime == null
                        ? 'Дата та час'
                        : _formatDateTime(_startDateTime!),
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: const OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _startDateTime ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _startDateTime != null
                            ? TimeOfDay.fromDateTime(_startDateTime!)
                            : const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (time != null) {
                        setState(() {
                          _startDateTime = DateTime(
                            date.year, date.month, date.day,
                            time.hour, time.minute,
                          );
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Закінчення'),
                const SizedBox(height: 8),
                TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: _endDateTime == null
                        ? 'Дата та час'
                        : _formatDateTime(_endDateTime!),
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: const OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _endDateTime ?? _startDateTime ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _endDateTime != null
                            ? TimeOfDay.fromDateTime(_endDateTime!)
                            : const TimeOfDay(hour: 18, minute: 0),
                      );
                      if (time != null) {
                        setState(() {
                          _endDateTime = DateTime(
                            date.year, date.month, date.day,
                            time.hour, time.minute,
                          );
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Text('Локація'),
      const SizedBox(height: 10),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Місто'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Адреса'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text('Організатор'),
      const SizedBox(height: 10),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ПІБ/Назва'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _organizerNameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Сайт'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _organizerSiteController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Телефон'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _organizerPhoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildConductionSystemTab() {
    return _buildTab([
      const Text(
        'Система проведення',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      const Text('Тип контролю часу'),
      DropdownButtonFormField<String>(
        value: selectedTimeControl,
        items:
            [
              "Рапід",
              "Бліц",
              "Класика",
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() => selectedTimeControl = val);
          }
        },
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      const SizedBox(height: 20),
      const Text('Система жеребкування'),
      RadioListTile<String>(
        title: const Text('Швейцарська'),
        value: 'Швейцарська',
        groupValue: selectedPairingSystem,
        onChanged: (value) => setState(() => selectedPairingSystem = value!),
      ),
      RadioListTile<String>(
        title: const Text('Колова'),
        value: 'Колова',
        groupValue: selectedPairingSystem,
        onChanged: (value) => setState(() => selectedPairingSystem = value!),
      ),
      RadioListTile<String>(
        title: const Text('Олімпійська (на вибування)'),
        value: 'Олімпійська (на вибування)',
        groupValue: selectedPairingSystem,
        onChanged: (value) => setState(() => selectedPairingSystem = value!),
      ),
      const SizedBox(height: 20),
      const Text('Кількість кіл'),
      TextFormField(
        controller: roundsController,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 20),
      const Text('Сортування стартового списку'),
      DropdownButtonFormField<String>(
        value: _startingListSort,
        items:
            [
              "За алфавітом",
              "За рейтингом",
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() => _startingListSort = val);
          }
        },
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
    ]);
  }

  Widget _buildTeamSettingsTab() {
    return _buildTab([
      const Text(
        'Командні налаштування',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      const Text('Формат заліку'),
      RadioListTile<String>(
        title: const Text('Особистий'),
        value: 'Особистий',
        groupValue: _scoringFormat,
        onChanged: (value) {
          setState(() {
            _scoringFormat = value!;
          });
        },
      ),
      RadioListTile<String>(
        title: const Text('Командний'),
        value: 'Командний',
        groupValue: _scoringFormat,
        onChanged: (value) {
          setState(() {
            _scoringFormat = value!;
          });
        },
      ),
      RadioListTile<String>(
        title: const Text('Особисто-командний'),
        value: 'Особисто-командний',
        groupValue: _scoringFormat,
        onChanged: (value) {
          setState(() {
            _scoringFormat = value!;
          });
        },
      ),
      const SizedBox(height: 20),
      CheckboxListTile(
        title: const Text('Запасні гравці'),
        subtitle: const Text(
          'Дозволити використання запасних гравців та ротацію між турами.',
        ),
        value: _allowSubstitutes,
        onChanged: (value) {
          setState(() {
            _allowSubstitutes = value!;
          });
        },
      ),
    ]);
  }

  Widget _buildScoringTab() {
    return _buildTab([
      const Text(
        'Нарахування очок та Тай-брейки',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      const Text('Система нарахування очок'),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Перемога'),
                TextFormField(
                  controller: _winPointsController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Нічия'),
                TextFormField(
                  controller: _drawPointsController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Поразка'),
                TextFormField(
                  controller: _lossPointsController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Text(
        'Додаткові показники (Тай-брейки)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const Text(
        'Виберіть тай-брейки. Пріоритет визначається порядком вибору (в майбутньому тут буде drag-and-drop).',
      ),
      const SizedBox(height: 10),
      ..._tieBreakers.keys.map((String key) {
        return CheckboxListTile(
          title: Text(key),
          value: _tieBreakers[key],
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (bool? value) {
            setState(() {
              _tieBreakers[key] = value!;
            });
          },
        );
      }).toList(),
    ]);
  }

  Widget _buildTab(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
