import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/utils/id_generator.dart';
import '../../chronicle/models/event_item.dart';
import '../../chronicle/models/moment_item.dart';
import '../../chronicle/models/quick_note.dart';
import '../../chronicle/presentation/event_detail_screen.dart';
import '../../chronicle/presentation/event_form_screen.dart';

/// Hlavní obrazovka a rozcestník rodinné kroniky.
///
/// Obsahuje:
/// - Výraznou kartu „Rozpracované / Právě probíhá“ pro nejnovější draft
/// - Rychlé přidání časové poznámky a fotky jedním klepnutím
/// - Pokročilé filtrování (stav draft/published, kategorie, účastníci, rok)
/// - Statistickou hlavičku (záznamy, km, fotky)
class ChronicleScreen extends StatefulWidget {
  const ChronicleScreen({
    super.key,
    this.selectedEventId,
    this.onSelectEvent,
    this.isFoldExpanded = false,
  });

  final String? selectedEventId;
  final ValueChanged<EventItem>? onSelectEvent;
  final bool isFoldExpanded;

  @override
  State<ChronicleScreen> createState() => _ChronicleScreenState();
}

class _ChronicleScreenState extends State<ChronicleScreen> {
  EventStatus? _filterStatus;
  EventCategory? _filterCategory;
  String? _filterParticipant;
  int? _filterYear;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ServiceLocator.chronicle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rodinná kronika'),
        actions: [
          IconButton(
            tooltip: 'Nová událost / Deník',
            icon: const Icon(Icons.add),
            onPressed: () => _openCreateForm(context),
          ),
        ],
      ),
      body: StreamBuilder<List<EventItem>>(
        stream: repo.watchEvents(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allEvents = snapshot.data!;

          // Nejnovější aktivní draft (pokud existuje)
          final activeDraft = allEvents.where((e) => e.isDraft).firstOrNull;

          // Filtrovaný seznam
          final filtered = allEvents.where((e) {
            if (_filterStatus != null && e.status != _filterStatus) return false;
            if (_filterCategory != null && e.category != _filterCategory) return false;
            if (_filterParticipant != null && !e.participants.contains(_filterParticipant)) return false;
            if (_filterYear != null && e.startDate.year != _filterYear) return false;
            if (_searchQuery.isNotEmpty) {
              final text = '${e.title} ${e.location} ${e.description} ${e.extraNotes} ${e.participants.join(' ')}'
                  .toLowerCase();
              if (!text.contains(_searchQuery)) return false;
            }
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // 1. Aktivní rozpracovaný draft nahoře
              if (activeDraft != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: _ActiveDraftBanner(
                      draft: activeDraft,
                      onTap: () => _openDetail(context, activeDraft),
                      onAddNote: () => _showAddNoteDialog(context, activeDraft),
                      onAddPhoto: () => _addPhotoToDraft(context, activeDraft),
                    ),
                  ),
                ),

              // 2. Statistická lišta filtrů
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: _buildStatsHeader(context, filtered),
                ),
              ),

              // 3. Vyhledávací pole a filtry
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildSearchBar(context),
                    _buildFilterRow(context, allEvents),
                  ],
                ),
              ),

              // 4. Seznam událostí
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final event = filtered[index];
                        final isSelected = widget.isFoldExpanded && event.id == widget.selectedEventId;
                        return _EventCard(
                          event: event,
                          isSelected: isSelected,
                          onTap: () => _openDetail(context, event),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: widget.isFoldExpanded
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCreateForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Zapsat zážitek'),
            ),
    );
  }

  void _openDetail(BuildContext context, EventItem event) {
    if (widget.isFoldExpanded && widget.onSelectEvent != null) {
      widget.onSelectEvent!(event);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(eventId: event.id),
        ),
      );
    }
  }

  Widget _buildStatsHeader(BuildContext context, List<EventItem> list) {
    final theme = Theme.of(context);
    final totalKm = list.fold<double>(0.0, (sum, e) => sum + (e.distanceKm ?? 0.0));
    final totalPhotos = list.fold<int>(0, (sum, e) => sum + e.momentCount);
    final totalDrafts = list.where((e) => e.isDraft).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Záznamů', '${list.length}'),
          if (totalDrafts > 0) _buildStatItem('Rozpracováno', '$totalDrafts', color: Colors.orange),
          _buildStatItem('Nachozeno', '${totalKm.toStringAsFixed(1)} km'),
          _buildStatItem('Fotografií', '$totalPhotos'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Hledat v zážitcích, poznámkách, místech…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context, List<EventItem> all) {
    final allParticipants = <String>{};
    final allYears = <int>{};
    for (final e in all) {
      allParticipants.addAll(e.participants);
      allYears.add(e.startDate.year);
    }
    final sortedYears = allYears.toList()..sort((a, b) => b.compareTo(a));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Stav
          FilterChip(
            label: const Text('Vše'),
            selected: _filterStatus == null && _filterCategory == null && _filterParticipant == null && _filterYear == null,
            onSelected: (_) => setState(() {
              _filterStatus = null;
              _filterCategory = null;
              _filterParticipant = null;
              _filterYear = null;
            }),
          ),
          const SizedBox(width: 6),
          FilterChip(
            avatar: const Icon(Icons.edit_note, size: 16, color: Colors.orange),
            label: const Text('Rozpracované'),
            selected: _filterStatus == EventStatus.draft,
            onSelected: (val) => setState(() => _filterStatus = val ? EventStatus.draft : null),
          ),
          const SizedBox(width: 6),
          FilterChip(
            avatar: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
            label: const Text('Publikované'),
            selected: _filterStatus == EventStatus.published,
            onSelected: (val) => setState(() => _filterStatus = val ? EventStatus.published : null),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          // Kategorie
          for (final cat in EventCategory.values) ...[
            FilterChip(
              avatar: Text(cat.emoji, style: const TextStyle(fontSize: 14)),
              label: Text(cat.label),
              selected: _filterCategory == cat,
              onSelected: (val) => setState(() => _filterCategory = val ? cat : null),
            ),
            const SizedBox(width: 6),
          ],
          if (sortedYears.length > 1) ...[
            Container(width: 1, height: 24, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            for (final yr in sortedYears) ...[
              FilterChip(
                label: Text('$yr'),
                selected: _filterYear == yr,
                onSelected: (val) => setState(() => _filterYear = val ? yr : null),
              ),
              const SizedBox(width: 6),
            ],
          ],
          if (allParticipants.isNotEmpty) ...[
            Container(width: 1, height: 24, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            for (final p in allParticipants) ...[
              FilterChip(
                avatar: const Icon(Icons.person, size: 14),
                label: Text(p),
                selected: _filterParticipant == p,
                onSelected: (val) => setState(() => _filterParticipant = val ? p : null),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nature_people_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Žádné zážitky neodpovídají filtru', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Zkuste změnit nastavení filtrů nebo založte nový rodinný zápis.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EventFormScreen(),
      ),
    );
  }

  Future<void> _showAddNoteDialog(BuildContext context, EventItem draft) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rychlá poznámka k akci'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Co se právě děje, co jsme viděli, ochutnali...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Přidat poznámku')),
        ],
      ),
    );

    if (ok == true && controller.text.trim().isNotEmpty) {
      final note = QuickNote(
        id: IdGen.next('qn_'),
        timestamp: DateTime.now(),
        text: controller.text.trim(),
      );
      final updated = draft.copyWith(quickNotes: [...draft.quickNotes, note]);
      await ServiceLocator.chronicle.saveEvent(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poznámka uložena do draftu')),
        );
      }
    }
  }

  Future<void> _addPhotoToDraft(BuildContext context, EventItem draft) async {
    final media = ServiceLocator.media;
    final res = await media.pickAndProcessPhotos();
    if (res.moments.isNotEmpty) {
      await ServiceLocator.chronicle.addMoments(draft.id, res.moments);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Přidáno ${res.moments.length} fotek do draftu')),
        );
      }
    }
  }
}

