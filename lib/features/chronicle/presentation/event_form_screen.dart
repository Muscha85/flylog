import 'package:flutter/material.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../chronicle/models/event_day.dart';
import '../../chronicle/models/event_item.dart';

/// Formulář pro vytvoření nové události nebo editaci existující.
///
/// Podporuje:
/// - Stav Draft / Published
/// - Automatické načtení počasí z Open-Meteo podle GPS a data
/// - Parametry délky trasy (km), doby trvání (min) a doplňujících tipů
/// - Zpětný zápis i vícedenní rozsah
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({super.key, this.existingEvent});

  final EventItem? existingEvent;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  late TextEditingController _weatherController;
  late TextEditingController _tempController;
  late TextEditingController _windController;
  late TextEditingController _distanceController;
  late TextEditingController _durationController;
  late TextEditingController _extraNotesController;
  late TextEditingController _latController;
  late TextEditingController _lngController;

  late EventCategory _category;
  late EventStatus _status;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _isMultiDay = false;
  bool _isSaving = false;
  bool _isLoadingWeather = false;

  final List<String> _selectedParticipants = [];

  static const List<String> _suggestedParticipants = [
    'Rodina',
    'Jiří',
    'Martinka',
    'Davídek',
    'Natálka',
    'Babička',
    'Dědeček',
  ];

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _titleController = TextEditingController(text: e?.title ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _weatherController = TextEditingController(text: e?.weather ?? '');
    _tempController = TextEditingController(text: e?.weatherTempC?.toString() ?? '');
    _windController = TextEditingController(text: e?.weatherWindMs?.toString() ?? '');
    _distanceController = TextEditingController(text: e?.distanceKm?.toString() ?? '');
    _durationController = TextEditingController(text: e?.durationMinutes?.toString() ?? '');
    _extraNotesController = TextEditingController(text: e?.extraNotes ?? '');
    _latController = TextEditingController(text: e?.latitude?.toString() ?? '');
    _lngController = TextEditingController(text: e?.longitude?.toString() ?? '');

    _category = e?.category ?? EventCategory.trip;
    _status = e?.status ?? EventStatus.draft; // Nový záznam začíná vždy jako draft
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate;
    _isMultiDay = e?.isMultiDay ?? false;

    if (e != null) {
      _selectedParticipants.addAll(e.participants);
    } else {
      _selectedParticipants.addAll(['Rodina', 'Jiří', 'Martinka', 'Davídek', 'Natálka']);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _weatherController.dispose();
    _tempController.dispose();
    _windController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    _extraNotesController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Upravit událost' : 'Nový záznam'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Uložit',
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Stav záznamu (Draft vs Published)
            Card(
              elevation: 0,
              color: _status == EventStatus.draft ? Colors.orange.shade50 : Colors.green.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _status == EventStatus.draft ? Colors.orange.shade300 : Colors.green.shade300,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _status.icon,
                      color: _status == EventStatus.draft ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status == EventStatus.draft
                            ? 'Stav: Rozpracováno (Draft)'
                            : 'Stav: Dokončeno (Publikováno)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _status == EventStatus.draft ? Colors.orange.shade900 : Colors.green.shade900,
                        ),
                      ),
                    ),
                    Switch(
                      value: _status == EventStatus.published,
                      activeColor: Colors.green.shade700,
                      onChanged: (val) {
                        setState(() {
                          _status = val ? EventStatus.published : EventStatus.draft;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Kategorie
            Text('Kategorie záznamu', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in EventCategory.values)
                  ChoiceChip(
                    avatar: Text(cat.emoji),
                    label: Text(cat.label),
                    selected: _category == cat,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _category = cat;
                          if (cat == EventCategory.vacation && !_isMultiDay) {
                            _isMultiDay = true;
                            _endDate = _startDate.add(const Duration(days: 2));
                          }
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Název
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Název události / dne *',
                hintText: 'např. Výlet na Paprsek nebo Sobotní pohoda',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Zadejte prosím název události';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Termín
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Termín konání', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            const Text('Vícedenní'),
                            Switch(
                              value: _isMultiDay,
                              onChanged: (val) {
                                setState(() {
                                  _isMultiDay = val;
                                  if (val && _endDate == null) {
                                    _endDate = _startDate.add(const Duration(days: 2));
                                  } else if (!val) {
                                    _endDate = null;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(_isMultiDay ? 'Začátek akce' : 'Datum akce'),
                      subtitle: Text(Fmt.longDate(_startDate)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => _pickDate(isStart: true),
                    ),
                    if (_isMultiDay)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_repeat),
                        title: const Text('Konec akce'),
                        subtitle: Text(_endDate != null ? Fmt.longDate(_endDate!) : 'Zvolte konec'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () => _pickDate(isStart: false),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Místo a GPS souřadnice
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Místo / Cíl',
                hintText: 'např. Paprsek, Rychlebské hory',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Zeměpisná šířka (lat)',
                      hintText: '50.2156',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lngController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Zeměpisná délka (lng)',
                      hintText: '17.0153',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Počasí (Open-Meteo & editace)
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Počasí', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        FilledButton.tonalIcon(
                          icon: _isLoadingWeather
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_sync_outlined, size: 16),
                          label: const Text('Načíst z Open-Meteo'),
                          onPressed: _isLoadingWeather ? null : _fetchWeatherFromOpenMeteo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _weatherController,
                      decoration: const InputDecoration(
                        labelText: 'Souhrnný popis počasí',
                        hintText: '☀️ 22 °C, polojasno, slabý vítr',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _tempController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Teplota (°C)',
                              hintText: '22.5',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _windController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Vítr (m/s)',
                              hintText: '3.2',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Délka trasy a trvání
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distanceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Trasa (km)',
                      hintText: '8.5',
                      prefixIcon: Icon(Icons.straighten),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Doba trvání (min)',
                      hintText: '180',
                      prefixIcon: Icon(Icons.timer_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Účastníci (štítky)
            Text('Účastníci', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in _suggestedParticipants)
                  FilterChip(
                    label: Text(p),
                    selected: _selectedParticipants.contains(p),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedParticipants.add(p);
                        } else {
                          _selectedParticipants.remove(p);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Popis
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Základní popis / průběh akce',
                hintText: 'Co bylo cílem, hlavní program a zážitky...',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Doplňující poznámky a praktické tipy
            TextFormField(
              controller: _extraNotesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Praktické tipy / doporučení',
                hintText: 'Parkování, vstupné, kde se dobře najíst, kočárky...',
                prefixIcon: Icon(Icons.lightbulb_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEditing ? 'Uložit změny' : 'Založit do kroniky'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchWeatherFromOpenMeteo() async {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejprve zadejte nebo načtěte GPS souřadnice (lat a lng).')),
      );
      return;
    }

    setState(() => _isLoadingWeather = true);
    final weather = await ServiceLocator.weather.fetchWeather(
      latitude: lat,
      longitude: lng,
      date: _startDate,
    );

    if (mounted) {
      setState(() {
        _isLoadingWeather = false;
        if (weather != null) {
          _weatherController.text = weather.toSummaryString();
          _tempController.text = weather.temperatureC.toStringAsFixed(1);
          _windController.text = weather.windSpeedMs.toStringAsFixed(1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Počasí z Open-Meteo bylo úspěšně načteno!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Počasí se nepodařilo z Open-Meteo načíst.')),
          );
        }
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? _startDate.add(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1980),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked.isBefore(_startDate) ? _startDate : picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repo = ServiceLocator.chronicle;

    try {
      final now = DateTime.now();
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());
      final temp = double.tryParse(_tempController.text.trim());
      final wind = double.tryParse(_windController.text.trim());
      final dist = double.tryParse(_distanceController.text.trim());
      final dur = int.tryParse(_durationController.text.trim());

      final effectiveEndDate = _isMultiDay ? (_endDate ?? _startDate.add(const Duration(days: 1))) : null;

      List<EventDay> days = widget.existingEvent?.days ?? [];
      if (_isMultiDay && effectiveEndDate != null && days.isEmpty) {
        final totalDays = Fmt.daysInclusive(_startDate, effectiveEndDate);
        days = [
          for (int i = 0; i < totalDays; i++)
            EventDay(
              id: IdGen.next('d_'),
              dayNumber: i + 1,
              date: _startDate.add(Duration(days: i)),
              title: 'Den ${i + 1}',
            ),
        ];
      }

      final event = EventItem(
        id: widget.existingEvent?.id ?? IdGen.next('e_'),
        title: _titleController.text.trim(),
        category: _category,
        startDate: _startDate,
        endDate: effectiveEndDate,
        status: _status,
        location: _locationController.text.trim(),
        latitude: lat,
        longitude: lng,
        description: _descriptionController.text.trim(),
        weather: _weatherController.text.trim().isEmpty ? null : _weatherController.text.trim(),
        weatherTempC: temp,
        weatherWindMs: wind,
        distanceKm: dist,
        durationMinutes: dur,
        extraNotes: _extraNotesController.text.trim(),
        locationGuideText: widget.existingEvent?.locationGuideText,
        aiStory: widget.existingEvent?.aiStory,
        participants: _selectedParticipants,
        moments: widget.existingEvent?.moments ?? [],
        days: days,
        quickNotes: widget.existingEvent?.quickNotes ?? [],
        createdAt: widget.existingEvent?.createdAt ?? now,
        updatedAt: now,
      );

      await repo.saveEvent(event);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Událost upravena' : 'Záznam založen')),
        );
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      AppLogger.I.error(LogModule.chronicle, 'save_event_form_failed', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při ukládání: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
