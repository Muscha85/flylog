import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../chronicle/models/event_day.dart';
import '../../chronicle/models/event_item.dart';
import '../../chronicle/models/moment_item.dart';
import 'event_form_screen.dart';

/// Detail události rodinné kroniky.
///
/// * Zobrazuje hlavičku, metadata, AI příběh s možností přegenerování,
/// * Správu jednotlivých dnů u vícedenních akcí (Dovolená),
/// * Fotogalerii s možností hromadného nahrání / vyfocení momentek,
/// * Tlačítko pro export do samostatného HTML pro `vylety.muchovi.com`.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.embedded = false,
  });

  final String eventId;

  /// Pokud je `true`, komponenta je vložena jako pravý panel Master-Detail
  /// rozvržení (bez vlastního Scaffold/AppBaru).
  final bool embedded;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _isGeneratingAi = false;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _syncTabController(int length) {
    if (_tabController == null || _tabController!.length != length) {
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ServiceLocator.chronicle;

    return StreamBuilder<List<EventItem>>(
      stream: repo.watchEvents(),
      builder: (context, snapshot) {
        final events = snapshot.data ?? [];
        final event = events.where((e) => e.id == widget.eventId).firstOrNull;

        if (event == null) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildNotFound(context);
        }

        final content = _buildContent(context, event);

        if (widget.embedded) {
          return content;
        }

        return Scaffold(
          body: content,
        );
      },
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail události')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Událost nebyla nalezena'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Zpět'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, EventItem event) {
    final cover = event.coverMoment;

    if (event.hasDays) {
      _syncTabController(event.days.length + 1); // +1 pro přehled
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: cover != null ? 240 : 140,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            background: cover != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWidget(cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: event.category.color.withValues(alpha: 0.8),
                    child: Center(
                      child: Text(
                        event.category.emoji,
                        style: const TextStyle(fontSize: 64),
                      ),
                    ),
                  ),
          ),
          actions: [
            IconButton(
              tooltip: 'Exportovat webové HTML',
              icon: const Icon(Icons.html_outlined),
              onPressed: () => _exportHtml(context, event),
            ),
            IconButton(
              tooltip: 'Upravit událost',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openEditForm(context, event),
            ),
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'delete') _confirmDelete(context, event);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Smazat událost', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetadataCard(context, event),
                const SizedBox(height: 16),
                _buildAiStoryCard(context, event),
                const SizedBox(height: 16),
                if (event.hasDays) ...[
                  _buildDaysSection(context, event),
                  const SizedBox(height: 16),
                ],
                _buildMomentsHeader(context, event),
                const SizedBox(height: 8),
                _buildMomentsGrid(context, event, event.moments),
                const SizedBox(height: 80), // rezerva pro FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataCard(BuildContext context, EventItem event) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: event.category.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(event.category.emoji),
                      const SizedBox(width: 6),
                      Text(
                        event.category.label,
                        style: TextStyle(
                          color: event.category.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  event.dateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(height: 20),
            if (event.location.isNotEmpty) ...[
              _buildMetaRow(
                Icons.location_on_outlined,
                'Místo',
                event.location + (event.hasLocation ? ' (${event.latitude!.toStringAsFixed(4)}, ${event.longitude!.toStringAsFixed(4)})' : ''),
              ),
              const SizedBox(height: 8),
            ],
            if (event.weather != null && event.weather!.isNotEmpty) ...[
              _buildMetaRow(Icons.wb_sunny_outlined, 'Počasí', event.weather!),
              const SizedBox(height: 8),
            ],
            if (event.participants.isNotEmpty) ...[
              _buildMetaRow(Icons.group_outlined, 'Účastníci', event.participants.join(', ')),
              const SizedBox(height: 8),
            ],
            if (event.description.isNotEmpty) ...[
              _buildMetaRow(Icons.notes_outlined, 'Poznámka', event.description),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _buildAiStoryCard(BuildContext context, EventItem event) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Rodinný příběh',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                const Spacer(),
                if (_isGeneratingAi)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: event.hasStory ? 'Přegenerovat příběh' : 'Vytvořit příběh',
                    icon: Icon(event.hasStory ? Icons.refresh : Icons.play_arrow),
                    onPressed: () => _generateStory(context, event),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (event.hasStory)
              Text(
                event.aiStory!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              )
            else
              Text(
                'Zatím nebyl vygenerován žádný příběh. Stiskněte tlačítko pro spuštění AI průvodce.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaysSection(BuildContext context, EventItem event) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sortedDays = event.sortedDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Jednotlivé dny (${sortedDays.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Přidat den'),
              onPressed: () => _addDay(context, event),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final day in sortedDays) ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.secondaryContainer,
                child: Text(
                  '${day.dayNumber}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSecondaryContainer),
                ),
              ),
              title: Text(day.displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(Fmt.date(day.date)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    tooltip: 'Přidat fotky ke dni',
                    onPressed: () => _importPhotos(context, event, dayId: day.id),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (day.note.isNotEmpty) ...[
                        Text(day.note, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                      ],
                      if (day.aiStory != null && day.aiStory!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(day.aiStory!, style: const TextStyle(fontStyle: FontStyle.italic)),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (day.moments.isNotEmpty)
                        _buildMomentsGrid(context, event, day.moments)
                      else
                        const Text('Žádné fotky pro tento den.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMomentsHeader(BuildContext context, EventItem event) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Fotogalerie (${event.moments.length})',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Vyfotit',
              icon: const Icon(Icons.camera_alt_outlined),
              onPressed: () => _capturePhoto(context, event),
            ),
            IconButton(
              tooltip: 'Vybrat z galerie',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => _importPhotos(context, event),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMomentsGrid(BuildContext context, EventItem event, List<MomentItem> moments) {
    if (moments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text('Zatím žádné momentky. Přidejte fotky tlačítkem výše.'),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: moments.length,
      itemBuilder: (context, index) {
        final moment = moments[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImageWidget(moment),
              if (moment.hasLocation)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.pin_drop, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageWidget(MomentItem m) {
    if (m.isRemote) {
      return Image.network(
        m.path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
      );
    }
    return Image.file(
      File(m.path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
    );
  }

  // ---------------------------------------------------------------------------
  // Akce
  // ---------------------------------------------------------------------------

  Future<void> _generateStory(BuildContext context, EventItem event) async {
    setState(() => _isGeneratingAi = true);
    try {
      final ai = ServiceLocator.ai;
      final result = await ai.generateStory(event);
      final repo = ServiceLocator.chronicle;
      await repo.saveEvent(event.copyWith(aiStory: result.text));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Příběh vygenerován (${result.sourceLabel})')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při generování: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAi = false);
    }
  }

  Future<void> _importPhotos(BuildContext context, EventItem event, {String? dayId}) async {
    try {
      final media = ServiceLocator.media;
      final result = await media.pickAndProcessPhotos();
      if (result.moments.isNotEmpty) {
        final repo = ServiceLocator.chronicle;
        await repo.addMoments(event.id, result.moments, dayId: dayId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nahráno ${result.moments.length} fotek (ušetřeno ${result.savedKb} kB)')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba importu fotek: $e')),
        );
      }
    }
  }

  Future<void> _capturePhoto(BuildContext context, EventItem event) async {
    try {
      final media = ServiceLocator.media;
      final result = await media.capturePhoto();
      if (result.moments.isNotEmpty) {
        final repo = ServiceLocator.chronicle;
        await repo.addMoments(event.id, result.moments);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fotka uložena')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při focení: $e')),
        );
      }
    }
  }

  Future<void> _addDay(BuildContext context, EventItem event) async {
    final newDayNum = event.days.length + 1;
    final newDate = event.startDate.add(Duration(days: newDayNum - 1));
    final newDay = EventDay(
      id: IdGen.next('d_'),
      dayNumber: newDayNum,
      date: newDate,
      title: 'Den $newDayNum',
    );
    final repo = ServiceLocator.chronicle;
    await repo.saveDay(event.id, newDay);
  }

  void _exportHtml(BuildContext context, EventItem event) {
    final builder = ServiceLocator.html;
    final html = builder.build(event);
    Clipboard.setData(ClipboardData(text: html));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Responzivní HTML pro ${builder.siteDomain} zkopírováno do schránky!'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  void _openEditForm(BuildContext context, EventItem event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventFormScreen(existingEvent: event),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, EventItem event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smazat událost?'),
        content: Text('Opravdu chcete smazat „${event.title}“ a všechny její momentky?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final repo = ServiceLocator.chronicle;
      await repo.deleteEvent(event.id);
      if (context.mounted && !widget.embedded) {
        Navigator.of(context).pop();
      }
    }
  }
}