/// Výrazný banner pro nejnovější rozpracovaný draft s rychlými akcemi
class _ActiveDraftBanner extends StatelessWidget {
  const _ActiveDraftBanner({
    required this.draft,
    required this.onTap,
    required this.onAddNote,
    required this.onAddPhoto,
  });

  final EventItem draft;
  final VoidCallback onTap;
  final VoidCallback onAddNote;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = draft.effectiveCoverMoment;

    return Card(
      elevation: 2,
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade400, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'PRÁVĚ PROBÍHÁ (DRAFT)',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    draft.dateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${draft.category.emoji} ${draft.title}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (draft.location.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '📍 ${draft.location}',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 58,
                        height: 58,
                        child: _buildCoverImage(cover),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add_comment_outlined, size: 16),
                    label: const Text('Rychlá poznámka'),
                    onPressed: onAddNote,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                    label: const Text('Přidat fotku'),
                    onPressed: onAddPhoto,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(MomentItem m) {
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
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.isSelected,
    required this.onTap,
  });

  final EventItem event;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = event.coverMoment;

    return Card(
      elevation: isSelected ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null)
              SizedBox(
                height: 130,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCoverImage(cover),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      right: 12,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: event.category.color.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(event.category.emoji, style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  event.category.label,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (event.isDraft)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade700,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Draft', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          const Spacer(),
                          if (event.momentCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_camera, size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${event.momentCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover == null) ...[
                    Row(
                      children: [
                        Text(event.category.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          event.category.label,
                          style: TextStyle(
                            color: event.category.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (event.isDraft) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Draft',
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (event.momentCount > 0)
                          Text(
                            '📸 ${event.momentCount}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    event.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(event.dateLabel, style: theme.textTheme.bodySmall),
                      if (event.location.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.place, size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            event.location,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (event.distanceKm != null || event.quickNotes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (event.distanceKm != null)
                          Text('🥾 ${event.distanceKm} km', style: theme.textTheme.bodySmall),
                        if (event.quickNotes.isNotEmpty)
                          Text('📝 ${event.quickNotes.length} poznámek', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(MomentItem m) {
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
}
