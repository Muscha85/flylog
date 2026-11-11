import 'package:flutter/material.dart';

/// Breakpointy pro Samsung Galaxy Z Fold 4.
///
/// * vnější (složený) displej: ~ 374 × 842 dp → **compact**
/// * vnitřní (rozložený) displej: ~ 673 × 841 dp (na šířku ~ 841 dp) → **expanded**
abstract final class FoldBreakpoints {
  /// Hranice mezi úzkým vnějším displejem a širokým vnitřním tabletem.
  static const double expanded = 600;

  /// Od této šířky se navigační lišta zobrazuje rozšířená (s popisky vedle ikon).
  static const double large = 1000;

  static bool isExpanded(BuildContext context) => MediaQuery.of(context).size.width >= expanded;

  static bool isLarge(BuildContext context) => MediaQuery.of(context).size.width >= large;
}

/// Jedna položka hlavní navigace.
class FoldDestination {
  const FoldDestination({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Adaptivní kostra aplikace pro Galaxy Z Fold 4.
///
/// * šířka < 600 dp (vnější displej): obsah na celou obrazovku + spodní [NavigationBar],
/// * šířka ≥ 600 dp (vnitřní tablet): postranní [NavigationRail] + obsah,
///   který si sám řeší Master-Detail rozložení přes [MasterDetailLayout].
class FoldLayoutScaffold extends StatelessWidget {
  const FoldLayoutScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.railLeading,
    this.floatingActionButton,
  });

  final List<FoldDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  /// Volitelný widget nad položkami railu (logo, FAB …).
  final Widget? railLeading;

  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isExpanded = width >= FoldBreakpoints.expanded;
    final scheme = Theme.of(context).colorScheme;

    if (!isExpanded) {
      // Složený Z Fold 4 – vnější úzký displej.
      return Scaffold(
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }

    // Rozložený Z Fold 4 – vnitřní tabletový displej.
    final extended = width >= FoldBreakpoints.large;
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        right: false,
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              extended: extended,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: railLeading,
              groupAlignment: -0.85,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Master-Detail rozložení pro vnitřní displej Z Fold 4.
///
/// Na úzkém displeji se zobrazí jen [master] (detail se otevírá navigací),
/// na širokém displeji je vlevo seznam a vpravo detail (nebo [emptyDetail]).
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.emptyDetail,
    this.masterWidth = 380,
    this.masterFlex,
  });

  final Widget master;

  /// Aktuální detail, nebo `null`, pokud není nic vybráno.
  final Widget? detail;

  final Widget? emptyDetail;

  /// Pevná šířka seznamu na širokém displeji.
  final double masterWidth;

  /// Pokud je nastaveno, šířka seznamu se počítá poměrem (flex) místo pevné šířky.
  final int? masterFlex;

  @override
  Widget build(BuildContext context) {
    final isExpanded = MediaQuery.of(context).size.width >= FoldBreakpoints.expanded;
    if (!isExpanded) return master;

    final scheme = Theme.of(context).colorScheme;
    final detailWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: detail ?? emptyDetail ?? const _EmptyDetail(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Na Z Fold 4 na výšku (~673 dp) dáme seznamu cca 45 %, na šířku pevných 380 dp.
        final listWidth = masterFlex != null
            ? null
            : (constraints.maxWidth * 0.45).clamp(300.0, masterWidth).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (listWidth != null) SizedBox(width: listWidth, child: master) else Expanded(flex: masterFlex!, child: master),
            VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(flex: masterFlex == null ? 1 : 10 - masterFlex!.clamp(1, 9), child: detailWidget),
          ],
        );
      },
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Vyberte událost ze seznamu', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Detail s fotkami a rodinným příběhem se zobrazí tady.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

