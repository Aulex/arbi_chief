import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/sport_type_provider.dart';
import '../services/tournament_service.dart';
import '../sports/athletics/athletics_results_tab.dart';
import '../sports/athletics/athletics_service.dart';

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

  // Athletics age coefficients — mutable copy for editing
  Map<int, ({double men3000, double women1500})> _coeffTable = {};
  bool _coeffTableLoaded = false;

  // Tournament conduct settings (Налаштування проведення)
  final _finalsPlacesController = TextEditingController(text: '1,2');
  final _crossGroupMatchPlacesController = TextEditingController();
  final _cyclePlacesController = TextEditingController();

  // Initial values to detect changes that require result reset
  String _initialFinalsPlaces = '1,2';
  String _initialCrossGroupMatchPlaces = '';
  String _initialCyclePlaces = '';

  final _winPointsController = TextEditingController(text: '1');
  final _drawPointsController = TextEditingController(text: '0,5');
  final _lossPointsController = TextEditingController(text: '0');
  final Map<String, bool> _tieBreakers = {
    'Особиста зустріч': true,
    'Бухгольц (повний)': false,
    'Бухгольц (усічений)': false,
    'Зоннеборн-Бергер': false,
    'Кількість перемог': false,
    'Різниця партій (між командами)': false,
    'Різниця м\'ячів (між командами)': false,
    'Різниця партій (у турнірі)': false,
    'Результат жіночої ракетки': false,
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
    _tabController = TabController(length: 2, vsync: this);
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
    // Load athletics coefficients in edit mode
    if (widget.isEditMode && widget.tournament != null && widget.tournament!.t_type == 10) {
      _loadCoeffTable(widget.tournament!.t_id!);
    } else if (widget.tournament?.t_type == 10) {
      // New athletics tournament — start with empty table
      _coeffTable = {};
      _coeffTableLoaded = true;
    }
  }

  Future<void> _loadCoeffTable(int tId) async {
    final svc = ref.read(athleticsServiceProvider);
    final custom = await svc.getCustomCoefficients(tId);
    if (!mounted) return;
    setState(() {
      _coeffTable = custom ?? {};
      _coeffTableLoaded = true;
    });
  }

  Future<void> _saveCoeffTable(int tId, AthleticsService svc) async {
    // Only save for athletics tournaments (type 10)
    if (widget.tournament?.t_type != 10 && ref.read(selectedSportTypeProvider) != 10) return;
    await svc.saveCustomCoefficients(tId, _coeffTable);
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
    final finalsPlaces = await svc.getAttrValue(tId, 12);
    final crossGroupMatchPlaces = await svc.getAttrValue(tId, 13);
    final cyclePlaces = await svc.getAttrValue(tId, 14);
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
      if (finalsPlaces != null) _finalsPlacesController.text = finalsPlaces;
      if (crossGroupMatchPlaces != null) _crossGroupMatchPlacesController.text = crossGroupMatchPlaces;
      if (cyclePlaces != null) _cyclePlacesController.text = cyclePlaces;

      _initialFinalsPlaces = _finalsPlacesController.text;
      _initialCrossGroupMatchPlaces = _crossGroupMatchPlacesController.text;
      _initialCyclePlaces = _cyclePlacesController.text;
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
    _finalsPlacesController.dispose();
    _crossGroupMatchPlacesController.dispose();
    _cyclePlacesController.dispose();
    super.dispose();
  }

  bool get _placesChanged =>
      _finalsPlacesController.text.trim() != _initialFinalsPlaces.trim() ||
      _crossGroupMatchPlacesController.text.trim() != _initialCrossGroupMatchPlaces.trim() ||
      _cyclePlacesController.text.trim() != _initialCyclePlaces.trim();

  Future<void> _saveTournament() async {
    if (tNameController.text.trim().isEmpty) return;

    // In edit mode, if place settings changed and there are game results, confirm reset
    if (widget.isEditMode && widget.tournament?.t_id != null && _placesChanged) {
      final svc = ref.read(tournamentServiceProvider);
      final hasResults = await svc.hasGameResults(widget.tournament!.t_id!);
      if (hasResults && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Скинути результати?'),
            content: const Text(
              'Ви змінили налаштування місць для етапів турніру. '
              'Всі існуючі результати ігор будуть видалені.\n\n'
              'Продовжити?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Скасувати'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Скинути і зберегти', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await svc.clearAllGameResults(widget.tournament!.t_id!);
      }
    }

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

    final athleticsSvc = ref.read(athleticsServiceProvider);
    
    final tId = await ref.read(tournamentProvider.notifier).addTournament(
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
      finalsPlaces: _finalsPlacesController.text.trim(),
      crossGroupMatchPlaces: _crossGroupMatchPlacesController.text.trim(),
      cyclePlaces: _cyclePlacesController.text.trim(),
    );

    // Save athletics coefficients
    await _saveCoeffTable(tId, athleticsSvc);

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Update initial values after successful save
    _initialFinalsPlaces = _finalsPlacesController.text;
    _initialCrossGroupMatchPlaces = _crossGroupMatchPlacesController.text;
    _initialCyclePlaces = _cyclePlacesController.text;

    if (!widget.isEditMode) {
      ref.read(tournamentNavProvider.notifier).showList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue,
            indicatorColor: Colors.blue,
            tabs: const [
              Tab(text: "Загальна інформація"),
              Tab(text: "Налаштування проведення"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGeneralInfoTab(),
                _buildTournamentConductTab(),
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

  Widget _buildTournamentConductTab() {
    return _buildTab([
      const Text(
        'Налаштування проведення',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Визначте, як місця в групах впливають на подальші етапи турніру.',
        style: TextStyle(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 24),

      // --- Tournament conduct settings (hidden for athletics) ---
      if (widget.tournament?.t_type != 10) ...[
      // --- Finals places ---
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
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Місця, що виходять у фінал з груп',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Вкажіть номери місць через кому (наприклад: 1,2). '
                'Команди/гравці з цих місць у кожній групі потраплять у фінальну частину.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _finalsPlacesController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '1,2',
                  labelText: 'Місця до фіналу',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // --- Cross-group matches ---
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
              const Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: Colors.indigo, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Місця для матчів між групами',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Вкажіть номери місць через кому (наприклад: 3,4). '
                'Команди/гравці з однакових місць у різних групах зіграють між собою для визначення підсумкових позицій.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _crossGroupMatchPlacesController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '3,4',
                  labelText: 'Місця для матчів',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // --- Cycle system places ---
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
              const Row(
                children: [
                  Icon(Icons.loop_rounded, color: Colors.teal, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Місця для колової системи',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Вкажіть номери місць через кому (наприклад: 5,6). '
                'Команди/гравці з цих місць у групах зіграють між собою коловою системою для визначення підсумкових позицій.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cyclePlacesController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '5,6',
                  labelText: 'Місця для колової',
                ),
              ),
            ],
          ),
        ),
      ),
      ], // end of conduct settings hidden for athletics

      // --- Athletics Age Coefficients ---
      if (widget.tournament?.t_type == 10) ...[
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.orange.shade200, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, color: Colors.orange.shade700, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Вікові коефіцієнти',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Коефіцієнт застосовується автоматично до кожного учасника залежно від віку. '
                  'Чоловіки: 3000 м, Жінки: 1500 м. '
                  'Заліковий час = час × коефіцієнт.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                // Action buttons row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addCoefficientAge,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Додати вік'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importCoefficients,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Імпорт'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _resetCoefficientsToDefault,
                      icon: Icon(Icons.delete_sweep, size: 18, color: Colors.red.shade400),
                      label: Text('Очистити все', style: TextStyle(color: Colors.red.shade400)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 400,
                  child: SingleChildScrollView(
                    child: _buildCoefficientTable(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _buildCoefficientTable() {
    if (!_coeffTableLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final sortedEntries = _coeffTable.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Таблиця порожня',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: DataTable(
      columnSpacing: 24,
      headingRowColor: WidgetStatePropertyAll(Colors.orange.shade50),
      dataRowMinHeight: 36,
      dataRowMaxHeight: 40,
      columns: const [
        DataColumn(label: Text('Вік', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Чол. 3000м', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
        DataColumn(label: Text('Жін. 1500м', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
        DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: sortedEntries.map((e) {
        return DataRow(
          cells: [
            DataCell(Text('${e.key}', style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(
              Text(
                e.value.men3000.toStringAsFixed(4),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: e.value.men3000 < 1.0 ? Colors.indigo : null,
                ),
              ),
              onTap: () => _editCoefficient(e.key, true),
            ),
            DataCell(
              Text(
                e.value.women1500.toStringAsFixed(4),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: e.value.women1500 < 1.0 ? Colors.pink : null,
                ),
              ),
              onTap: () => _editCoefficient(e.key, false),
            ),
            DataCell(
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                onPressed: () {
                  setState(() {
                    // Set to 1.0 (effectively removing the coefficient)
                    _coeffTable[e.key] = (men3000: 1.0, women1500: 1.0);
                  });
                },
                tooltip: 'Видалити',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
          ],
        );
      }).toList(),
      ),
    );
  }



  void _editCoefficient(int age, bool isMen) {
    final current = _coeffTable[age];
    if (current == null) return;
    final controller = TextEditingController(
      text: (isMen ? current.men3000 : current.women1500).toStringAsFixed(4),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${isMen ? "Чол. 3000м" : "Жін. 1500м"} — вік $age'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Коефіцієнт',
            hintText: '0.9856',
          ),
          onSubmitted: (_) {
            final val = double.tryParse(controller.text.replaceAll(',', '.'));
            if (val != null && val > 0 && val <= 1.0) {
              setState(() {
                if (isMen) {
                  _coeffTable[age] = (men3000: val, women1500: current.women1500);
                } else {
                  _coeffTable[age] = (men3000: current.men3000, women1500: val);
                }
              });
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null && val > 0 && val <= 1.0) {
                setState(() {
                  if (isMen) {
                    _coeffTable[age] = (men3000: val, women1500: current.women1500);
                  } else {
                    _coeffTable[age] = (men3000: current.men3000, women1500: val);
                  }
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
  }

  void _addCoefficientAge() {
    final ageController = TextEditingController();
    final menController = TextEditingController(text: '1.0000');
    final womenController = TextEditingController(text: '1.0000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Додати вік'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ageController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Вік',
                hintText: '82',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: menController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Чоловіки 3000м',
                hintText: '0.9856',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: womenController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Жінки 1500м',
                hintText: '0.9895',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          FilledButton(
            onPressed: () {
              final age = int.tryParse(ageController.text);
              final men = double.tryParse(menController.text.replaceAll(',', '.'));
              final women = double.tryParse(womenController.text.replaceAll(',', '.'));
              if (age != null && men != null && women != null && age > 0) {
                setState(() {
                  _coeffTable[age] = (men3000: men, women1500: women);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Додати'),
          ),
        ],
      ),
    );
  }

  void _importCoefficients() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setST) {
          // Parse preview
          final lines = textController.text
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          final preview = <({int age, double men, double women, bool valid})>[];
          // Detect format: 2 columns (men, women — ages auto from 18) or 3 columns (age, men, women)
          int autoAge = 18;
          for (final line in lines) {
            // Split by tab or semicolon only — NOT comma (used as decimal separator)
            var parts = line.split(RegExp(r'[\t;]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            // Fallback: if only 1 part, try splitting by any spaces
            if (parts.length == 1) {
              parts = line.split(RegExp(r'\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            }
            if (parts.length >= 3) {
              // 3+ columns: age, men, women
              final age = int.tryParse(parts[0]);
              final men = double.tryParse(parts[1].replaceAll(',', '.'));
              final women = double.tryParse(parts[2].replaceAll(',', '.'));
              preview.add((
                age: age ?? 0,
                men: men ?? 0,
                women: women ?? 0,
                valid: age != null && men != null && women != null && age > 0,
              ));
            } else if (parts.length == 2) {
              // 2 columns: men, women (auto-assign ages starting from 18)
              final men = double.tryParse(parts[0].replaceAll(',', '.'));
              final women = double.tryParse(parts[1].replaceAll(',', '.'));
              if (men != null && women != null) {
                preview.add((
                  age: autoAge,
                  men: men,
                  women: women,
                  valid: true,
                ));
                autoAge++;
              }
            }
          }
          final validCount = preview.where((p) => p.valid).length;

          return AlertDialog(
            title: const Text('Імпорт коефіцієнтів'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вставте дані з Excel. Підтримувані формати:\n'
                    '• 2 колонки: Чол.3000м  Жін.1500м (вік автоматично з 18)\n'
                    '• 3 колонки: Вік  Чол.3000м  Жін.1500м\n'
                    'Роздільник колонок: табуляція або крапка з комою.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: TextField(
                      controller: textController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: '18\t0.9856\t0.9895\n19\t0.9914\t0.9948\n34\t0.9979\t0.9845',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade400,
                        ),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      onChanged: (_) => setST(() {}),
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Знайдено $validCount з ${preview.length} записів',
                      style: TextStyle(
                        fontSize: 12,
                        color: validCount == preview.length ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
              FilledButton(
                onPressed: validCount == 0
                    ? null
                    : () {
                        setState(() {
                          for (final p in preview) {
                            if (p.valid) {
                              _coeffTable[p.age] = (men3000: p.men, women1500: p.women);
                            }
                          }
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Імпортовано $validCount коефіцієнтів')),
                        );
                      },
                child: Text('Імпортувати ($validCount)'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetCoefficientsToDefault() {
    setState(() {
      _coeffTable = {};
    });
  }

  Widget _buildTab(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
