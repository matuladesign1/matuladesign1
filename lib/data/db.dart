import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/settings.dart';
import 'models.dart';

/// Version de la base biblique embarquée. Incrémenter quand assets/db/bible.db change.
const bibleAssetVersion = 1;

/// Schéma des sermons — identique à tools/import_sermons.py (format de pack 1).
const sermonSchema = '''
CREATE TABLE IF NOT EXISTS sermons(
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL,
  language TEXT NOT NULL,
  title TEXT NOT NULL,
  date TEXT,
  year INTEGER,
  location TEXT,
  duration_sec INTEGER,
  series TEXT,
  audio_url TEXT,
  audio_cues INTEGER NOT NULL DEFAULT 0,
  pdf_name TEXT,
  source TEXT,
  sha1 TEXT,
  paragraph_count INTEGER NOT NULL DEFAULT 0,
  translation_status TEXT NOT NULL DEFAULT 'original',
  needs_review INTEGER NOT NULL DEFAULT 0,
  review_notes TEXT,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(code, language));
CREATE TABLE IF NOT EXISTS paragraphs(
  id INTEGER PRIMARY KEY,
  sermon_id INTEGER NOT NULL REFERENCES sermons(id) ON DELETE CASCADE,
  number INTEGER NOT NULL,
  text TEXT NOT NULL,
  start_ms INTEGER);
CREATE INDEX IF NOT EXISTS paragraphs_sermon ON paragraphs(sermon_id, number);
''';

const appSchema = '''
CREATE VIRTUAL TABLE IF NOT EXISTS paragraphs_fts USING fts5(
  text, content='paragraphs', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2');
CREATE TRIGGER IF NOT EXISTS paragraphs_ai AFTER INSERT ON paragraphs BEGIN
  INSERT INTO paragraphs_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS paragraphs_ad AFTER DELETE ON paragraphs BEGIN
  INSERT INTO paragraphs_fts(paragraphs_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS paragraphs_au AFTER UPDATE ON paragraphs BEGIN
  INSERT INTO paragraphs_fts(paragraphs_fts, rowid, text) VALUES('delete', old.id, old.text);
  INSERT INTO paragraphs_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TABLE IF NOT EXISTS notes(
  id INTEGER PRIMARY KEY, title TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '',
  ref_type TEXT, ref_key TEXT, ref_label TEXT, collection TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body, content='notes', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2');
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
END;
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
END;
CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
END;
CREATE TABLE IF NOT EXISTS favorites(
  ref_type TEXT NOT NULL, ref_key TEXT NOT NULL, label TEXT NOT NULL,
  excerpt TEXT, collection TEXT, created_at TEXT NOT NULL,
  PRIMARY KEY(ref_type, ref_key));
CREATE TABLE IF NOT EXISTS highlights(
  ref_type TEXT NOT NULL, ref_key TEXT NOT NULL, color INTEGER NOT NULL,
  created_at TEXT NOT NULL, PRIMARY KEY(ref_type, ref_key));
CREATE TABLE IF NOT EXISTS history(
  ref_type TEXT NOT NULL, ref_key TEXT NOT NULL, label TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL,
  PRIMARY KEY(ref_type, ref_key));
CREATE TABLE IF NOT EXISTS search_history(
  query TEXT NOT NULL, mode TEXT NOT NULL, ts TEXT NOT NULL,
  PRIMARY KEY(query, mode));
CREATE TABLE IF NOT EXISTS activity(day TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS plan_state(
  plan_id TEXT PRIMARY KEY, started_at TEXT NOT NULL, paused INTEGER NOT NULL DEFAULT 0,
  last_read_at TEXT);
CREATE TABLE IF NOT EXISTS plan_progress(
  plan_id TEXT NOT NULL, day INTEGER NOT NULL, done_at TEXT NOT NULL,
  PRIMARY KEY(plan_id, day));
CREATE TABLE IF NOT EXISTS translations_cache(
  sermon_id INTEGER NOT NULL, number INTEGER NOT NULL, lang TEXT NOT NULL,
  text TEXT NOT NULL, PRIMARY KEY(sermon_id, number, lang));
''';

