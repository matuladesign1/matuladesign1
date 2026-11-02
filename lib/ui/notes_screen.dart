import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/user_repo.dart';
import 'sermon_reader.dart';
import 'shell.dart';
import 'widgets.dart';

/// Ouvre l'élément visé par un favori (sermon, paragraphe ou verset).
void openFavorite(BuildContext context, Favorite f) => openRef(context, f.refType, f.refKey);

void openRef(BuildContext context, String type, String key) {
  final adb = context.read<AppDb>();
  switch (type) {
    case 'sermon':
      {
        final id = int.tryParse(key);
        if (id != null && adb.sermon(id) != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => SermonReader(sermonId: id)));
        }
      }
    case 'para':
      {
        final parts = key.split(':');
        final id = int.tryParse(parts[0]);
        if (id != null && adb.sermon(id) != null) {
          final n = int.tryParse(parts[1]);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => SermonReader(sermonId: id, paragraph: n, highlightParagraph: n)));
        }
      }
    case 'verse':
      {
        // version:livre:chapitre:verset
        final parts = key.split(':');
        if (parts.length == 4) {
          Shell.of(context).openBible(int.parse(parts[1]), int.parse(parts[2]), verse: int.parse(parts[3]));
        }
      }
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, this.initialTab = 0, this.sermon});
  final int initialTab;
  final Sermon? sermon;
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String? collection;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRepo>();
    final cs = Theme.of(context).colorScheme;
    final sermon = widget.sermon;
    var notes = user.notes();
    if (sermon != null) {
      notes = notes
          .where((n) =>
              (n.refType == 'sermon' && n.refKey == '${sermon.id}') ||
              (n.refType == 'para' && (n.refKey ?? '').startsWith('${sermon.id}:')))
          .toList();
    }
    final collections = notes.map((n) => n.collection).whereType<String>().toSet().toList()..sort();
    if (collection != null) notes = notes.where((n) => n.collection == collection).toList();
    final favs = user.favorites();
    final hist = user.history();

    return DefaultTabController(
      length: sermon == null ? 3 : 1,
      initialIndex: sermon == null ? widget.initialTab : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(sermon == null ? 'Mon espace' : 'Notes · ${sermon.code}'),
          actions: [
            if (sermon == null)
              IconButton(
                tooltip: 'Exporter mes notes',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => Share.share(user.exportNotesText()),
              ),
          ],
          bottom: sermon == null
              ? const TabBar(tabs: [Tab(text: 'Notes'), Tab(text: 'Favoris'), Tab(text: 'Historique')])
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NoteEditor(
                        refType: sermon == null ? null : 'sermon',
                        refKey: sermon == null ? null : '${sermon.id}',
                        refLabel: sermon == null ? null : '${sermon.code} · ${sermon.title}',
                      ))),
          icon: const Icon(Icons.add),
          label: const Text('Nouvelle note'),
        ),
        body: TabBarView(children: [
          Column(children: [
            if (collections.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
                  ChoiceChip(label: const Text('Toutes'), selected: collection == null, onSelected: (_) => setState(() => collection = null)),
                  for (final c in collections)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(label: Text(c), selected: collection == c, onSelected: (_) => setState(() => collection = c)),
                    ),
                ]),
              ),
            Expanded(
              child: notes.isEmpty
                  ? const EmptyState(
                      icon: Icons.edit_note_rounded,
                      title: 'Aucune note',
                      message: 'Appuyez longuement sur un paragraphe ou un verset pour l\'annoter, ou créez une note libre.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: notes.length,
                      itemBuilder: (_, i) {
                        final n = notes[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              title: Text(n.title.isEmpty ? 'Sans titre' : n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (n.refLabel != null)
                                  Text(n.refLabel!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
                                Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(n.updatedAt.substring(0, 16).replaceAll('T', ' '),
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              ]),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditor(note: n))),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]),
          if (sermon == null) ...[
            favs.isEmpty
                ? const EmptyState(icon: Icons.star_outline_rounded, title: 'Aucun favori', message: 'Ajoutez des sermons, paragraphes et versets à vos favoris.')
                : ListView(padding: const EdgeInsets.all(8), children: [
                    for (final f in favs)
                      ListTile(
                        leading: Icon(
                            f.refType == 'verse'
                                ? Icons.menu_book_outlined
                                : f.refType == 'para'
                                    ? Icons.format_quote_rounded
                                    : Icons.star_rounded,
                            color: Brand.gold),
                        title: Text(f.label),
                        subtitle: f.excerpt == null ? null : Text(f.excerpt!, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => openFavorite(context, f),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => user.toggleFavorite(f.refType, f.refKey, f.label),
                        ),
                      ),
                  ]),
            hist.isEmpty
                ? const EmptyState(icon: Icons.history_rounded, title: 'Historique vide')
                : ListView(padding: const EdgeInsets.all(8), children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                          onPressed: user.clearHistory, icon: const Icon(Icons.delete_sweep_outlined), label: const Text('Effacer')),
                    ),
                    for (final h in hist)
                      ListTile(
                        leading: Icon(h.type == 'bible' ? Icons.menu_book_outlined : Icons.record_voice_over_outlined),
                        title: Text(h.label),
                        subtitle: Text(h.ts.substring(0, 16).replaceAll('T', ' ')),
                        onTap: () {
                          if (h.type == 'bible') {
                            final p = h.key.split(':');
                            Shell.of(context).openBible(int.parse(p[0]), int.parse(p[1]));
                          } else {
                            openRef(context, h.type, h.key);
                          }
                        },
                      ),
                  ]),
          ],
        ]),
      ),
    );
  }
}

