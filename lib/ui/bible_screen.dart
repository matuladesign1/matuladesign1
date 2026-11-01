import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/user_repo.dart';
import 'notes_screen.dart';
import 'shell.dart';
import 'widgets.dart';

/// Lecteur biblique : 66 livres, navigation par glissement entre chapitres.
class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});
  @override
  State<BibleScreen> createState() => BibleScreenState();
}

class BibleScreenState extends State<BibleScreen> {
  late final List<BibleBook> books;
  late final List<(int, int)> chapters; // (livre, chapitre) dans l'ordre
  late PageController _pages;
  int page = 0;
  int? flashVerse;
  final _tts = FlutterTts();
  bool speaking = false;

  @override
  void initState() {
    super.initState();
    final adb = context.read<AppDb>();
    books = adb.books();
    chapters = [for (final b in books) for (var c = 1; c <= b.chapters; c++) (b.id, c)];
    final last = context.read<UserRepo>().last('bible');
    if (last != null) {
      final parts = last.key.split(':');
      page = _indexOf(int.parse(parts[0]), int.parse(parts[1]));
    } else {
      page = _indexOf(43, 1); // Jean 1
    }
    _pages = PageController(initialPage: page);
    _tts.setLanguage('fr-FR');
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => speaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _pages.dispose();
    super.dispose();
  }

  int _indexOf(int book, int chapter) {
    final i = chapters.indexWhere((e) => e.$1 == book && e.$2 == chapter);
    return i < 0 ? 0 : i;
  }

  void open(int book, int chapter, {int? verse}) {
    final i = _indexOf(book, chapter);
    setState(() {
      flashVerse = verse;
      page = i;
    });
    if (_pages.hasClients) _pages.jumpToPage(i);
  }

  String _label(int i) => '${books[chapters[i].$1 - 1].name} ${chapters[i].$2}';

  void _onPage(int i) {
    _tts.stop();
    setState(() {
      page = i;
      speaking = false;
      flashVerse = null;
    });
    final (b, c) = chapters[i];
    context.read<UserRepo>().visit('bible', '$b:$c', _label(i));
  }

  Future<void> _speak(List<Verse> verses) async {
    if (speaking) {
      await _tts.stop();
      setState(() => speaking = false);
      return;
    }
    setState(() => speaking = true);
    await _tts.speak('${_label(page)}. ${verses.map((v) => v.text).join(' ')}');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;
    final version = settings.bibleVersion;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.history_rounded), onPressed: _showHistory),
        centerTitle: false,
        titleSpacing: 0,
        title: Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
              onTap: _pickBook,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(_label(page), style: const TextStyle(fontSize: 18))),
            ),
            Container(width: 1, height: 28, color: cs.outline),
            InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
              onTap: _pickVersion,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(version, style: const TextStyle(fontSize: 18))),
            ),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: speaking ? 'Arrêter la lecture' : 'Écouter le chapitre',
            icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
            onPressed: () {
              final (b, c) = chapters[page];
              _speak(adb.chapter(version, b, c));
            },
          ),
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => Shell.of(context).go(2)),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: chapters.length,
        onPageChanged: _onPage,
        itemBuilder: (_, i) {
          final (b, c) = chapters[i];
          return _ChapterView(
            key: ValueKey('$version-$b-$c'),
            version: version,
            book: books[b - 1],
            chapter: c,
            flashVerse: i == page ? flashVerse : null,
            onPrev: i > 0 ? () => _pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
            onNext: i < chapters.length - 1
                ? () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                : null,
          );
        },
      ),
    );
  }

  void _pickVersion() {
    final adb = context.read<AppDb>();
    final settings = context.read<Settings>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final v in adb.bibleVersions())
            RadioListTile<String>(
              value: v,
              groupValue: settings.bibleVersion,
              title: Text(v),
              subtitle: Text(adb.bibleVersionName(v)),
              onChanged: (x) {
                settings.bibleVersion = x!;
                Navigator.pop(ctx);
              },
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Bible en lingala : à ajouter dès qu\'une version autorisée est disponible '
                '(les versions lingala courantes sont protégées par le droit d\'auteur).',
                style: TextStyle(fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  void _pickBook() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        builder: (_, scroll) => _BookPicker(
          books: books,
          scroll: scroll,
          onPick: (b, c) {
            Navigator.pop(ctx);
            open(b, c);
          },
        ),
      ),
    );
  }

  void _showHistory() {
    final items = context.read<UserRepo>().history().where((h) => h.type == 'bible').take(30).toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun chapitre lu pour l\'instant.'))
            : ListView(shrinkWrap: true, children: [
                for (final h in items)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(h.label),
                    subtitle: Text(h.ts.substring(0, 16).replaceAll('T', ' ')),
                    onTap: () {
                      Navigator.pop(ctx);
                      final p = h.key.split(':');
                      open(int.parse(p[0]), int.parse(p[1]));
                    },
                  ),
              ]),
      ),
    );
  }
}