String nowIso() => DateTime.now().toIso8601String();

class AppDb {
  AppDb._(this.db, this.dir);
  final Database db;
  final Directory dir;

  static late AppDb I;

  String get pdfDir => p.join(dir.path, 'pdf');

  static Future<AppDb> open(Settings settings, {void Function(double)? onProgress}) async {
    final dir = await getApplicationSupportDirectory();
    final biblePath = p.join(dir.path, 'bible.db');
    if (!File(biblePath).existsSync() || settings.bibleAssetVersion < bibleAssetVersion) {
      final data = await rootBundle.load('assets/db/bible.db');
      await File(biblePath).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
      settings.bibleAssetVersion = bibleAssetVersion;
    }
    Directory(p.join(dir.path, 'pdf')).createSync(recursive: true);
    await _installSermonBundle(dir, settings, onProgress);
    final db = sqlite3.open(p.join(dir.path, 'matomate.db'));
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute(sermonSchema);
    db.execute(appSchema);
    db.execute("ATTACH DATABASE ? AS bible", [biblePath]);
    I = AppDb._(db, dir);
    return I;
  }

  /// Installe (ou met à jour) la bibliothèque de sermons livrée avec l'application.
  /// La base est découpée en morceaux dans assets/sermons/ (voir tools/import_grenier.py)
  /// et recopiée morceau par morceau pour rester légère en mémoire.
  /// Les données personnelles et les sermons importés par l'utilisateur sont conservés.
  static Future<void> _installSermonBundle(Directory dir, Settings settings, void Function(double)? onProgress) async {
    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(await rootBundle.loadString('assets/sermons/manifest.json')) as Map<String, dynamic>;
    } catch (_) {
      return; // aucune bibliothèque embarquée
    }
    final id = '${manifest['version']}-${manifest['bytes']}-${manifest['sermons']}';
    final mainPath = p.join(dir.path, 'matomate.db');
    if (settings.sermonsBundle == id && File(mainPath).existsSync()) return;

    final parts = (manifest['parts'] as List).cast<String>();
    final tmpPath = p.join(dir.path, 'matomate_new.db');
    final tmp = File(tmpPath);
    if (tmp.existsSync()) tmp.deleteSync();
    final sink = tmp.openWrite();
    for (var i = 0; i < parts.length; i++) {
      final data = await rootBundle.load('assets/sermons/${parts[i]}');
      sink.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await sink.flush();
      onProgress?.call((i + 1) / (parts.length + 1));
    }
    await sink.close();