/// Création / modification d'une note, sauvegardée automatiquement.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note, this.refType, this.refKey, this.refLabel, this.quote});
  final Note? note;
  final String? refType, refKey, refLabel, quote;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  late final _collection = TextEditingController(text: widget.note?.collection ?? '');
  int? id;
  late final UserRepo _user;

  @override
  void initState() {
    super.initState();
    id = widget.note?.id;
    _user = context.read<UserRepo>();
  }

  void _save() {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) return;
    id = _user.saveNote(
      id: id,
      title: _title.text.trim(),
      body: _body.text,
      refType: widget.note?.refType ?? widget.refType,
      refKey: widget.note?.refKey ?? widget.refKey,
      refLabel: widget.note?.refLabel ?? widget.refLabel,
      collection: _collection.text.trim().isEmpty ? null : _collection.text.trim(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.note?.refLabel ?? widget.refLabel;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) Future.microtask(_save);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(id == null ? 'Nouvelle note' : 'Note'),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => Share.share('${_title.text}\n${label ?? ''}\n\n${_body.text}'),
            ),
            if (id != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  _user.deleteNote(id!);
                  _title.clear();
                  _body.clear();
                  id = null;
                  Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (label != null)
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.w600)),
          if (widget.quote != null)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: Brand.gold, width: 3))),
              child: Text(widget.quote!, style: TextStyle(fontFamily: readingFont, color: cs.onSurfaceVariant, height: 1.4)),
            ),
          TextField(
            controller: _title,
            onChanged: (_) => _save(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Titre', filled: false, border: InputBorder.none),
          ),
          TextField(
            controller: _collection,
            onChanged: (_) => _save(),
            decoration: const InputDecoration(
                hintText: 'Collection (facultatif)', prefixIcon: Icon(Icons.folder_outlined), filled: false, border: InputBorder.none),
          ),
          TextField(
            controller: _body,
            onChanged: (_) => _save(),
            maxLines: null,
            minLines: 12,
            style: const TextStyle(fontSize: 17, height: 1.5),
            decoration: const InputDecoration(hintText: 'Écrivez votre commentaire…', filled: false, border: InputBorder.none),
          ),
          Text('Enregistrement automatique', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
