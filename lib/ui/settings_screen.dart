import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../main.dart';
import 'library_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.focusNotifications = false});
  final bool focusNotifications;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<Settings>();
    final s = st.s;
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
          child: Text(t.toUpperCase(), style: const TextStyle(color: Brand.gold, letterSpacing: 1.5, fontSize: 13)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(children: [
        header('Affichage'),
        ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(s.t('language')),
          subtitle: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'fr', label: Text('Français')), ButtonSegment(value: 'ln', label: Text('Lingala'))],
            selected: {st.lang},
            onSelectionChanged: (v) => st.lang = v.first,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(s.t('theme')),
          subtitle: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ThemeMode.dark, label: Text(s.t('dark'))),
              ButtonSegment(value: ThemeMode.light, label: Text(s.t('light'))),
              ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_outlined, size: 18)),
            ],
            selected: {st.themeMode},
            onSelectionChanged: (v) => st.themeMode = v.first,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.format_size_rounded),
          title: Text(s.t('fontSize')),
          subtitle: Slider(
            value: st.textScale,
            min: .85,
            max: 1.5,
            divisions: 13,
            label: '${(st.textScale * 100).round()} %',
            onChanged: (v) => st.textScale = v,
          ),
        ),
        header(s.t('notifications')),
        SwitchListTile(
          secondary: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Verset et citation du jour'),
          value: st.notifyVerse,
          onChanged: (v) => st.notifyVerse = v,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.alarm_rounded),
          title: const Text('Rappel de lecture et reprise des plans'),
          value: st.notifyReading,
          onChanged: (v) => st.notifyReading = v,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Les rappels planifiés seront envoyés à partir de la version 1.1 ; vos choix sont déjà enregistrés.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        header('Bibliothèque et fichiers'),
        ListTile(
          leading: const Icon(Icons.upload_file_rounded),
          title: const Text('Importer des prédications'),
          subtitle: const Text('PDF, dossiers, ZIP ou packs préparés'),
          onTap: () => showImportSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.storage_rounded),
          title: const Text('Gestion des fichiers'),
          subtitle: Text('${adb.sermonCount()} prédication(s) · ${_size(adb)}'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _ManageLibrary())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.manage_search_rounded),
          title: const Text('Inclure mes notes dans la recherche'),
          value: st.searchNotes,
          onChanged: (v) => st.searchNotes = v,
        ),
        header('Assistant IA'),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Serveur IA (Supabase)'),
          subtitle: Text(st.hasServer ? st.serverUrl : 'Non configuré — mode recherche locale'),
          onTap: () => _server(context, st),
        ),
        header('Compte et confidentialité'),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(s.t('privacy')),
          onTap: () => _text(context, s.t('privacy'),
              'Vos notes, favoris, surlignages et votre historique sont enregistrés uniquement sur cet appareil.\n\n'
              'Lorsque vous utilisez l\'assistant IA, votre question et les passages trouvés sont envoyés au serveur configuré, '
              'qui les transmet au service d\'IA pour rédiger la réponse. Aucune autre donnée personnelle n\'est transmise.\n\n'
              'Aucune publicité, aucun traceur.'),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(s.t('terms')),
          onTap: () => _text(context, s.t('terms'),
              'Les textes de la Bible Louis Segond 1910 appartiennent au domaine public.\n\n'
              'Les prédications, traductions et enregistrements audio importés restent la propriété de leurs ayants droit. '
              'L\'utilisateur ou l\'administrateur qui importe des documents garantit disposer des autorisations nécessaires à leur utilisation et à leur diffusion.\n\n'
              'Les traductions générées par intelligence artificielle sont signalées comme telles et ne constituent pas une édition officielle tant qu\'elles n\'ont pas été validées.'),
        ),
        header(s.t('about')),
        ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/logo_small.png', width: 40)),
          title: const Text('Sermons de Branham Matomate'),
          subtitle: const Text('Version 1.0.0'),
          onTap: () => _about(context),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '${s.t('developedBy')} :\nMatula Design & Pasteur Ben MATOMATE\n\n'
            '© ${DateTime.now().year} Matula Design & Pasteur Ben MATOMATE. ${s.t('rights')}',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  String _size(AppDb adb) {
    var bytes = 0;
    try {
      for (final f in adb.dir.listSync(recursive: true).whereType<File>()) {
        bytes += f.lengthSync();
      }
    } catch (_) {}
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }

  void _text(BuildContext context, String title, String body) => showDialog(
      context: context,
      builder: (_) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(body)),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ));

  void _about(BuildContext context) => showAboutDialog(
        context: context,
        applicationName: 'Sermons de Branham Matomate',
        applicationVersion: '1.0.0',
        applicationIcon: ClipRRect(
            borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo_small.png', width: 56)),
        applicationLegalese: '© ${DateTime.now().year} Matula Design & Pasteur Ben MATOMATE. Tous droits réservés.',
        children: const [
          SizedBox(height: 12),
          Text('Développé par : Matula Design & Pasteur Ben MATOMATE'),
          SizedBox(height: 8),
          Text('Bible : Louis Segond 1910 (domaine public). Police de lecture : Lora (SIL Open Font License).'),
        ],
      );

  void _server(BuildContext context, Settings st) {
    final url = TextEditingController(text: st.serverUrl);
    final key = TextEditingController(text: st.serverKey);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Serveur IA'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Adresse et clé publique (anon) du projet Supabase où est déployée la fonction « assistant ». '
                'La clé OpenAI reste sur le serveur et n\'est jamais saisie ici.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'URL (https://xxxx.supabase.co)')),
            const SizedBox(height: 12),
            TextField(controller: key, decoration: const InputDecoration(labelText: 'Clé anon')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              st.serverUrl = url.text;
              st.serverKey = key.text;
              Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

class _ManageLibrary extends StatelessWidget {
  const _ManageLibrary();
  @override
  Widget build(BuildContext context) {
    context.watch<LibraryState>();
    final adb = context.read<AppDb>();
    final list = adb.db
        .select('SELECT id, code, language, title, needs_review, review_notes, translation_status FROM sermons ORDER BY code, language')
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des fichiers')),
      body: list.isEmpty
          ? const EmptyState(icon: Icons.folder_off_outlined, title: 'Aucun document importé')
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final r = list[i];
                return ListTile(
                  title: Text('${r['code']} · ${r['title']}'),
                  subtitle: Text([
                    (r['language'] as String).toUpperCase(),
                    if (r['translation_status'] == 'ia_non_validee') 'traduction IA non validée',
                    if ((r['needs_review'] as int) == 1) 'à vérifier : ${r['review_notes']}',
                  ].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Supprimer ce document ?'),
                          content: Text('${r['code']} · ${r['title']}'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        adb.deleteSermon(r['id'] as int);
                        context.read<LibraryState>().changed();
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