class _BookPicker extends StatefulWidget {
  const _BookPicker({required this.books, required this.scroll, required this.onPick});
  final List<BibleBook> books;
  final ScrollController scroll;
  final void Function(int book, int chapter) onPick;
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  BibleBook? selected;
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (selected != null) {
      final b = selected!;
      return Column(children: [
        ListTile(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => selected = null)),
          title: Text(b.name, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: GridView.builder(
            controller: widget.scroll,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 64, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: b.chapters,
            itemBuilder: (_, i) => Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onPick(b.id, i + 1),
                child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 17))),
              ),
            ),
          ),
        ),
      ]);
    }
    final f = filter.toLowerCase();
    final list = widget.books.where((b) => b.name.toLowerCase().contains(f) || b.abbr.toLowerCase() == f).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          autofocus: false,
          onChanged: (v) => setState(() => filter = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Livre…'),
        ),
      ),
      Expanded(
        child: ListView(controller: widget.scroll, children: [
          for (final t in ['AT', 'NT']) ...[
            if (list.any((b) => b.testament == t))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(t == 'AT' ? 'ANCIEN TESTAMENT' : 'NOUVEAU TESTAMENT',
                    style: const TextStyle(color: Brand.gold, letterSpacing: 1.5)),
              ),
            for (final b in list.where((b) => b.testament == t))
              ListTile(
                title: Text(b.name),
                trailing: Text('${b.chapters} ch.', style: TextStyle(color: cs.onSurfaceVariant)),
                onTap: () => b.chapters == 1 ? widget.onPick(b.id, 1) : setState(() => selected = b),
              ),
          ],
        ]),
      ),
    ]);
  }
}

class _ChapterView extends StatefulWidget {
  const _ChapterView({
    super.key,
    required this.version,
    required this.book,
    required this.chapter,
    this.flashVerse,
    this.onPrev,
    this.onNext,
  });
  final String version;
  final BibleBook book;
  final int chapter;
  final int? flashVerse;
  final VoidCallback? onPrev, onNext;
  @override
  State<_ChapterView> createState() => _ChapterViewState();
}

