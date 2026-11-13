import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/utils/formatters.dart';
import '../../chronicle/models/event_day.dart';
import '../../chronicle/models/event_item.dart';
import '../../chronicle/models/moment_item.dart';

/// Funkce převádějící momentku na URL obrázku ve výsledném HTML.
typedef ImageUrlResolver = String Function(MomentItem moment);

/// Generátor samostatné (single-file) responzivní HTML stránky z události.
///
/// Výstup nemá žádné externí závislosti (inline CSS, bez JS frameworků),
/// takže jej lze rovnou nahrát na statický hosting `vylety.muchovi.com`.
/// Záložky dnů u vícedenních akcí fungují čistě přes CSS (radio inputy).
class StaticHtmlBuilder {
  const StaticHtmlBuilder({this.siteDomain = AppConfig.webPublishDomain, this.imageUrlResolver});

  final String siteDomain;

  /// Vlastní překlad cest obrázků. Výchozí: vzdálené URL zůstávají,
  /// lokální soubory se odkazují relativně jako `photos/<soubor>`.
  final ImageUrlResolver? imageUrlResolver;

  /// Vytvoří kompletní HTML dokument pro [event].
  String build(EventItem event, {String? familyName}) {
    final sw = Stopwatch()..start();
    final accent = event.category.colorHex;
    final family = familyName ?? AppConfig.instance.familyName;
    final days = event.sortedDays;

    final b = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="cs">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>${_e(event.title)} · FlyLog</title>')
      ..writeln('<meta name="description" content="${_e(_metaDescription(event))}">')
      ..writeln('<meta property="og:title" content="${_e(event.title)}">')
      ..writeln('<meta property="og:description" content="${_e(_metaDescription(event))}">')
      ..writeln('<meta property="og:type" content="article">');
    final cover = event.effectiveCoverMoment;
    if (cover != null) {
      b.writeln('<meta property="og:image" content="${_e(_imageUrl(cover))}">');
    }
    b
      ..writeln('<meta name="generator" content="FlyLog ${AppConfig.appVersion}">')
      ..writeln('<style>')
      ..writeln(_css(accent, days.length))
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>');

    // Záhlaví -------------------------------------------------------------------
    b
      ..writeln('<header class="hero"${cover != null ? ' style="--cover:url(\'${_attrUrl(_imageUrl(cover))}\')"' : ''}>')
      ..writeln('<div class="hero-inner">')
      ..writeln('<span class="badge">${event.category.emoji} ${_e(event.category.label)}</span>')
      ..writeln('<h1>${_e(event.title)}</h1>')
      ..writeln('<p class="meta">')
      ..writeln('<span>📅 ${_e(event.dateLabel)}</span>');
    if (event.location.isNotEmpty) b.writeln('<span>📍 ${_e(event.location)}</span>');
    if (event.isMultiDay) {
      b.writeln('<span>🗓️ ${_e(Fmt.plural(event.durationDays, 'den', 'dny', 'dní'))}</span>');
    }
    b
      ..writeln('</p>')
      ..writeln('</div>')
      ..writeln('</header>')
      ..writeln('<main class="container">');

    // Info karty ------------------------------------------------------------------
    b.writeln('<section class="cards">');
    if (event.weather != null && event.weather!.isNotEmpty) {
      b.writeln('<div class="card info"><h3>Počasí</h3><p class="weather">${_e(event.weather!)}</p></div>');
    }
    if (event.participants.isNotEmpty) {
      b.writeln('<div class="card info"><h3>Účastníci</h3><p>${_e(event.participants.join(', '))}</p></div>');
    }
    b.writeln('<div class="card info"><h3>Momentky</h3><p>${_e(Fmt.plural(event.momentCount, 'fotka', 'fotky', 'fotek'))}</p></div>');
    if (event.hasLocation) {
      final lat = event.latitude!.toStringAsFixed(5);
      final lng = event.longitude!.toStringAsFixed(5);
      b.writeln('<div class="card info"><h3>Mapa</h3><p><a href="https://mapy.cz/zakladni?q=$lat%2C$lng" '
          'target="_blank" rel="noopener">$lat, $lng ↗</a></p></div>');
    }
    b.writeln('</section>');

    if (event.description.isNotEmpty) {
      b.writeln('<section class="card"><h2>O akci</h2>${_paragraphs(event.description)}</section>');
    }

    // AI příběh ----------------------------------------------------------------------
    if (event.hasStory) {
      b.writeln('<section class="card story"><h2>✨ Příběh</h2>${_paragraphs(event.aiStory!)}</section>');
    }

    // Galerie celé akce ------------------------------------------------------------------
    if (event.moments.isNotEmpty) {
      b
        ..writeln('<section>')
        ..writeln('<h2 class="section-title">Fotogalerie</h2>')
        ..writeln(_gallery(event.moments))
        ..writeln('</section>');
    }

    // Záložky dnů ------------------------------------------------------------------------
    if (days.isNotEmpty) {
      b
        ..writeln('<section class="days">')
        ..writeln('<h2 class="section-title">Den po dni</h2>');
      for (var i = 0; i < days.length; i++) {
        b.writeln('<input type="radio" name="day" id="day-${i + 1}" class="tab-input"${i == 0 ? ' checked' : ''}>');
      }
      b.writeln('<nav class="tabs" aria-label="Dny akce">');
      for (var i = 0; i < days.length; i++) {
        b.writeln('<label for="day-${i + 1}" class="tab">Den ${days[i].dayNumber}'
            '<small>${_e(Fmt.dayMonth(days[i].date))}</small></label>');
      }
      b
        ..writeln('</nav>')
        ..writeln('<div class="panels">');
      for (var i = 0; i < days.length; i++) {
        b.writeln(_dayPanel(days[i], i + 1));
      }
      b
        ..writeln('</div>')
        ..writeln('</section>');
    }

    b
      ..writeln('</main>')
      ..writeln('<footer>')
      ..writeln('<p>Rodinná kronika ${_e(family)} · <a href="https://$siteDomain/">$siteDomain</a></p>')
      ..writeln('<p class="small">Vytvořeno aplikací FlyLog · ${_e(Fmt.dateTime(DateTime.now()))}</p>')
      ..writeln('</footer>')
      ..writeln('</body>')
      ..writeln('</html>');

    final html = b.toString();
    AppLogger.I.info(LogModule.web, 'html_built', metrics: {
      'event_id': event.id,
      'days': days.length,
      'images': event.momentCount,
      'html_kb': (html.length / 1024).toStringAsFixed(1),
      'duration_ms': sw.elapsedMilliseconds,
    });
    return html;
  }

