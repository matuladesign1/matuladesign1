import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/ai_service.dart';
import '../data/audio_controller.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/user_repo.dart';
import '../main.dart';
import 'audio_bar.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'widgets.dart';

/// Lecteur d'une prédication : texte intégral, paragraphes numérotés.
class SermonReader extends StatefulWidget {
  const SermonReader({super.key, required this.sermonId, this.paragraph, this.highlightParagraph});
  final int sermonId;
  final int? paragraph;
  final int? highlightParagraph;

  @override
  State<SermonReader> createState() => _SermonReaderState();
}

class _SermonReaderState extends State<SermonReader> {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late Sermon sermon;
  late List<Paragraph> paras;
  Sermon? other; // version dans l'autre langue
  List<Paragraph> otherParas = [];
  bool parallel = false;
  double fontSize = 20;
  int? flash;
  double? translating;
  late final UserRepo _user;

  @override
  void initState() {
    super.initState();
    _user = context.read<UserRepo>();
    flash = widget.highlightParagraph;
    _load(widget.sermonId);
    if (widget.paragraph != null && widget.paragraph! > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(widget.paragraph!));
    }
  }

  void _load(int id) {
    final adb = context.read<AppDb>();
    sermon = adb.sermon(id)!;
    paras = adb.paragraphs(id);
    final otherLang = sermon.language == 'ln' ? 'fr' : 'ln';
    other = adb.sermonVersion(sermon.code, otherLang);
    otherParas = other == null ? [] : adb.paragraphs(other!.id);
    _user.visit('sermon', '${sermon.id}', '${sermon.code} · ${sermon.title}');
  }

  void _jumpTo(int number) {
    final i = paras.indexWhere((p) => p.number >= number);
    if (i >= 0 && _items.isAttached) _items.jumpTo(index: i + 1, alignment: .1);
  }

  @override
  void deactivate() {
    final pos = _positions.itemPositions.value;
    if (pos.isNotEmpty) {
      final first = pos.where((p) => p.itemTrailingEdge > 0).fold<int>(1 << 30, (a, p) => p.index < a ? p.index : a);
      if (first >= 1 && first - 1 < paras.length) {
        _user.visit('sermon', '${sermon.id}', '${sermon.code} · ${sermon.title}',
            position: paras[first - 1].number);
      }
    }
    super.deactivate();
  }

  Future<void> _translate() async {
    final ai = context.read<AiService>();
    if (other != null) {
      setState(() => parallel = !parallel);
      return;
    }
    if (!context.read<Settings>().hasServer) {
      toast(context, 'Configurez le serveur IA (Paramètres > Assistant IA) pour traduire en lingala.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Traduire en lingala avec l\'IA'),
        content: Text(
            'Les ${paras.length} paragraphes seront traduits fidèlement, numéros et références bibliques conservés. '
            'La traduction sera clairement marquée « automatique, non validée » jusqu\'à sa validation par un traducteur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Traduire')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => translating = 0);
    try {
      await ai.translateSermonToLingala(sermon,
          onProgress: (d, t) {
        if (mounted) setState(() => translating = d / t);
      });
      if (!mounted) return;
      _load(sermon.id);
      setState(() {
        translating = null;
        parallel = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => translating = null);
      toast(context, '$e');
    }
  }

  void _paragraphMenu(Paragraph p) {
    final user = context.read<UserRepo>();
    final key = '${sermon.id}:${p.number}';
    final label = '${sermon.title} — ${sermon.code} ¶${p.number}';
    final quote = '« ${p.text} »\n— $label${sermon.shortLocation.isEmpty ? '' : ', ${sermon.shortLocation}'}';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final c in UserRepo.highlightColors)
                InkWell(
                  onTap: () {
                    user.setHighlight('para', key, c);
                    Navigator.pop(ctx);
                  },
                  child: CircleAvatar(backgroundColor: Color(c), radius: 18),
                ),
              IconButton(
                tooltip: 'Retirer le surlignage',
                icon: const Icon(Icons.format_color_reset_outlined),
                onPressed: () {
                  user.setHighlight('para', key, null);
                  Navigator.pop(ctx);
                },
              ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copier'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: quote));
              Navigator.pop(ctx);
              toast(context, 'Passage copié');
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Partager'),
            onTap: () {
              Navigator.pop(ctx);
              Share.share(quote);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: const Text('Ajouter une note'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NoteEditor(refType: 'para', refKey: key, refLabel: label, quote: p.text)));
            },
          ),
          ListTile(
            leading: Icon(user.isFavorite('para', key) ? Icons.star_rounded : Icons.star_outline_rounded),
            title: Text(user.isFavorite('para', key) ? 'Retirer des favoris' : 'Ajouter aux favoris'),
            onTap: () {
              user.toggleFavorite('para', key, label, excerpt: p.text);
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRepo>();
    context.watch<LibraryState>();
    final cs = Theme.of(context).colorScheme;
    final adb = context.read<AppDb>();
    final highlights = user.highlights('para', '${sermon.id}:');
    final noted = user.notedKeys('para', '${sermon.id}:');
    final fav = user.isFavorite('sermon', '${sermon.id}');
    final pdf = adb.pdfPathFor(sermon);
    final otherByNumber = {for (final p in otherParas) p.number: p};

    Widget action(IconData icon, String tip, VoidCallback? onTap, {String? badge, Color? color}) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: onTap == null ? cs.outline : (color ?? cs.onSurface)),
                if (badge != null) Padding(padding: const EdgeInsets.only(left: 6), child: Text(badge, style: const TextStyle(fontSize: 18))),
              ]),
            ),
          ),
        );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Column(children: [
        Text(sermon.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: readingFont, fontSize: 30, fontWeight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 10),
        Text(sermon.displayCode, style: TextStyle(fontSize: 22, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (sermon.location != null) Text(sermon.shortLocation, style: TextStyle(fontSize: 17, color: cs.onSurfaceVariant)),
        if (sermon.dateLabel.isNotEmpty) Text(sermon.dateLabel, style: TextStyle(color: cs.onSurfaceVariant)),
        if (sermon.isAiTranslation || (parallel && (other?.isAiTranslation ?? false)))
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(10)),
            child: Text(context.read<Settings>().s.t('aiTranslation'),
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSecondaryContainer)),
          ),
        if (sermon.needsReview)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Document à vérifier : ${sermon.reviewNotes ?? ''}',
                textAlign: TextAlign.center, style: const TextStyle(color: Brand.gold, fontSize: 13)),
          ),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
          action(Icons.translate_rounded, other != null ? 'Français | Lingala' : 'Traduire en lingala avec l\'IA', _translate,
              color: parallel ? Theme.of(context).colorScheme.primary : null),
          action(Icons.vertical_split_outlined, 'Lecture parallèle',
              other == null ? null : () => setState(() => parallel = !parallel),
              color: parallel ? Theme.of(context).colorScheme.primary : null),
          action(Icons.picture_as_pdf_outlined, 'Ouvrir le PDF', pdf == null ? null : () => OpenFilex.open(pdf)),
          action(Icons.edit_note_rounded, 'Notes',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotesScreen(sermon: sermon))),
              badge: '${noted.length + user.notes(refType: 'sermon', refKey: '${sermon.id}').length}'),
          action(fav ? Icons.star_rounded : Icons.star_outline_rounded, 'Favori',
              () => user.toggleFavorite('sermon', '${sermon.id}', '${sermon.code} · ${sermon.title}'),
              color: fav ? Brand.gold : null),
          action(Icons.share_outlined, 'Partager',
              () => Share.share('${sermon.title} — ${sermon.code}, ${sermon.shortLocation} (${sermon.dateLabel})')),
        ]),
        if (translating != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(children: [
              LinearProgressIndicator(value: translating),
              const SizedBox(height: 4),
              Text('Traduction en cours… ${(translating! * 100).round()} %'),
            ]),
          ),
        const SizedBox(height: 8),
        const Divider(),
      ]),
    );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: 'Chercher dans ce sermon',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(sermonId: sermon.id))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'bigger') setState(() => fontSize = (fontSize + 2).clamp(14, 34));
              if (v == 'smaller') setState(() => fontSize = (fontSize - 2).clamp(14, 34));
              if (v == 'goto') _askParagraph();
              if (v == 'switch' && other != null) setState(() => _load(other!.id));
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'bigger', child: Text('Agrandir le texte')),
              const PopupMenuItem(value: 'smaller', child: Text('Réduire le texte')),
              const PopupMenuItem(value: 'goto', child: Text('Aller au paragraphe…')),
              if (other != null)
                PopupMenuItem(value: 'switch', child: Text('Lire la version ${other!.language == 'ln' ? 'lingala' : 'française'}')),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: sermon.audioUrl == null
          ? null
          : FloatingActionButton(
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .9),
              shape: const CircleBorder(),
              onPressed: () async {
                await context.read<AudioController>().play(sermon);
                if (context.mounted) showAudioSheet(context);
              },
              child: const Icon(Icons.play_arrow_rounded, size: 36),
            ),
      body: Column(children: [
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: _items,
            itemPositionsListener: _positions,
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: paras.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) return header;
              final p = paras[i - 1];
              final key = '${sermon.id}:${p.number}';
              final hl = highlights[key];
              final ln = parallel ? otherByNumber[p.number] : null;
              return GestureDetector(
                onLongPress: () => _paragraphMenu(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: hl != null
                        ? Color(hl).withValues(alpha: .22)
                        : (flash == p.number ? Brand.gold.withValues(alpha: .12) : null),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(
                      TextSpan(children: [
                        if (p.number == 1 && i == 1)
                          const TextSpan(text: '🦅  ')
                        else
                          TextSpan(
                              text: '${p.number}  ',
                              style: TextStyle(fontSize: fontSize * .7, color: cs.onSurfaceVariant, fontFamily: null)),
                        TextSpan(text: p.text),
                        if (noted.contains(key))
                          WidgetSpan(
                              child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.sticky_note_2_outlined, size: fontSize * .8, color: Brand.gold))),
                      ]),
                      style: TextStyle(fontFamily: readingFont, fontSize: fontSize, height: 1.5),
                    ),
                    if (ln != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Brand.gold, width: 3))),
                        child: Text(ln.text,
                            style: TextStyle(
                                fontFamily: readingFont, fontSize: fontSize * .9, height: 1.5, color: cs.onSurfaceVariant)),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _askParagraph() async {
    final ctrl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aller au paragraphe'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text)), child: const Text('OK')),
        ],
      ),
    );
    if (n != null) _jumpTo(n);
  }
}
