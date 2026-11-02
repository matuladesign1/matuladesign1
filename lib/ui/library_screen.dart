import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/import_service.dart';
import '../data/plans.dart';
import '../main.dart';
import 'search_screen.dart';
import 'widgets.dart';

/// Bibliothèque des prédications, classée par année, série, lieu ou A-Z.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialGroup = 'all', this.year});
  final String initialGroup;
  final int? year;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late String group = widget.year != null ? 'year' : widget.initialGroup;
  String? openKey;

  @override
  void initState() {
    super.initState();
    if (widget.year != null) openKey = '${widget.year}';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryState>();
    final s = context.watch<Settings>().s;
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;
    final count = adb.sermonCount();

    Widget body;
    if (count == 0) {
      body = EmptyState(
        icon: Icons.local_library_outlined,
        title: s.t('emptyLibrary'),
        message: s.t('emptyLibrarySub'),
        action: FilledButton.icon(
            onPressed: () => showImportSheet(context),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Importer des prédications')),
      );
    } else if (openKey != null) {
      final list = switch (group) {
        'year' => adb.sermons(year: int.parse(openKey!)),
        'series' => adb.sermons(series: openKey),
        'location' => adb.sermons(location: openKey),
        'brochures' => adb.collectionSermons(openKey!),
        _ => adb.sermons(),
      };
      body = ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) => SermonRow(sermon: list[i]),
      );
    } else if (group == 'all' || group == 'az') {
      final list = adb.sermons(order: group == 'az' ? 'title' : 'date');
      body = ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) => SermonRow(sermon: list[i]),
      );
    } else {
      final Map<String, int> groups = switch (group) {
        'year' => {
            for (final y in [for (var y = 1947; y <= 1965; y++) y]) '$y': adb.yearCounts()[y] ?? 0,
          },
        'series' => {
            for (final sName in _defaultSeries) sName: adb.seriesCounts()[sName] ?? 0,
            ...adb.seriesCounts(),
          },
        'brochures' => adb.collectionCounts(),
        _ => adb.locationCounts(),
      };
      body = ListView(children: [
        for (final e in groups.entries)
          ListTile(
            enabled: e.value > 0,
            leading: Icon(group == 'year'
                ? Icons.calendar_month_outlined
                : group == 'series'
                    ? Icons.collections_bookmark_outlined
                    : group == 'brochures'
                        ? Icons.auto_stories_outlined
                        : Icons.place_outlined),
            title: Text(e.key),
            trailing: Text(e.value == 0 ? 'aucune' : '${e.value}', style: TextStyle(color: cs.onSurfaceVariant)),
            onTap: () => setState(() => openKey = e.key),
          ),
        if (groups.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('Aucune donnée pour ce classement.')),
      ]);
    }

    return PopScope(
      canPop: openKey == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => openKey = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(openKey ?? s.t('library')),
          actions: [
            IconButton(
                tooltip: 'Importer', icon: const Icon(Icons.upload_file_rounded), onPressed: () => showImportSheet(context)),
          ],
        ),
        body: Column(children: [
          if (count > 0)
            SizedBox(
              height: 56,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                for (final (k, label) in [
                  ('all', 'Tous ($count)'),
                  ('year', 'Par année'),
                  ('az', 'A-Z'),
                  ('brochures', 'Brochures'),
                  ('series', 'Par séries'),
                  ('location', 'Par lieu'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: group == k,
                      onSelected: (_) => setState(() {
                        group = k;
                        openKey = null;
                      }),
                    ),
                  ),
              ]),
            ),
          Expanded(child: body),
        ]),
      ),
    );
  }

  static const _defaultSeries = [
    'La Révélation des Sept Sceaux',
    'La Révélation de Jésus-Christ',
    'Les Sept Âges de l\'Église',
    'La Conduite, l\'Ordre et la Doctrine de l\'Église',
    'Le Livre des Hébreux',
    'Le Saint-Esprit',
    'L\'Adoption',
    'Les Soixante-dix semaines de Daniel',
    'L\'Église',
    'La Démonologie',
    'Israël et l\'Église',
    'Questions et Réponses',
  ];
}

/// Feuille d'import : PDF (un ou plusieurs), ZIP, packs, dossier.
Future<void> showImportSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(
          title: Text('Importer des prédications', style: TextStyle(fontSize: 20)),
          subtitle: Text(
              'Chaque document conserve sa source et son fichier original. Les doublons sont détectés automatiquement. '
              'Importez uniquement des fichiers que vous avez le droit d\'utiliser.'),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined, color: Brand.gold),
          title: const Text('Fichiers PDF'),
          subtitle: const Text('Un ou plusieurs PDF à la fois'),
          onTap: () async {
            Navigator.pop(ctx);
            final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf']);
            if (r != null && context.mounted) {
              await runImport(context, r.files.map((f) => f.path).whereType<String>().toList());
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_zip_outlined, color: Brand.gold),
          title: const Text('Archive ZIP ou pack .smpack'),
          subtitle: const Text('Des centaines de sermons en une seule opération'),
          onTap: () async {
            Navigator.pop(ctx);
            final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
            if (r != null && context.mounted) {
              await runImport(context, r.files.map((f) => f.path).whereType<String>().toList());
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_open_outlined, color: Brand.gold),
          title: const Text('Dossier complet'),
          subtitle: const Text('Parcourt le dossier et ses sous-dossiers (Android 12 ou moins ; sinon utilisez un ZIP)'),
          onTap: () async {
            Navigator.pop(ctx);
            final dir = await FilePicker.platform.getDirectoryPath();
            if (dir != null && context.mounted) await runImport(context, [dir]);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<void> runImport(BuildContext context, List<String> paths) async {
  if (paths.isEmpty) return;
  final adb = context.read<AppDb>();
  final lib = context.read<LibraryState>();
  final plans = context.read<Plans>();
  final progress = ValueNotifier<(int, int, String)>((0, 0, ''));
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Import en cours'),
        content: ValueListenableBuilder<(int, int, String)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
            const SizedBox(height: 12),
            Text(v.$2 == 0 ? 'Préparation…' : '${v.$1} / ${v.$2}'),
            Text(v.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    ),
  );
  ImportReport? report;
  String? error;
  try {
    report = await ImportService(adb.db.select('PRAGMA database_list').first['file'] as String, adb.pdfDir)
        .importPaths(paths, onProgress: (d, t, c) => progress.value = (d, t, c));
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  lib.changed();
  plans.refresh();
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(error == null ? 'Import terminé' : 'Import interrompu'),
      content: SizedBox(
        width: double.maxFinite,
        child: error != null
            ? Text(error)
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(report!.summary, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final l in report.lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}