  /// Doporučený název souboru / slug pro publikaci, např. `2025-05-12-vylet-na-paprsek.html`.
  String suggestedFileName(EventItem event) {
    final d = event.startDate;
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '$date-${slugify(event.title)}.html';
  }

  /// Veřejná URL po budoucím exportu.
  String publicUrl(EventItem event) => 'https://$siteDomain/${suggestedFileName(event)}';

  /// Převod textu na URL slug bez diakritiky.
  static String slugify(String input) {
    const from = 'áäčďéěëíňóöřšťúůüýžÁÄČĎÉĚËÍŇÓÖŘŠŤÚŮÜÝŽ';
    const to = 'aacdeeeinoorstuuuyzAACDEEEINOORSTUUUYZ';
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch);
    }
    final slug = sb
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'akce' : slug;
  }

  // ---------------------------------------------------------------------------

  String _dayPanel(EventDay day, int index) {
    final b = StringBuffer()
      ..writeln('<article class="panel" id="panel-$index">')
      ..writeln('<header class="panel-head">')
      ..writeln('<h3>${_e(day.displayTitle)}</h3>')
      ..writeln('<p class="meta-dark">${_e(Fmt.longDate(day.date))}'
          '${day.weather != null && day.weather!.isNotEmpty ? ' · ${_e(day.weather!)}' : ''}</p>')
      ..writeln('</header>');
    if (day.note.isNotEmpty) b.writeln(_paragraphs(day.note));
    if (day.hasStory) b.writeln('<div class="story inner">${_paragraphs(day.aiStory!)}</div>');
    if (day.moments.isNotEmpty) {
      b.writeln(_gallery(day.moments));
    } else {
      b.writeln('<p class="empty">Pro tento den zatím nejsou žádné fotky.</p>');
    }
    b.writeln('</article>');
    return b.toString();
  }

  String _gallery(List<MomentItem> moments) {
    final b = StringBuffer()..writeln('<div class="gallery">');
    for (final m in moments) {
      final caption = [
        Fmt.time(m.takenAt),
        if (m.note.isNotEmpty) m.note,
      ].join(' · ');
      b
        ..writeln('<figure>')
        ..writeln('<a href="${_e(_imageUrl(m))}" target="_blank" rel="noopener">'
            '<img src="${_e(_imageUrl(m))}" alt="${_e(m.note.isEmpty ? 'Momentka' : m.note)}" loading="lazy"'
            '${m.width != null && m.height != null ? ' width="${m.width}" height="${m.height}"' : ''}></a>')
        ..writeln('<figcaption>${_e(caption)}</figcaption>')
        ..writeln('</figure>');
    }
    b.writeln('</div>');
    return b.toString();
  }

  String _imageUrl(MomentItem m) {
    final resolver = imageUrlResolver;
    if (resolver != null) return resolver(m);
    return m.isRemote ? m.path : 'photos/${m.fileName}';
  }

  String _metaDescription(EventItem e) {
    final base = e.description.isNotEmpty ? e.description : (e.aiStory ?? '${e.category.label} · ${e.dateLabel}');
    return base.length > 155 ? '${base.substring(0, 155)}…' : base;
  }

  static String _paragraphs(String text) {
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => '<p>${_e(p).replaceAll('\n', '<br>')}</p>')
        .join();
  }

  /// HTML escaping.
  static String _e(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// Bezpečná URL uvnitř CSS `url('...')` v atributu style.
  static String _attrUrl(String url) =>
      url.replaceAll("'", '%27').replaceAll('"', '%22').replaceAll('(', '%28').replaceAll(')', '%29');

  String _css(String accent, int dayCount) {
    final tabRules = StringBuffer();
    for (var i = 1; i <= dayCount; i++) {
      tabRules
        ..writeln('#day-$i:checked ~ .panels #panel-$i{display:block}')
        ..writeln('#day-$i:checked ~ .tabs label[for="day-$i"]{background:var(--accent);color:#fff;border-color:var(--accent)}');
    }
    return '''
:root{--accent:$accent;--bg:#f6f7f9;--card:#fff;--text:#1d232b;--muted:#5f6b7a;--radius:18px;--shadow:0 6px 24px rgba(20,30,50,.08)}
@media (prefers-color-scheme:dark){:root{--bg:#11151a;--card:#1b2128;--text:#e8edf2;--muted:#9aa7b4;--shadow:0 6px 24px rgba(0,0,0,.35)}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.6}
a{color:var(--accent)}
.hero{position:relative;min-height:340px;display:flex;align-items:flex-end;color:#fff;background:linear-gradient(135deg,var(--accent),#263238);background-size:cover;background-position:center}
.hero[style]{background-image:linear-gradient(180deg,rgba(0,0,0,.05) 0%,rgba(0,0,0,.65) 100%),var(--cover)}
.hero-inner{width:100%;max-width:1100px;margin:0 auto;padding:48px 20px 32px}
.hero h1{margin:.3em 0 .2em;font-size:clamp(1.9rem,5vw,3.2rem);line-height:1.15;text-shadow:0 2px 12px rgba(0,0,0,.35)}
.badge{display:inline-block;padding:6px 14px;border-radius:999px;background:rgba(255,255,255,.2);backdrop-filter:blur(6px);font-weight:600;font-size:.9rem}
.meta{display:flex;flex-wrap:wrap;gap:8px 20px;margin:0;font-weight:500;opacity:.95}
.meta-dark{margin:0;color:var(--muted);font-size:.95rem}
.container{max-width:1100px;margin:0 auto;padding:24px 20px 48px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin:-56px 0 24px;position:relative}
.card{background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);padding:20px 24px;margin-bottom:24px}
.card.info{margin-bottom:0}
.card h2{margin-top:0}
.card h3{margin:0 0 4px;font-size:.8rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.card.info p{margin:0;font-weight:600}
.weather{font-size:1.15rem}
.story{border-left:6px solid var(--accent)}
.story p:first-of-type::first-letter{font-size:2.6em;float:left;line-height:.9;padding:4px 8px 0 0;color:var(--accent);font-weight:700}
.story.inner{background:rgba(127,127,127,.08);border-radius:12px;padding:12px 18px;margin:12px 0}
.section-title{margin:32px 0 16px}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px}
.gallery figure{margin:0;background:var(--card);border-radius:14px;overflow:hidden;box-shadow:var(--shadow)}
.gallery img{display:block;width:100%;height:220px;object-fit:cover;transition:transform .3s}
.gallery a:hover img{transform:scale(1.04)}
.gallery figcaption{padding:10px 14px;font-size:.9rem;color:var(--muted)}
.tab-input{position:absolute;opacity:0;pointer-events:none}
.tabs{display:flex;gap:8px;overflow-x:auto;padding:4px 2px 12px;scrollbar-width:thin}
.tab{flex:0 0 auto;cursor:pointer;padding:10px 16px;border-radius:14px;border:1px solid rgba(127,127,127,.3);background:var(--card);font-weight:600;text-align:center;line-height:1.2;user-select:none}
.tab small{display:block;font-weight:400;font-size:.75rem;opacity:.8}
.panel{display:none;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);padding:20px 24px}
.panel-head h3{margin:0}
.empty{color:var(--muted);font-style:italic}
${tabRules.toString()}
footer{text-align:center;padding:32px 20px 48px;color:var(--muted)}
footer .small{font-size:.8rem}
@media (max-width:600px){.hero{min-height:280px}.cards{margin-top:-40px}.gallery{grid-template-columns:repeat(auto-fill,minmax(150px,1fr))}.gallery img{height:150px}.card,.panel{padding:16px 18px}}
@media print{.hero{min-height:auto;color:#000;background:none}.tabs{display:none}.panel{display:block!important;box-shadow:none}}
''';
  }
}

