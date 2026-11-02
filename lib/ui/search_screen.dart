import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/ai_service.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/search_service.dart';
import '../data/user_repo.dart';
import '../main.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'sermon_reader.dart';
import 'shell.dart';
import 'widgets.dart';

/// Onglet « Chercher » : recherche plein texte et index de la bibliothèque.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.sermonId});

  /// Ouvert depuis un sermon : l'onglet « CELLE-CI » cible ce sermon.
  final int? sermonId;

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  bool indexMode = false;
  void showIndex(bool v) => setState(() => indexMode = v);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>().s;
    final cs = Theme.of(context).colorScheme;
    final standalone = widget.sermonId != null;
    Widget roundBtn(IconData i, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: IconButton.filled(
            style: IconButton.styleFrom(
                backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHigh,
                foregroundColor: active ? cs.onPrimaryContainer : cs.onSurface,
                fixedSize: const Size(52, 52)),
            onPressed: onTap,
            icon: Icon(i),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            color: Theme.of(context).appBarTheme.backgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(children: [
              roundBtn(Icons.local_library_outlined, indexMode, () => showIndex(true)),
              roundBtn(Icons.find_in_page_outlined, !indexMode, () => showIndex(false)),
              Expanded(
                child: Text(indexMode ? s.t('index') : 'Recherche',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHigh, foregroundColor: cs.onSurface),
                onPressed: () => standalone ? Navigator.pop(context) : Shell.of(context).go(0),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          Expanded(
            child: indexMode
                ? const IndexView()
                : SearchView(sermonId: widget.sermonId),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== Recherche
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.sermonId});
  final int? sermonId;
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  SearchMode mode = SearchMode.words;
  bool thisOne = false;
  /// Portée : 'all', 'titles', 'paragraphs', 'brochures', 'bible'.
  String where = 'all';
  Timer? _debounce;
  List<SearchHit> hits = [];
  int total = 0;
  String? suggestion;
  bool approximate = false, loadingMore = false, semanticServer = false;
  String? error;

  @override
  void initState() {
    super.initState();
    thisOne = widget.sermonId != null;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _more();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int? get _targetSermon {
    if (!thisOne) return null;
    if (widget.sermonId != null) return widget.sermonId;
    final last = context.read<UserRepo>().last('sermon');
    return last == null ? null : int.tryParse(last.key);
  }

  SearchScope get _scope => SearchScope(
        titles: where == 'all' || where == 'titles' || where == 'brochures',
        sermons: where == 'all' || where == 'paragraphs',
        brochures: where == 'all' || where == 'brochures',
        bible: where == 'all' || where == 'bible',
        notes: context.read<Settings>().searchNotes,
        sermonId: _targetSermon,
      );

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _run(live: true));
  }

  Future<void> _run({bool live = false, bool remember = false}) async {
    final q = _ctrl.text;
    final svc = context.read<SearchService>();
    if (remember) svc.remember(q, mode);
    setState(() => error = null);
    if (mode == SearchMode.meaning && context.read<Settings>().hasServer && !live && !thisOne) {
      try {
        final r = await context.read<AiService>().semantic(q);
        if (!mounted) return;
        setState(() {
          hits = r;
          total = r.length;
          approximate = false;
          semanticServer = true;
          suggestion = null;
        });
        return;
      } catch (e) {
        error = '$e — recherche locale utilisée.';
      }
    }
    final page = svc.search(q, mode, scope: _scope, live: live);
    setState(() {
      hits = page.hits;
      total = page.total;
      suggestion = page.suggestion;
      approximate = page.approximate;
      semanticServer = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _more() {
    if (loadingMore || semanticServer || hits.length >= total) return;
    loadingMore = true;
    final page = context.read<SearchService>().search(_ctrl.text, mode, scope: _scope, offset: hits.length);
    setState(() {
      hits = [...hits, ...page.hits];
      loadingMore = false;
    });
  }

  void _setQuery(String q, [SearchMode? m]) {
    _ctrl.text = q;
    if (m != null) mode = m;
    _run(remember: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>().s;
    final cs = Theme.of(context).colorScheme;
    final svc = context.read<SearchService>();
    final empty = _ctrl.text.trim().isEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          for (final (v, label) in [(false, s.t('all')), (true, s.t('thisOne'))])
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => thisOne = v);
                  if (!empty) _run();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: thisOne == v ? cs.surfaceContainerHigh : null,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    border: Border(bottom: BorderSide(color: thisOne == v ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3)),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          letterSpacing: 2,
                          fontSize: 16,
                          color: thisOne == v ? cs.onSurface : cs.onSurfaceVariant)),
                ),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
          controller: _ctrl,
          onChanged: _onChanged,
          onSubmitted: (_) => _run(remember: true),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: s.t('searchHint'),
            suffixIcon: empty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => hits = []);
                    }),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(
            tooltip: s.t('history'),
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _showHistory(context, svc),
          ),
          Expanded(
            child: SegmentedButton<SearchMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: SearchMode.words, label: Text(s.t('words'))),
                ButtonSegment(value: SearchMode.exact, label: Text(s.t('exact'))),
                ButtonSegment(value: SearchMode.meaning, label: Text(s.t('meaning'))),
              ],
              selected: {mode},
              onSelectionChanged: (v) {
                setState(() => mode = v.first);
                if (!empty) _run();
              },
            ),
          ),
          IconButton(
            tooltip: 'Demander à l\'assistant',
            icon: const Icon(Icons.auto_awesome_outlined, color: Brand.gold),
            onPressed: () {
              if (widget.sermonId != null) Navigator.pop(context);
              Shell.of(context).ask(_ctrl.text.trim().isEmpty ? '' : _ctrl.text.trim());
            },
          ),
        ]),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          children: [
            for (final (k, icon, label) in const [
              ('all', Icons.select_all_rounded, 'Tout'),
              ('titles', Icons.title_rounded, 'Titres'),
              ('paragraphs', Icons.format_align_left_rounded, 'Paragraphes'),
              ('brochures', Icons.auto_stories_outlined, 'Brochures'),
              ('bible', Icons.menu_book_outlined, 'Bible'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: where == k,
                  showCheckmark: false,
                  onSelected: thisOne && k != 'paragraphs' && k != 'all'
                      ? null
                      : (_) {
                          setState(() => where = k);
                          if (!empty) _run();
                        },
                ),
              ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: empty
            ? _Help(mode: mode, onExample: _setQuery)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: hits.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (error != null) Text(error!, style: TextStyle(color: cs.error)),
                        Text(
                            total == 0
                                ? s.t('noResults')
                                : '${s.t('results', n: total)}'
                                    '${approximate ? ' · classement par pertinence (mode hors ligne)' : ''}'
                                    '${semanticServer ? ' · recherche sémantique' : ''}',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        if (suggestion != null)
                          TextButton(
                            onPressed: () => _setQuery(suggestion!),
                            child: Text('${s.t('didYouMean')} « $suggestion » ?'),
                          ),
                        if (thisOne && _targetSermon == null)
                          const Text('Ouvrez d\'abord un sermon pour chercher dans « celui-ci ».'),
                      ]),
                    );
                  }
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 10), child: HitCard(hit: hits[i - 1], expandable: true));
                },
              ),
      ),
    ]);
  }

  void _showHistory(BuildContext context, SearchService svc) {
    final items = svc.recent();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucune recherche récente.'))
            : ListView(shrinkWrap: true, children: [
                for (final it in items)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(it.query),
                    subtitle: Text(it.mode.name == 'words' ? 'Mots' : it.mode.name == 'exact' ? 'Exacte' : 'Sens'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setQuery(it.query, it.mode);
                    },
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Effacer l\'historique'),
                  onPressed: () {
                    svc.clearHistory();
                    Navigator.pop(ctx);
                  },
                ),
              ]),
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help({required this.mode, required this.onExample});
  final SearchMode mode;
  final void Function(String, [SearchMode?]) onExample;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Settings>().s;
    final cs = Theme.of(context).colorScheme;
    Widget example(String kind, String q, String desc, SearchMode m) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onExample(q, m),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  border: Border.all(color: cs.outline), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind, style: const TextStyle(color: Brand.gold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('« $q »', style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontSize: 20)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
              ]),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(mode == SearchMode.meaning ? 'Recherche par le sens' : s.t('textSearch'),
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(mode == SearchMode.meaning ? s.t('meaningSub') : s.t('textSearchSub'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16, height: 1.4)),
      const SizedBox(height: 22),
      if (mode == SearchMode.meaning)
        example('Sens', 'Le retour de Jésus-Christ', 'Les passages qui développent cette idée.', SearchMode.meaning),
      example('Titres', 'premier sceau', 'Trouve les prédications et les brochures par leur titre, leur code ou leur lieu.',
          SearchMode.words),
      example(s.t('exact'), 'le temps de la fin', s.t('exactEx'), SearchMode.exact),
      example(s.t('words'), 'colombe agneau', s.t('wordsEx'), SearchMode.words),
    ]);
  }
}

