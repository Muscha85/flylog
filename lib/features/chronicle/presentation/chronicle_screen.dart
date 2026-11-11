import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/di/service_locator.dart';
import '../../chronicle/models/event_item.dart';
import '../../chronicle/models/moment_item.dart';
import '../../chronicle/presentation/event_detail_screen.dart';
import '../../chronicle/presentation/event_form_screen.dart';

/// Hlavní obrazovka a rozcestník rodinné kroniky.
///
/// * Na Galaxy Z Fold 4 v rozloženém stavu funguje jako Master panel
///   v Master-Detail rozložení.
/// * Filtrování podle kategorie (Výlet, Divadlo, Besídka, Relax, Dovolená).
/// * Seznam seřazený sestupně podle data.
class ChronicleScreen extends StatefulWidget {
  const ChronicleScreen({
    super.key,
    this.selectedEventId,
    this.onSelectEvent,
    this.isFoldExpanded = false,
  });

  /// ID vybrané události v Master-Detail režimu.
  final String? selectedEventId;

  /// Callback při výběru události v Master-Detail režimu.
  final ValueChanged<EventItem>? onSelectEvent;

  /// Zda běží na širokém (rozloženém) displeji Z Fold 4.
  final bool isFoldExpanded;

  @override
  State<ChronicleScreen> createState() => _ChronicleScreenState();
}

class _ChronicleScreenState extends State<ChronicleScreen> {
  EventCategory? _filterCategory;
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
            tooltip: 'Nová událost',
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
          final filtered = allEvents.where((e) {
            if (_filterCategory != null && e.category != _filterCategory) return false;
            if (_searchQuery.isNotEmpty) {
              final text = '${e.title} ${e.location} ${e.description} ${e.participants.join(' ')}'.toLowerCase();
              if (!text.contains(_searchQuery)) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              _buildFilterChips(context, allEvents),
              _buildSearchBar(context),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final event = filtered[index];
                          final isSelected = widget.isFoldExpanded && event.id == widget.selectedEventId;
                          return _EventCard(
                            event: event,
                            isSelected: isSelected,
                            onTap: () {
                              if (widget.isFoldExpanded && widget.onSelectEvent != null) {
                                widget.onSelectEvent!(event);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(eventId: event.id),
                                  ),
                                );
                              }
                            },
                          );
                        },
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

  Widget _buildFilterChips(BuildContext context, List<EventItem> all) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          FilterChip(
            label: Text('Vše (${all.length})'),
            selected: _filterCategory == null,
            onSelected: (_) => setState(() => _filterCategory = null),
          ),
          const SizedBox(width: 6),
          for (final cat in EventCategory.values) ...[
            Builder(builder: (context) {
              final count = all.where((e) => e.category == cat).length;
              return FilterChip(
                avatar: Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                label: Text('${cat.label} ($count)'),
                selected: _filterCategory == cat,
                onSelected: (val) => setState(() => _filterCategory = val ? cat : null),
              );
            }),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Hledat zážitek, místo, účastníky…',
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nature_people_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Žádné zážitky v kronice', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Přidejte první rodinný výlet nebo dovolenou tlačítkem níže.',
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
                  if (event.hasStory) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 13, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Příběh připraven',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

