import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/di/service_locator.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/log_entry.dart';
import 'core/responsive/fold_layout_scaffold.dart';
import 'core/theme/app_theme.dart';
import 'features/chronicle/presentation/chronicle_screen.dart';
import 'features/chronicle/presentation/event_detail_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/system_monitor/presentation/debug_console_screen.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Spuštění AppLoggeru
    AppLogger.I.info(LogModule.app, 'app_starting', metrics: {
      'timestamp': DateTime.now().toIso8601String(),
    });

    // 2. Načtení konfigurace
    await AppConfig.instance.load();
    AppLogger.I.contextProvider = () => AppConfig.instance.diagnosticContext();

    // 3. Inicializace ServiceLocatoru (výchozí mock úložiště + ukázková data)
    await ServiceLocator.init();

    runApp(const FlyLogApp());
  }, (error, stack) {
    AppLogger.I.error(LogModule.app, 'unhandled_zone_error', error: error, stackTrace: stack);
  });
}

class FlyLogApp extends StatelessWidget {
  const FlyLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.instance;

    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        return MaterialApp(
          title: 'FlyLog',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: config.themeMode,
          home: const FlyLogHomeScaffold(),
        );
      },
    );
  }
}

/// Hlavní adaptivní kostra FlyLog s podporou pro Samsung Galaxy Z Fold 4.
class FlyLogHomeScaffold extends StatefulWidget {
  const FlyLogHomeScaffold({super.key});

  @override
  State<FlyLogHomeScaffold> createState() => _FlyLogHomeScaffoldState();
}

class _FlyLogHomeScaffoldState extends State<FlyLogHomeScaffold> {
  int _navIndex = 0;
  String? _selectedEventId;

  static const List<FoldDestination> _destinations = [
    FoldDestination(
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories,
      label: 'Kronika',
    ),
    FoldDestination(
      icon: Icons.terminal_outlined,
      selectedIcon: Icons.terminal,
      label: 'Systémový log',
    ),
    FoldDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Nastavení',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isExpanded = FoldBreakpoints.isExpanded(context);

    return FoldLayoutScaffold(
      destinations: _destinations,
      selectedIndex: _navIndex,
      onDestinationSelected: (idx) {
        setState(() => _navIndex = idx);
      },
      railLeading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Text('FL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
      body: switch (_navIndex) {
        0 => _buildChronicleView(isExpanded),
        1 => const DebugConsoleScreen(),
        2 => const SettingsScreen(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildChronicleView(bool isExpanded) {
    if (!isExpanded) {
      // Vnější úzký displej Galaxy Z Fold 4 (< 600 dp)
      return const ChronicleScreen();
    }

    // Široký vnitřní displej Galaxy Z Fold 4 (>= 600 dp)
    // Master-Detail rozvržení: Vlevo seznam událostí, vpravo detail s fotkami a příběhem
    return MasterDetailLayout(
      masterWidth: 420,
      master: ChronicleScreen(
        isFoldExpanded: true,
        selectedEventId: _selectedEventId,
        onSelectEvent: (event) {
          setState(() => _selectedEventId = event.id);
        },
      ),
      detail: _selectedEventId != null
          ? EventDetailScreen(
              key: ValueKey(_selectedEventId),
              eventId: _selectedEventId!,
              embedded: true,
            )
          : null,
    );
  }
}