/// Carte d'un résultat (utilisée par la recherche et l'assistant).
class HitCard extends StatefulWidget {
  const HitCard({super.key, required this.hit, this.index, this.expandable = false});
  final SearchHit hit;
  final int? index;
  final bool expandable;
  @override
  State<HitCard> createState() => _HitCardState();
}

class _HitCardState extends State<HitCard> {
  bool open = false;

  void _go() {
    final h = widget.hit;
    switch (h.kind) {
      case HitKind.title:
        Navigator.push(context, MaterialPageRoute(builder: (_) => SermonReader(sermonId: h.sermonId!)));
      case HitKind.sermon:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SermonReader(sermonId: h.sermonId!, paragraph: h.number, highlightParagraph: h.number)));
      case HitKind.bible:
        final v = context.read<AppDb>().verseById(h.id)!;
        Navigator.of(context).popUntil((r) => r.isFirst);
        Shell.of(context).openBible(v.book, v.chapter, verse: v.verse);
      case HitKind.note:
        final n = context.read<UserRepo>().notes().where((n) => n.id == h.id).firstOrNull;
        if (n != null) Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditor(note: n)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hit;
    final cs = Theme.of(context).colorScheme;
    final ctx = (open && h.kind == HitKind.sermon)
        ? context.read<SearchService>().context(h.sermonId!, h.number!)
        : null;
    final lang = h.language == null || h.language == 'fr' ? '' : ' · ${h.language!.toUpperCase()}';
    if (h.kind == HitKind.title) {
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          leading: CircleAvatar(
            backgroundColor: cs.secondaryContainer,
            child: Icon(h.reference.startsWith('Brochure') ? Icons.auto_stories_outlined : Icons.title_rounded,
                color: cs.secondary),
          ),
          title: MarkedText(h.snippet,
              style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: Text([('${h.reference}$lang'), if (h.subtitle.isNotEmpty) h.subtitle].join('\n'),
              style: TextStyle(color: cs.onSurfaceVariant)),
          isThreeLine: h.subtitle.isNotEmpty,
          trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          onTap: _go,
        ),
      );
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.expandable && h.kind == HitKind.sermon ? () => setState(() => open = !open) : _go,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.index != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                      radius: 12,
                      backgroundColor: Brand.gold,
                      child: Text('${widget.index}', style: const TextStyle(fontSize: 12, color: Brand.black))),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  Text('${h.reference}$lang',
                      style: TextStyle(color: cs.tertiary, fontWeight: FontWeight.w600)),
                  if (h.subtitle.isNotEmpty) Text(h.subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
              Icon(h.kind == HitKind.bible ? Icons.menu_book_outlined : h.kind == HitKind.note ? Icons.edit_note : Icons.record_voice_over_outlined,
                  color: cs.onSurfaceVariant, size: 20),
            ]),
            const SizedBox(height: 10),
            if (ctx?.before != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(ctx!.before!,
                    style: TextStyle(fontFamily: readingFont, color: cs.onSurfaceVariant, fontSize: 15, height: 1.45)),
              ),
            MarkedText(h.snippet,
                maxLines: open ? null : 6,
                style: const TextStyle(fontFamily: readingFont, fontSize: 17, height: 1.45)),
            if (ctx?.after != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(ctx!.after!,
                    style: TextStyle(fontFamily: readingFont, color: cs.onSurfaceVariant, fontSize: 15, height: 1.45)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _go,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(h.kind == HitKind.bible
                    ? 'Lire dans la Bible'
                    : h.kind == HitKind.note
                        ? 'Ouvrir la note'
                        : h.reference.startsWith('Brochure')
                            ? 'Lire dans la brochure'
                            : 'Lire dans le sermon'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =================================================================== Index
class IndexView extends StatefulWidget {
  const IndexView({super.key});
  @override
  State<IndexView> createState() => _IndexViewState();
}

class _IndexViewState extends State<IndexView> {
  String order = 'date';
  bool ascending = true;
  String filter = '';
  String display = 'all';

  static const _orders = [
    ('date', Icons.calendar_month_outlined, 'Date'),
    ('title', Icons.sort_by_alpha_rounded, 'A-Z'),
    ('duration', Icons.hourglass_empty_rounded, 'Durée'),
    ('series', Icons.collections_bookmark_outlined, 'Séries'),
    ('location', Icons.place_outlined, 'Lieu'),
  ];

  static const _displays = {
    'all': 'TOUT',
    'audio': 'AVEC AUDIO',
    'pdf': 'AVEC PDF',
    'fr': 'FRANÇAIS',
    'ln': 'LINGALA',
    'review': 'À VÉRIFIER',
  };

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryState>();
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;
    var list = adb.sermons(order: order, filter: filter);
    list = switch (display) {
      'audio' => list.where((s) => s.audioUrl != null).toList(),
      'pdf' => list.where((s) => adb.pdfPathFor(s) != null).toList(),
      'fr' => list.where((s) => s.language == 'fr').toList(),
      'ln' => list.where((s) => s.language == 'ln').toList(),
      'review' => list.where((s) => s.needsReview).toList(),
      _ => list,
    };
    if (!ascending) list = list.reversed.toList();

    if (adb.sermonCount() == 0) {
      return EmptyState(
        icon: Icons.local_library_outlined,
        title: context.read<Settings>().s.t('emptyLibrary'),
        message: context.read<Settings>().s.t('emptyLibrarySub'),
        action: FilledButton.icon(
          onPressed: () => showImportSheet(context),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Importer des prédications'),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (final (key, icon, label) in _orders)
            Tooltip(
              message: label,
              child: Stack(clipBehavior: Clip.none, children: [
                IconButton.filled(
                  style: IconButton.styleFrom(
                    fixedSize: const Size(56, 56),
                    backgroundColor: order == key ? cs.primary : cs.surfaceContainerHighest,
                    foregroundColor: order == key ? cs.onPrimary : cs.onSurface,
                  ),
                  icon: Icon(icon),
                  onPressed: () => setState(() {
                    if (order == key) {
                      ascending = !ascending;
                    } else {
                      order = key;
                      ascending = true;
                    }
                  }),
                ),
                if (order == key)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.surface,
                      child: Icon(ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => filter = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Titre, date ou lieu…'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: display,
              items: [
                for (final e in _displays.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Center(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: 'AFFICHAGE: ', style: TextStyle(letterSpacing: 1.5, color: cs.onSurfaceVariant)),
                        TextSpan(text: e.value, style: TextStyle(letterSpacing: 1.5, color: Theme.of(context).colorScheme.tertiary)),
                      ])),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => display = v!),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${list.length} prédication(s)', style: TextStyle(color: cs.onSurfaceVariant))),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) => SermonRow(sermon: list[i]),
        ),
      ),
    ]);
  }
}

class SermonRow extends StatelessWidget {
  const SermonRow({super.key, required this.sermon});
  final Sermon sermon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = sermon;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SermonReader(sermonId: s.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(fontSize: 19)),
              const SizedBox(height: 4),
              Row(children: [
                Text(s.displayCode, style: TextStyle(color: cs.tertiary, fontSize: 18, fontWeight: FontWeight.w700)),
                if (s.language != 'fr')
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(s.language.toUpperCase(), style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                if (s.audioUrl != null)
                  Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.headphones_rounded, size: 16, color: cs.onSurfaceVariant)),
                if (s.needsReview)
                  const Padding(
                      padding: EdgeInsets.only(left: 8), child: Icon(Icons.error_outline_rounded, size: 16, color: Brand.gold)),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Durée: ${s.durationLabel}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(s.shortLocation, textAlign: TextAlign.right, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
            ),
          ]),
        ]),
      ),
    );
  }
}
