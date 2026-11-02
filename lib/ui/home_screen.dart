import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/user_repo.dart';
import '../main.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'profile_screen.dart';
import 'sermon_reader.dart';
import 'settings_screen.dart';
import 'shell.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ask = TextEditingController();

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _ask.text.trim();
    if (q.isEmpty) return;
    _ask.clear();
    FocusScope.of(context).unfocus();
    Shell.of(context).ask(q);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final s = settings.s;
    final user = context.watch<UserRepo>();
    context.watch<LibraryState>();
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;
    final streak = user.streak();
    final next = user.nextBadge();
    final name = settings.userName.isEmpty ? '' : ', ${settings.userName.split(' ').first}';
    final lastSermon = user.last('sermon');
    final lastChapter = user.last('bible');
    final favs = user.favorites(limit: 3);
    final today = DateTime.now();
    final quote = adb.quoteOfTheDay(today);

    return SafeArea(
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Container(
          decoration: const BoxDecoration(
            gradient: Brand.skyGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 18),
          child: Column(children: [
            Row(children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Brand.gold, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/images/logo_small.png', width: 52, height: 52)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.t('hello')}$name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: readingFont, fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                  ShaderMask(
                    shaderCallback: (r) => Brand.goldGradient.createShader(r),
                    child: const Text('Sermons de Branham Matomate',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: .4, color: Colors.white)),
                  ),
                ]),
              ),
              Tooltip(
                message: '$streak jour(s) consécutif(s)',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.bolt_rounded, color: Brand.brightYellow, size: 20),
                    Text('$streak', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen(focusNotifications: true))),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: Brand.gold,
                  child: Text(settings.userName.isEmpty ? '?' : settings.userName[0].toUpperCase(),
                      style: const TextStyle(color: Brand.deepBlue, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _ask,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: s.t('askHint'),
                prefixIcon: const Icon(Icons.auto_awesome, color: Brand.gold),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.deepBlue),
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: quote != null
              ? _QuoteCard(
                  label: s.t('quoteOfDay'),
                  text: quote.paragraph.text,
                  title: quote.sermon.title,
                  place: quote.sermon.shortLocation,
                  ref: '${quote.sermon.code} · ¶${quote.paragraph.number}',
                  onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SermonReader(sermonId: quote.sermon.id, paragraph: quote.paragraph.number))),
                  shareText:
                      '« ${quote.paragraph.text} »\n— ${quote.sermon.title}, ${quote.sermon.code} ¶${quote.paragraph.number}, ${quote.sermon.shortLocation}',
                  variant: today.day,
                )
              : Builder(builder: (_) {
                  final v = adb.verseOfTheDay(today, settings.bibleVersion);
                  final book = adb.books()[v.book - 1].name;
                  return _QuoteCard(
                    label: s.t('verseOfDay'),
                    text: v.text,
                    title: '$book ${v.chapter}:${v.verse}',
                    place: adb.bibleVersionName(settings.bibleVersion),
                    ref: 'Importez des prédications pour afficher une citation du jour.',
                    onOpen: () => Shell.of(context).openBible(v.book, v.chapter, verse: v.verse),
                    shareText: '« ${v.text} »\n— $book ${v.chapter}:${v.verse} (${settings.bibleVersion})',
                    variant: today.day,
                  );
                }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
                child: IconTile(
                    icon: Icons.local_library_outlined,
                    label: s.t('library'),
                    color: Brand.gold,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())))),
            const SizedBox(width: 10),
            Expanded(
                child: IconTile(
                    icon: Icons.edit_note_rounded,
                    label: s.t('notes'),
                    color: const Color(0xFF7FD1A8),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotesScreen())))),
            const SizedBox(width: 10),
            Expanded(
                child: IconTile(
                    icon: Icons.account_circle_outlined,
                    label: s.t('profile'),
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())))),
            const SizedBox(width: 10),
            Expanded(
                child: IconTile(
                    icon: Icons.settings_outlined,
                    label: s.t('settings'),
                    color: cs.onSurfaceVariant,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: cs.surfaceContainerHighest,
                child: Icon(Icons.workspace_premium_outlined, color: next == null ? Brand.gold : cs.onSurfaceVariant, size: 30),
              ),
              title: Text(s.t('nextBadge'), style: TextStyle(color: cs.onSurfaceVariant)),
              subtitle: next == null
                  ? const Text('Tous les badges obtenus !', style: TextStyle(fontSize: 18))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$next ${s.t('activeDays')}', style: TextStyle(fontSize: 20, color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text(s.t('stillDays', n: next - streak), style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: streak / next, color: Brand.gold, borderRadius: BorderRadius.circular(4)),
                    ]),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
          ),
        ),
        if (lastSermon != null || lastChapter != null) ...[
          SectionTitle(s.t('resume')),
          if (lastSermon != null)
            _ResumeTile(
              icon: Icons.record_voice_over_outlined,
              label: s.t('lastSermon'),
              title: lastSermon.label,
              onTap: () {
                final id = int.tryParse(lastSermon.key);
                if (id != null && adb.sermon(id) != null) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SermonReader(sermonId: id, paragraph: lastSermon.position)));
                }
              },
            ),
          if (lastChapter != null)
            _ResumeTile(
              icon: Icons.menu_book_outlined,
              label: s.t('lastChapter'),
              title: lastChapter.label,
              onTap: () {
                final parts = lastChapter.key.split(':');
                Shell.of(context).openBible(int.parse(parts[0]), int.parse(parts[1]));
              },
            ),
        ],
        if (favs.isNotEmpty) ...[
          SectionTitle(s.t('recentFav'),
              action: s.t('seeAll'),
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotesScreen(initialTab: 1)))),
          for (final f in favs)
            _ResumeTile(
              icon: f.refType == 'verse' ? Icons.menu_book_outlined : Icons.star_rounded,
              label: f.refType == 'verse' ? 'Verset' : 'Prédication',
              title: f.label,
              onTap: () => openFavorite(context, f),
            ),
        ],
      ]),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.label,
    required this.text,
    required this.title,
    required this.place,
    required this.ref,
    required this.onOpen,
    required this.shareText,
    required this.variant,
  });
  final String label, text, title, place, ref, shareText;
  final VoidCallback onOpen;
  final int variant;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Landscape(
        variant: variant,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 12, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16))),
              PopupMenuButton<String>(
                icon: const CircleAvatar(
                    backgroundColor: Colors.black26, child: Icon(Icons.more_horiz_rounded, color: Colors.white)),
                onSelected: (v) {
                  if (v == 'open') onOpen();
                  if (v == 'share') Share.share(shareText);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Ouvrir le passage complet')),
                  PopupMenuItem(value: 'share', child: Text('Partager la citation')),
                ],
              ),
            ]),
            const Text('“', style: TextStyle(color: Colors.white38, fontSize: 56, height: .6, fontFamily: readingFont)),
            Text(text,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: readingFont, color: Colors.white, fontSize: 22, height: 1.35)),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w500)),
            if (place.isNotEmpty) Text(place, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 2),
            Text(ref, style: const TextStyle(color: Colors.white70)),
          ]),
        ),
      ),
    );
  }
}

class _ResumeTile extends StatelessWidget {
  const _ResumeTile({required this.icon, required this.label, required this.title, required this.onTap});
  final IconData icon;
  final String label, title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: Brand.gold),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(label),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onTap,
          ),
        ),
      );
}