    final fresh = sqlite3.open(tmpPath);
    try {
      fresh.execute(sermonSchema);
      fresh.execute(appSchema);
      if (File(mainPath).existsSync()) {
        fresh.execute('ATTACH DATABASE ? AS old', [mainPath]);
        fresh.execute('BEGIN');
        for (final t in const ['notes', 'favorites', 'highlights', 'history', 'search_history', 'activity',
          'plan_state', 'plan_progress', 'translations_cache']) {
          fresh.execute('INSERT OR IGNORE INTO main.$t SELECT * FROM old.$t');
        }
        // Sermons importés par l'utilisateur (absents de la bibliothèque embarquée).
        final mine = fresh.select(
            'SELECT o.* FROM old.sermons o WHERE NOT EXISTS '
            '(SELECT 1 FROM main.sermons m WHERE m.code=o.code AND m.language=o.language)');
        for (final r in mine) {
          fresh.execute(
              'INSERT INTO main.sermons(code,language,title,date,year,location,duration_sec,series,audio_url,audio_cues,'
              'pdf_name,source,sha1,paragraph_count,translation_status,needs_review,review_notes) '
              'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
              [r['code'], r['language'], r['title'], r['date'], r['year'], r['location'], r['duration_sec'],
                r['series'], r['audio_url'], r['audio_cues'], r['pdf_name'], r['source'], r['sha1'],
                r['paragraph_count'], r['translation_status'], r['needs_review'], r['review_notes']]);
          final nid = fresh.lastInsertRowId;
          fresh.execute(
              'INSERT INTO main.paragraphs(sermon_id, number, text, start_ms) '
              'SELECT ?, number, text, start_ms FROM old.paragraphs WHERE sermon_id=? ORDER BY number',
              [nid, r['id']]);
          final oldPdf = File(p.join(dir.path, 'pdf', '${r['id']}.pdf'));
          if (oldPdf.existsSync()) oldPdf.renameSync(p.join(dir.path, 'pdf', 'n$nid.pdf'));
        }
        fresh.execute('COMMIT');
        fresh.execute('DETACH DATABASE old');
      }
    } finally {
      fresh.dispose();
    }
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$mainPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    tmp.renameSync(mainPath);
    // Les PDF des sermons importés ont été renommés « n<id>.pdf » : on retire le préfixe.
    final pdfDir = Directory(p.join(dir.path, 'pdf'));
    final files = pdfDir.listSync().whereType<File>().toList();
    for (final f in files.where((f) => !p.basename(f.path).startsWith('n'))) {
      f.deleteSync(); // PDF d'un sermon désormais fourni par la bibliothèque embarquée
    }
    for (final f in files.where((f) => p.basename(f.path).startsWith('n'))) {
      f.renameSync(p.join(pdfDir.path, p.basename(f.path).substring(1)));
    }
    settings.sermonsBundle = id;
    onProgress?.call(1);
  }

  // ---------------------------------------------------------------- Bible
  List<BibleBook> books() => db
      .select('SELECT id, name, abbr, testament, chapters FROM bible.books ORDER BY id')
      .map(BibleBook.fromRow)
      .toList();

  List<String> bibleVersions() =>
      db.select('SELECT code FROM bible.versions ORDER BY code').map((r) => r['code'] as String).toList();

  String bibleVersionName(String code) =>
      (db.select('SELECT name FROM bible.versions WHERE code=?', [code]).firstOrNull?['name']
          as String?) ??
      code;

  List<Verse> chapter(String version, int book, int chapter) => db
      .select(
          'SELECT id, book, chapter, verse, text FROM bible.verses '
          'WHERE version=? AND book=? AND chapter=? ORDER BY verse',
          [version, book, chapter])
      .map(Verse.fromRow)
      .toList();

  Verse? verseById(int id) => db
      .select('SELECT id, book, chapter, verse, text FROM bible.verses WHERE id=?', [id])
      .map(Verse.fromRow)
      .firstOrNull;

  // ---------------------------------------------------------------- Sermons
  static const _sermonCols =
      'id, code, language, title, date, year, location, duration_sec, series, audio_url, '
      'audio_cues, pdf_name, source, paragraph_count, translation_status, needs_review, review_notes';

  int sermonCount() =>
      db.select("SELECT count(DISTINCT code) c FROM sermons WHERE translation_status != 'ia_non_validee'")
          .first['c'] as int;

  /// Liste de la bibliothèque. [order] : date | title | duration | series | location.
  List<Sermon> sermons({String order = 'date', String filter = '', String? series, int? year, String? location}) {
    final where = <String>["translation_status != 'ia_non_validee'"];
    final args = <Object?>[];
    if (filter.trim().isNotEmpty) {
      where.add('(title LIKE ? OR code LIKE ? OR location LIKE ? OR date LIKE ?)');
      final f = '%${filter.trim()}%';
      args.addAll([f, f, f, f]);
    }
    if (series != null) {
      where.add('series = ?');
      args.add(series);
    }
    if (year != null) {
      where.add('year = ?');
      args.add(year);
    }
    if (location != null) {
      where.add('location = ?');
      args.add(location);
    }
    final orderBy = switch (order) {
      'title' => 'title COLLATE NOCASE',
      'duration' => 'duration_sec DESC NULLS LAST, code',
      'series' => 'series NULLS LAST, code',
      'location' => 'location NULLS LAST, code',
      _ => 'code',
    };
    return db
        .select('SELECT $_sermonCols FROM sermons WHERE ${where.join(' AND ')} ORDER BY $orderBy', args)
        .map(Sermon.fromRow)
        .toList();
  }

  Sermon? sermon(int id) =>
      db.select('SELECT $_sermonCols FROM sermons WHERE id=?', [id]).map(Sermon.fromRow).firstOrNull;

  /// Autre version linguistique du même sermon (ex. lingala d'un sermon français).
  Sermon? sermonVersion(String code, String language) => db
      .select('SELECT $_sermonCols FROM sermons WHERE code=? AND language=?', [code, language])
      .map(Sermon.fromRow)
      .firstOrNull;

  List<Paragraph> paragraphs(int sermonId) => db
      .select('SELECT id, sermon_id, number, text, start_ms FROM paragraphs WHERE sermon_id=? ORDER BY number',
          [sermonId])
      .map(Paragraph.fromRow)
      .toList();

  Map<String, int> seriesCounts() => {
        for (final r in db.select(
            'SELECT series, count(DISTINCT code) c FROM sermons WHERE series IS NOT NULL GROUP BY series ORDER BY series'))
          r['series'] as String: r['c'] as int
      };

  Map<int, int> yearCounts() => {
        for (final r in db.select(
            'SELECT year, count(DISTINCT code) c FROM sermons WHERE year IS NOT NULL GROUP BY year ORDER BY year'))
          r['year'] as int: r['c'] as int
      };

  Map<String, int> locationCounts() => {
        for (final r in db.select(
            'SELECT location, count(DISTINCT code) c FROM sermons WHERE location IS NOT NULL GROUP BY location ORDER BY c DESC, location'))
          r['location'] as String: r['c'] as int
      };

  String? pdfPathFor(Sermon s) {
    final f = File(p.join(pdfDir, '${s.id}.pdf'));
    return f.existsSync() ? f.path : null;
  }

  /// Paragraphe du jour, choisi de façon déterministe parmi les vrais textes importés.
  ({Sermon sermon, Paragraph paragraph})? quoteOfTheDay(DateTime day) {
    final total = db.select(
        "SELECT count(*) c FROM paragraphs p JOIN sermons s ON s.id=p.sermon_id "
        "WHERE s.translation_status='original' AND length(p.text) BETWEEN 140 AND 420").first['c'] as int;
    if (total == 0) return null;
    final seed = day.year * 1000 + int.parse(_dayOfYear(day));
    final r = db.select(
        "SELECT p.id, p.sermon_id, p.number, p.text, p.start_ms FROM paragraphs p JOIN sermons s ON s.id=p.sermon_id "
        "WHERE s.translation_status='original' AND length(p.text) BETWEEN 140 AND 420 "
        "ORDER BY p.id LIMIT 1 OFFSET ?",
        [seed % total]).first;
    final para = Paragraph.fromRow(r);
    return (sermon: sermon(para.sermonId)!, paragraph: para);
  }

  Verse verseOfTheDay(DateTime day, String version) {
    // Sélection de versets courts et édifiants : Psaumes, Proverbes, Évangiles, Épîtres.
    final rows = db.select(
        "SELECT count(*) c FROM bible.verses WHERE version=? AND book IN (19,20,23,43,45,49,50,58,62) "
        "AND length(text) BETWEEN 60 AND 220",
        [version]);
    final total = rows.first['c'] as int;
    final seed = day.year * 1000 + int.parse(_dayOfYear(day));
    return Verse.fromRow(db.select(
        "SELECT id, book, chapter, verse, text FROM bible.verses WHERE version=? "
        "AND book IN (19,20,23,43,45,49,50,58,62) AND length(text) BETWEEN 60 AND 220 "
        "ORDER BY id LIMIT 1 OFFSET ?",
        [version, (seed * 7919) % (total == 0 ? 1 : total)]).first);
  }

  String _dayOfYear(DateTime d) => '${d.difference(DateTime(d.year)).inDays + 1}';

  void deleteSermon(int id) {
    db.execute('DELETE FROM sermons WHERE id=?', [id]);
    final f = File(p.join(pdfDir, '$id.pdf'));
    if (f.existsSync()) f.deleteSync();
  }
}
