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
/// - Zpětný zápis do minulosti (výběr libovolného data)
/// - Vícedenní rozsah (od - do) pro dovolené
/// - Automatické předgenerování EventDay struktur pro vícedenní akce
/// - Nastavení kategorie, místa, souřadnic, počasí, účastníků a popisu
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
  late TextEditingController _participantsController;
  late TextEditingController _latController;
  late TextEditingController _lngController;

  late EventCategory _category;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _isMultiDay = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _titleController = TextEditingController(text: e?.title ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _weatherController = TextEditingController(text: e?.weather ?? '');
    _participantsController = TextEditingController(text: e?.participants.join(', ') ?? 'Táta, Máma, Ema, Vojta');
    _latController = TextEditingController(text: e?.latitude?.toString() ?? '');
    _lngController = TextEditingController(text: e?.longitude?.toString() ?? '');

    _category = e?.category ?? EventCategory.trip;
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate;
    _isMultiDay = e?.isMultiDay ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _weatherController.dispose();
    _participantsController.dispose();
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
        title: Text(_isEditing ? 'Upravit událost' : 'Nový rodinný zážitek'),
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
            // Kategorie
            Text('Kategorie zážitku', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                labelText: 'Název události *',
                hintText: 'např. Výlet na Paprsek',
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

            // Datum a čas
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
                            const Text('Vícedenní akce'),
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
                    const SizedBox(height: 8),
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

            // Místo a GPS
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Místo / Cíl',
                hintText: 'např. Paprsek, Rychlebské hory',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
                const SizedBox(width: 12),
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

            // Počasí a účastníci
            TextFormField(
              controller: _weatherController,
              decoration: const InputDecoration(
                labelText: 'Počasí',
                hintText: '☀️ 22 °C, polojasno',
                prefixIcon: Icon(Icons.wb_sunny_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _participantsController,
              decoration: const InputDecoration(
                labelText: 'Účastníci (oddělené čárkou)',
                hintText: 'Táta, Máma, Ema, Vojta',
                prefixIcon: Icon(Icons.people_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Popis
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Poznámky, průběh, zážitky',
                hintText: 'Jaký byl výlet, co jsme zažili, co chutnalo...',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEditing ? 'Uložit změny' : 'Zapsat do kroniky'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
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
      final participants = _participantsController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());

      final effectiveEndDate = _isMultiDay ? (_endDate ?? _startDate.add(const Duration(days: 1))) : null;

      List<EventDay> days = widget.existingEvent?.days ?? [];
      // Pokud je vícedenní a nemá ještě dny, vygenerujeme prázdné struktury dnů
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
        location: _locationController.text.trim(),
        latitude: lat,
        longitude: lng,
        description: _descriptionController.text.trim(),
        weather: _weatherController.text.trim().isEmpty ? null : _weatherController.text.trim(),
        participants: participants,
        aiStory: widget.existingEvent?.aiStory,
        moments: widget.existingEvent?.moments ?? [],
        days: days,
        createdAt: widget.existingEvent?.createdAt ?? now,
        updatedAt: now,
      );

      await repo.saveEvent(event);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Událost upravena' : 'Událost zapsána do kroniky')),
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

