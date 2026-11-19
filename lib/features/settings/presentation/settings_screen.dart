import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/service_locator.dart';

/// Obrazovka nastavení aplikace FlyLog.
///
/// Umožňuje:
/// - Zadat a uložit Google Gemini API klíč
/// - Zvolit model Gemini (např. gemini-2.5-flash)
/// - Přepínat mezi Offline (mock) a Gemini režimem
/// - Otestovat funkčnost API spojení
/// - Nastavit jméno rodiny pro generování příběhů
/// - Zvolit barevný motiv (systémový, světlý, tmavý)
/// - Vybrat úložiště (Lokální vs. příprava na Firestore)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _config = AppConfig.instance;

  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _familyController;

  bool _obscureApiKey = true;
  bool _isTestingApi = false;
  String? _apiTestResult;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: _config.storedGeminiApiKey);
    _modelController = TextEditingController(text: _config.geminiModel);
    _familyController = TextEditingController(text: _config.familyName);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _familyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nastavení'),
      ),
      body: ListenableBuilder(
        listenable: _config,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Rodina
              _buildSectionTitle('Rodinná kronika'),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _familyController,
                        decoration: const InputDecoration(
                          labelText: 'Příjmení / Název rodiny',
                          hintText: 'Muchovi',
                          prefixIcon: Icon(Icons.family_restroom),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) => _config.setFamilyName(val),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _config.setFamilyName(_familyController.text),
                          child: const Text('Uložit název'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // AI modul & Gemini
              _buildSectionTitle('AI průvodce a vypravěč'),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Režim generování příběhů', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<AiMode>(
                        segments: const [
                          ButtonSegment(value: AiMode.mock, label: Text('Offline Mock'), icon: Icon(Icons.cloud_off)),
                          ButtonSegment(value: AiMode.gemini, label: Text('Gemini API'), icon: Icon(Icons.auto_awesome)),
                        ],
                        selected: {_config.aiMode},
                        onSelectionChanged: (set) => _config.setAiMode(set.first),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          labelText: 'Google Gemini API Klíč',
                          hintText: 'AIzaSy...',
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                          border: const OutlineInputBorder(),
                          helperText: _config.hasGeminiKey
                              ? 'Klíč je nastaven (${_config.maskedApiKey})'
                              : 'Bez klíče funguje lokální offline generátor',
                        ),
                        onChanged: (val) => _config.setGeminiApiKey(val),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'Gemini Model',
                          hintText: 'gemini-flash-lite-latest',
                          prefixIcon: Icon(Icons.memory),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) => _config.setGeminiModel(val),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            icon: _isTestingApi
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.network_check),
                            label: const Text('Test spojení'),
                            onPressed: _isTestingApi ? null : _testAiConnection,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _config.setGeminiApiKey(_apiKeyController.text);
                              _config.setGeminiModel(_modelController.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Nastavení AI uloženo')),
                              );
                            },
                            child: const Text('Uložit AI nastavení'),
                          ),
                        ],
                      ),
                      if (_apiTestResult != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            _apiTestResult!,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: _apiTestResult!.contains('Chyba') ? Colors.red : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Vzhled
              _buildSectionTitle('Vzhled aplikace'),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<ThemeMode>(
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                        ),
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('Systém'), icon: Icon(Icons.brightness_auto, size: 16)),
                          ButtonSegment(value: ThemeMode.light, label: Text('Světlý'), icon: Icon(Icons.light_mode, size: 16)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Tmavý'), icon: Icon(Icons.dark_mode, size: 16)),
                        ],
                        selected: {_config.themeMode},
                        onSelectionChanged: (set) => _config.setThemeMode(set.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Úložiště a databáze
              _buildSectionTitle('Datové úložiště'),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    RadioListTile<StorageBackend>(
                      value: StorageBackend.local,
                      groupValue: _config.storageBackend,
                      title: const Text('Lokální zařízení (JSON + SharedPreferences)'),
                      subtitle: const Text('Rychlé in-memory úložiště s offline perzistencí'),
                      onChanged: (val) => _config.setStorageBackend(val!),
                    ),
                    RadioListTile<StorageBackend>(
                      value: StorageBackend.firestore,
                      groupValue: _config.storageBackend,
                      title: const Text('Firebase Firestore (připraveno pro budoucí migraci)'),
                      subtitle: const Text('Vyžaduje vytvořený Firebase projekt a google-services.json'),
                      onChanged: null, // Zatím neaktivní
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.shield_outlined, color: Colors.green.shade800, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Automatická ochrana dat aktivní',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Každý zápis i úprava se automaticky zrcadlí do trvalé složky Download/FlyLog na vašem zařízení. '
                                        'Data jsou v bezpečí i při odinstalaci aplikace a při reinstalaci se automaticky načtou.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade900.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Zálohování (Export)',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                                label: const Text('Uložit do Download'),
                                onPressed: _saveBackupToDownloads,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                label: const Text('Kopírovat JSON'),
                                onPressed: _copyBackupToClipboard,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.share_outlined, size: 18),
                                label: const Text('Sdílet (Disk/Email)'),
                                onPressed: _shareBackup,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Obnova dat (Import)',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.find_in_page_outlined, size: 18),
                                label: const Text('Najít zálohy v telefonu'),
                                onPressed: _scanAndRestoreBackups,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open_outlined, size: 18),
                                label: const Text('Vybrat soubor (.json)'),
                                onPressed: _importFromFilePicker,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.paste_outlined, size: 18),
                                label: const Text('Vložit text ze schránky'),
                                onPressed: _importFromClipboard,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Center(
                child: Text(
                  'FlyLog v${AppConfig.appVersion} · Pro rodinu Muchových',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Future<void> _testAiConnection() async {
    setState(() {
      _isTestingApi = true;
      _apiTestResult = null;
    });

    final currentKey = _apiKeyController.text.trim().isNotEmpty
        ? _apiKeyController.text.trim()
        : _config.geminiApiKey;
    final currentModel = _modelController.text.trim().isNotEmpty
        ? _modelController.text.trim()
        : _config.geminiModel;

    final ai = ServiceLocator.ai;
    final res = await ai.testConnection(
      modelOverride: currentModel,
      apiKeyOverride: currentKey,
    );

    if (mounted) {
      setState(() {
        _isTestingApi = false;
        _apiTestResult = res;
      });
    }
  }

  Future<void> _saveBackupToDownloads() async {
    try {
      final repo = ServiceLocator.chronicle;
      final events = await repo.getEvents();
      final path = await ServiceLocator.backup.saveBackupToDownloads(events);
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 36),
            title: const Text('Záloha bezpečně uložena'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uloženo ${events.length} událostí do trvalého souboru:'),
                const SizedBox(height: 8),
                SelectableText(
                  path,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tento soubor se NESMAŽE ani při odinstalaci aplikace. Najdete ho ve své složce Stažené položky (Download).',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Rozumím')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při ukládání: $e')));
      }
    }
  }

  Future<void> _copyBackupToClipboard() async {
    try {
      final repo = ServiceLocator.chronicle;
      final events = await repo.getEvents();
      await ServiceLocator.backup.copyBackupToClipboard(events);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kompletní JSON záloha (${events.length} událostí) byla zkopírována do schránky!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při kopírování: $e')));
      }
    }
  }

  Future<void> _shareBackup() async {
    try {
      final repo = ServiceLocator.chronicle;
      final events = await repo.getEvents();
      final path = await ServiceLocator.backup.shareBackup(events);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Záloha uložena do $path a připravena ke sdílení.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při sdílení: $e')));
      }
    }
  }

  Future<void> _scanAndRestoreBackups() async {
    try {
      final files = await ServiceLocator.backup.getAvailableBackupFiles();
      if (!mounted) return;

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ve složkách Download a Documents nebyly nalezeny žádné zálohy FlyLog.')),
        );
        return;
      }

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nalezené zálohy na zařízení'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (c, i) {
                final file = files[i];
                final name = file.path.split(Platform.pathSeparator).last;
                final date = file.lastModifiedSync();
                final sizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, color: Colors.blue),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${date.day}. ${date.month}. ${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')} · $sizeKb kB'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final res = await ServiceLocator.backup.importFromFile(file);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res.message)),
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zavřít')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při hledání: $e')));
      }
    }
  }

  Future<void> _importFromFilePicker() async {
    final res = await ServiceLocator.backup.importBackupWithPicker();
    if (mounted && res.message != 'Výběr souboru byl zrušen.') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Future<void> _importFromClipboard() async {
    final textController = TextEditingController();
    try {
      final clipData = await Clipboard.getData('text/plain');
      if (clipData?.text != null && clipData!.text!.contains('events')) {
        textController.text = clipData.text!;
      }
    } catch (_) {}

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vložit zálohu (JSON text)'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vložte kód zálohy zkopírovaný z emailu, poznámek nebo zprávy:'),
              const SizedBox(height: 10),
              TextField(
                controller: textController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '{\n  "version": 1,\n  "events": [...]\n}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Obnovit z textu')),
        ],
      ),
    );

    if (ok == true && textController.text.trim().isNotEmpty) {
      final res = await ServiceLocator.backup.importFromJsonString(textController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
      }
    }
  }
}

