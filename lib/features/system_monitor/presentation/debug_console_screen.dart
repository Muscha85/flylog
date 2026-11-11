import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/theme/app_theme.dart';

/// Obrazovka systémového logu FlyLog.
///
/// * filtrování podle modulu (chronicle, media, ai, web …) a úrovně (INFO, WARN, ERROR),
/// * vyhledávání v textu,
/// * živá aktualizace přes [ListenableBuilder],
/// * **tlačítko „Kopírovat pro AI analýzu“**, které vezme posledních 50 záznamů,
///   zabalí je do přehledného Markdown reportu a zkopíruje do schránky.
class DebugConsoleScreen extends StatefulWidget {
  const DebugConsoleScreen({super.key});

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedModule;
  LogLevel? _selectedLevel;
  String _query = '';
  bool _autoScroll = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger.I;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Systémový monitor'),
        actions: [
          IconButton(
            tooltip: 'Smazat log',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
          IconButton(
            tooltip: 'Zapsat testovací log',
            icon: const Icon(Icons.add_task),
            onPressed: () {
              logger.info(LogModule.system, 'manual_ping', metrics: {'user_triggered': true});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Testovací INFO záznam zapsán')),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: logger,
        builder: (context, _) {
          final allEntries = logger.entries;
          final filtered = allEntries.where((e) {
            if (_selectedModule != null && e.module != _selectedModule) return false;
            if (_selectedLevel != null && e.level != _selectedLevel) return false;
            if (_query.isNotEmpty) {
              final haystack = '${e.module} ${e.action} ${e.metricsText} ${e.error ?? ''}'.toLowerCase();
              if (!haystack.contains(_query)) return false;
            }
            return true;
          }).toList();

          if (_autoScroll && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
              }
            });
          }

          return Column(
            children: [
              _buildAiHeroBanner(context, filtered),
              _buildFilterBar(context, allEntries),
              _buildSearchBar(context),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          return _LogCard(entry: filtered[index]);
                        },
                      ),
              ),
              _buildStatusBar(context, allEntries.length, filtered.length),
            ],
          );
        },
      ),
    );
  }

  /// Výrazný banner s tlačítkem „Kopírovat pro AI analýzu“.
  Widget _buildAiHeroBanner(BuildContext context, List<LogEntry> currentFiltered) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Diagnostika pro AI asistenta',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                ),
                Text(
                  'Vygeneruje Markdown report posledních 50 záznamů a zkopíruje do schránky.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Kopírovat pro AI'),
            onPressed: () => _copyForAi(context, currentFiltered),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, List<LogEntry> all) {
    final scheme = Theme.of(context).colorScheme;
    final modules = {for (final e in all) e.module}.toList()..sort();
    final errorCount = all.where((e) => e.level == LogLevel.error).length;
    final warnCount = all.where((e) => e.level == LogLevel.warn).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Úrovně
          FilterChip(
            label: const Text('Vše'),
            selected: _selectedLevel == null && _selectedModule == null,
            onSelected: (_) => setState(() {
              _selectedLevel = null;
              _selectedModule = null;
            }),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: Text('ERROR ($errorCount)'),
            selected: _selectedLevel == LogLevel.error,
            selectedColor: scheme.errorContainer,
            labelStyle: TextStyle(
              color: _selectedLevel == LogLevel.error ? scheme.onErrorContainer : scheme.error,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (val) => setState(() => _selectedLevel = val ? LogLevel.error : null),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: Text('WARN ($warnCount)'),
            selected: _selectedLevel == LogLevel.warn,
            onSelected: (val) => setState(() => _selectedLevel = val ? LogLevel.warn : null),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: const Text('INFO'),
            selected: _selectedLevel == LogLevel.info,
            onSelected: (val) => setState(() => _selectedLevel = val ? LogLevel.info : null),
          ),
          const SizedBox(width: 12),
          Container(height: 24, width: 1, color: scheme.outlineVariant),
          const SizedBox(width: 12),
          // Moduly
          for (final m in modules) ...[
            FilterChip(
              label: Text(m),
              selected: _selectedModule == m,
              onSelected: (val) => setState(() => _selectedModule = val ? m : null),
            ),
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
          hintText: 'Hledat v logu (akce, chyba, modul)…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('Žádné záznamy neodpovídají filtru', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, int total, int filtered) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        children: [
          Text(
            'Zobrazeno $filtered z $total záznamů',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          InkWell(
            onTap: () => setState(() => _autoScroll = !_autoScroll),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _autoScroll ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text('Auto-scroll', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyForAi(BuildContext context, List<LogEntry> currentFiltered) async {
    final report = AppLogger.I.exportForAi(
      last: 50,
      source: currentFiltered.isNotEmpty ? currentFiltered : null,
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report pro AI (${(report.length / 1024).toStringAsFixed(1)} kB) byl zkopírován do schránky!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            textColor: Theme.of(context).colorScheme.onPrimary,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smazat systémový log?'),
        content: const Text('Paměťový buffer bude vyprázdněn. Tuto akci nelze vrátit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Smazat')),
        ],
      ),
    );
    if (ok == true) {
      AppLogger.I.clear();
    }
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final levelColor = AppTheme.logLevelColor(scheme, entry.level.label);

    return Card(
      elevation: 0,
      color: entry.level == LogLevel.error
          ? scheme.errorContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: entry.level == LogLevel.error
              ? scheme.error
              : (entry.level == LogLevel.warn ? Colors.orange : scheme.outlineVariant.withValues(alpha: 0.4)),
          width: entry.hasError ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.level.label,
                    style: TextStyle(color: levelColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.module,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  entry.shortTime,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.action,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            if (entry.metrics.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final m in entry.metrics.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        '${m.key}: ${m.value}',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ),
            ],
            if (entry.hasError) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.error!,
                            style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    if (entry.stackTrace != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.stackTrace!,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: scheme.onErrorContainer.withValues(alpha: 0.8),
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