class _ChapterViewState extends State<_ChapterView> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(_ChapterView old) {
    super.didUpdateWidget(old);
    if (widget.flashVerse != null && widget.flashVerse != old.flashVerse) _scrollToFlash();
  }

  @override
  void initState() {
    super.initState();
    if (widget.flashVerse != null) _scrollToFlash();
  }

  void _scrollToFlash() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.flashVerse]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .2, duration: const Duration(milliseconds: 300));
      });

  void _verseMenu(Verse v) {
    final user = context.read<UserRepo>();
    final ref = '${widget.book.name} ${v.chapter}:${v.verse}';
    final quote = '« ${v.text} »\n— $ref (${widget.version})';
    final key = '${widget.version}:${v.key}';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ref, style: Theme.of(ctx).textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final c in UserRepo.highlightColors)
                InkWell(
                    onTap: () {
                      user.setHighlight('verse', key, c);
                      Navigator.pop(ctx);
                    },
                    child: CircleAvatar(backgroundColor: Color(c), radius: 18)),
              IconButton(
                  icon: const Icon(Icons.format_color_reset_outlined),
                  onPressed: () {
                    user.setHighlight('verse', key, null);
                    Navigator.pop(ctx);
                  }),
            ]),
          ),
          ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copier'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: quote));
                Navigator.pop(ctx);
                toast(context, 'Verset copié');
              }),
          ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager'),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(quote);
              }),
          ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Ajouter une note'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NoteEditor(refType: 'verse', refKey: key, refLabel: ref, quote: v.text)));
              }),
          ListTile(
              leading: Icon(user.isFavorite('verse', key) ? Icons.star_rounded : Icons.star_outline_rounded),
              title: Text(user.isFavorite('verse', key) ? 'Retirer des favoris' : 'Ajouter aux favoris'),
              onTap: () {
                user.toggleFavorite('verse', key, ref, excerpt: v.text);
                Navigator.pop(ctx);
              }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adb = context.read<AppDb>();
    final user = context.watch<UserRepo>();
    final cs = Theme.of(context).colorScheme;
    final verses = adb.chapter(widget.version, widget.book.id, widget.chapter);
    final prefix = '${widget.version}:${widget.book.id}:${widget.chapter}:';
    final hl = user.highlights('verse', prefix);
    final noted = user.notedKeys('verse', prefix);
    const size = 21.0;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: [
      Text('${widget.book.name} ${widget.chapter}',
          style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      for (final v in verses)
        GestureDetector(
          key: _keys.putIfAbsent(v.verse, () => GlobalKey()),
          onLongPress: () => _verseMenu(v),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: hl.containsKey('$prefix${v.verse}')
                  ? Color(hl['$prefix${v.verse}']!).withValues(alpha: .25)
                  : widget.flashVerse == v.verse
                      ? Brand.gold.withValues(alpha: .15)
                      : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: v.verse == 1
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${widget.chapter}',
                        style: const TextStyle(fontFamily: readingFont, fontSize: size * 3.2, height: 1)),
                    const SizedBox(width: 10),
                    Expanded(child: _verseText(v, size, noted, cs)),
                  ])
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${v.verse} ', style: TextStyle(fontSize: size * .65, color: cs.onSurfaceVariant)),
                      ..._verseSpans(v, size, noted, cs),
                    ]),
                    style: const TextStyle(fontFamily: readingFont, fontSize: size, height: 1.5),
                  ),
          ),
        ),
      const SizedBox(height: 16),
      Row(children: [
        if (widget.onPrev != null)
          OutlinedButton.icon(onPressed: widget.onPrev, icon: const Icon(Icons.chevron_left), label: const Text('Précédent')),
        const Spacer(),
        if (widget.onNext != null)
          FilledButton.tonalIcon(onPressed: widget.onNext, icon: const Icon(Icons.chevron_right), label: const Text('Suivant')),
      ]),
      const SizedBox(height: 12),
      Text(adb.bibleVersionName(widget.version) + (widget.version == 'LSG' ? ' — domaine public' : ''),
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }

  Widget _verseText(Verse v, double size, Set<String> noted, ColorScheme cs) => Text.rich(
      TextSpan(children: _verseSpans(v, size, noted, cs)),
      style: TextStyle(fontFamily: readingFont, fontSize: size, height: 1.5));

  List<InlineSpan> _verseSpans(Verse v, double size, Set<String> noted, ColorScheme cs) => [
        TextSpan(text: v.text),
        if (noted.contains('${widget.version}:${v.key}'))
          WidgetSpan(
              child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.sticky_note_2_outlined, size: size * .8, color: Brand.gold))),
      ];
}
