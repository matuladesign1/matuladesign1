import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Résultat d'une opération d'import.
class ImportReport {
  int imported = 0, duplicates = 0, toReview = 0, failed = 0;
  final List<String> lines = [];
  Map<String, Object> toJson() =>
      {'imported': imported, 'duplicates': duplicates, 'toReview': toReview, 'failed': failed, 'lines': lines};
  static ImportReport fromJson(Map m) => ImportReport()
    ..imported = m['imported'] as int
    ..duplicates = m['duplicates'] as int
    ..toReview = m['toReview'] as int
    ..failed = m['failed'] as int
    ..lines.addAll((m['lines'] as List).cast<String>());
  String get summary =>
      '$imported importé(s), $duplicates doublon(s), $toReview à vérifier, $failed échec(s)';
}

typedef Progress = void Function(int done, int total, String current);

/// Import des sermons, exécuté hors du fil de l'interface.
class ImportService {
  ImportService(this.dbPath, this.pdfDir);
  final String dbPath, pdfDir;

  /// [paths] : fichiers PDF, ZIP, packs .smpack, ou dossiers.
  Future<ImportReport> importPaths(List<String> paths, {String source = '', Progress? onProgress}) async {
    final port = ReceivePort();
    final done = Completer<ImportReport>();
    await Isolate.spawn(_worker, [port.sendPort, dbPath, pdfDir, paths, source]);
    port.listen((msg) {
      if (msg is List && msg.first == 'progress') {
        onProgress?.call(msg[1] as int, msg[2] as int, msg[3] as String);
      } else if (msg is Map) {
        done.complete(ImportReport.fromJson(msg));
        port.close();
      } else if (msg is String) {
        done.completeError(Exception(msg));
        port.close();
      }
    });
    return done.future;
  }

  static void _worker(List args) {
    final send = args[0] as SendPort;
    try {
      final w = _Worker(args[1] as String, args[2] as String, args[4] as String,
          (d, t, c) => send.send(['progress', d, t, c]));
      final report = w.run((args[3] as List).cast<String>());
      send.send(report.toJson());
    } catch (e, st) {
      send.send('Import interrompu : $e\n$st');
    }
  }
}

class _Worker {
  _Worker(String dbPath, this.pdfDir, this.source, this.progress)
      : db = sqlite3.open(dbPath)
          ..execute('PRAGMA foreign_keys=ON')
          ..execute('PRAGMA busy_timeout=10000');
  final Database db;
  final String pdfDir, source;
  final Progress progress;
  final report = ImportReport();
  late final Directory tmp = Directory.systemTemp.createTempSync('import');

  ImportReport run(List<String> inputs) {
    try {
      final files = <String>[];
      for (final i in inputs) {
        _collect(i, files);
      }
      for (var k = 0; k < files.length; k++) {
        final f = files[k];
        progress(k, files.length, p.basename(f));
        try {
          if (f.toLowerCase().endsWith('.pdf')) {
            _importPdf(f);
          } else {
            _importPack(f);
          }
        } catch (e) {
          report.failed++;
          report.lines.add('${p.basename(f)} : échec ($e)');
        }
      }
      progress(files.length, files.length, '');
      db.execute("INSERT INTO paragraphs_fts(paragraphs_fts) VALUES('optimize')");
    } finally {
      db.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
    return report;
  }

  void _collect(String path, List<String> out) {
    final lower = path.toLowerCase();
    if (FileSystemEntity.isDirectorySync(path)) {
      final entries = Directory(path).listSync(recursive: true).whereType<File>().map((e) => e.path).toList()..sort();
      for (final e in entries) {
        final l = e.toLowerCase();
        if (l.endsWith('.pdf') || l.endsWith('.zip') || l.endsWith('.smpack')) _collect(e, out);
      }
    } else if (lower.endsWith('.zip')) {
      final dest = Directory(p.join(tmp.path, 'z${out.length}_${DateTime.now().microsecondsSinceEpoch}'))
        ..createSync(recursive: true);
      final archive = ZipDecoder().decodeBuffer(InputFileStream(path));
      for (final f in archive.files) {
        final n = f.name.toLowerCase();
        if (!f.isFile || f.name.contains('..')) continue;
        if (n.endsWith('.pdf') || n.endsWith('.smpack')) {
          final target = File(p.join(dest.path, p.basename(f.name)));
          target.writeAsBytesSync(f.content as List<int>);
          out.add(target.path);
        }
      }
    } else if (lower.endsWith('.pdf') || _isSqlite(path)) {
      out.add(path);
    } else {
      report.failed++;
      report.lines.add('${p.basename(path)} : format non pris en charge');
    }
  }

  bool _isSqlite(String path) {
    try {
      final raf = File(path).openSync();
      final head = raf.readSync(16);
      raf.closeSync();
      return utf8.decode(head, allowMalformed: true).startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------ packs
  void _importPack(String path) {
    db.execute('ATTACH DATABASE ? AS pack', [path]);
    try {
      final ok = db.select("SELECT value FROM pack.pack_info WHERE key='format'").firstOrNull;
      if (ok == null) throw Exception('pack invalide');
      final hasPdf =
          db.select("SELECT 1 FROM pack.sqlite_master WHERE name='pdf_files'").isNotEmpty;
      final rows = db.select('SELECT * FROM pack.sermons ORDER BY code');
      db.execute('BEGIN');
      for (final r in rows) {
        final exists = db.select('SELECT 1 FROM sermons WHERE (code=? AND language=?) OR (sha1 IS NOT NULL AND sha1=?)',
            [r['code'], r['language'], r['sha1']]).isNotEmpty;
        if (exists) {
          report.duplicates++;
          continue;
        }
        db.execute(
            'INSERT INTO sermons(code,language,title,date,year,location,duration_sec,series,audio_url,audio_cues,'
            'pdf_name,source,sha1,paragraph_count,translation_status,needs_review,review_notes) '
            'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [r['code'], r['language'], r['title'], r['date'], r['year'], r['location'], r['duration_sec'],
              r['series'], r['audio_url'], r['audio_cues'] ?? 0, r['pdf_name'], r['source'], r['sha1'],
              r['paragraph_count'], r['translation_status'] ?? 'original', r['needs_review'], r['review_notes']]);
        final id = db.lastInsertRowId;
        db.execute(
            'INSERT INTO paragraphs(sermon_id, number, text, start_ms) '
            'SELECT ?, number, text, start_ms FROM pack.paragraphs WHERE sermon_id=? ORDER BY number',
            [id, r['id']]);
        if (hasPdf) {
          final blob = db.select('SELECT data FROM pack.pdf_files WHERE sermon_id=?', [r['id']]).firstOrNull;
          if (blob != null) File(p.join(pdfDir, '$id.pdf')).writeAsBytesSync(blob['data'] as List<int>);
        }
        report.imported++;
        if ((r['needs_review'] as int? ?? 0) == 1) report.toReview++;
      }
      db.execute('COMMIT');
      report.lines.add('${p.basename(path)} : pack importé');
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    } finally {
      db.execute('DETACH DATABASE pack');
    }
  }

  // ------------------------------------------------------------------ PDF
  void _importPdf(String path) {
    final name = p.basename(path);
    final bytes = File(path).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final pages = doc.pages.count;
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    if (text.trim().length < 80 * pages) {
      report.failed++;
      report.lines.add('$name : PDF scanné (sans texte). Utilisez l\'outil d\'import sur ordinateur, qui applique l\'OCR.');
      return;
    }
    final parsed = SermonParser.parse(name, text);
    final digest = sha1.convert(utf8.encode(SermonParser.norm(parsed.paragraphs.map((e) => e.$2).join(' ')))).toString();
    final dup = db.select('SELECT 1 FROM sermons WHERE (code=? AND language=?) OR sha1=?',
        [parsed.code, parsed.language, digest]);
    if (dup.isNotEmpty) {
      report.duplicates++;
      report.lines.add('$name : doublon (${parsed.code})');
      return;
    }
    db.execute('BEGIN');
    try {
      db.execute(
          'INSERT INTO sermons(code,language,title,date,year,location,pdf_name,source,sha1,paragraph_count,'
          'needs_review,review_notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
          [parsed.code, parsed.language, parsed.title, parsed.date, parsed.year, parsed.location, name,
            source.isEmpty ? 'Import sur l\'appareil' : source, digest, parsed.paragraphs.length,
            parsed.notes.isEmpty ? 0 : 1, parsed.notes.isEmpty ? null : parsed.notes.join('; ')]);
      final id = db.lastInsertRowId;
      final st = db.prepare('INSERT INTO paragraphs(sermon_id, number, text) VALUES(?,?,?)');
      for (final para in parsed.paragraphs) {
        st.execute([id, para.$1, para.$2]);
      }
      st.dispose();
      db.execute('COMMIT');
      File(p.join(pdfDir, '$id.pdf')).writeAsBytesSync(bytes);
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
    report.imported++;
    if (parsed.notes.isNotEmpty) report.toReview++;
    report.lines.add('$name : ${parsed.code} · ${parsed.paragraphs.length} § '
        '${parsed.notes.isEmpty ? '' : '(à vérifier : ${parsed.notes.join(', ')})'}');
  }
}

class ParsedSermon {
  ParsedSermon(this.code, this.date, this.year, this.title, this.location, this.language, this.paragraphs, this.notes);
  final String code, title, language;
  final String? date, location;
  final int? year;
  final List<(int, String)> paragraphs;
  final List<String> notes;
}

/// Même logique que tools/import_sermons.py (à garder synchronisée).
class SermonParser {
  static final codeRe = RegExp(r'(?<!\d)(4[7-9]|5\d|6[0-5])-(\d{2})(\d{2})([MAESBX]?)(?!\d)');
  static final paraRe = RegExp(r'^(?:E-)?(\d{1,4})[\s.]+(?=\S)(.*)$');

  static const locationHints = [
    'USA', 'U.S.A', 'Etats-Unis', 'États-Unis', 'Canada', 'Californie', 'Indiana', 'Arizona', 'Illinois',
    'Ohio', 'Texas', 'Louisiane', 'Kentucky', 'Floride', 'Michigan', 'Minnesota', 'Oregon', 'Washington',
    'Colorado', 'Oklahoma', 'Arkansas', 'Géorgie', 'Tennessee', 'Caroline', 'Pennsylvanie', 'New York',
    'Afrique du Sud', 'Suisse', 'Allemagne', 'Norvège', 'Finlande', 'Inde', 'Jeffersonville', 'Phoenix',
    'Chicago', 'Los Angeles', 'Oakland', 'Tucson', 'Shreveport', 'Dallas', 'Houston', 'Denver',
  ];

  static const _stop = {
    'fr': {'le', 'la', 'les', 'et', 'de', 'des', 'que', 'qui', 'est', 'dans', 'il', 'nous', 'vous', 'pas', 'une', 'un', 'pour', 'sur', 'dieu'},
    'en': {'the', 'and', 'of', 'that', 'is', 'in', 'he', 'we', 'you', 'not', 'a', 'to', 'for', 'on', 'god', 'it'},
    'ln': {'na', 'ya', 'mpe', 'oyo', 'te', 'kaka', 'nzambe', 'bato', 'ezali', 'moto', 'ete', 'bongo', 'bino', 'biso', 'awa'},
  };

  static String norm(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  static String detectLanguage(String text) {
    final sample = text.length > 20000 ? text.substring(0, 20000) : text;
    final words = RegExp(r'[a-zà-ÿ]+').allMatches(sample.toLowerCase()).map((m) => m.group(0)!);
    final scores = {for (final k in _stop.keys) k: 0};
    for (final w in words) {
      for (final e in _stop.entries) {
        if (e.value.contains(w)) scores[e.key] = scores[e.key]! + 1;
      }
    }
    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 20 ? best.key : 'fr';
  }

  static (String?, String?) parseCode(String s) {
    final m = codeRe.firstMatch(s);
    if (m == null) return (null, null);
    final code = '${m[1]}-${m[2]}${m[3]}${m[4]}';
    final mm = int.parse(m[2]!), dd = int.parse(m[3]!);
    final date = (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) ? '19${m[1]}-${m[2]}-${m[3]}' : null;
    return (code, date);
  }

  static (List<String>, List<(int, String)>) split(String text) {
    final pre = <String>[];
    final paras = <List<Object>>[];
    var expected = 1;
    String? prevLine;
    for (final raw in text.replaceAll('\f', '\n').split('\n')) {
      final line = raw.trim();
      // numéro de page isolé
      if (RegExp(r'^\d{1,3}$').hasMatch(line) && (prevLine == null || prevLine.isEmpty)) {
        prevLine = line;
        continue;
      }
      prevLine = line;
      final m = paraRe.firstMatch(line);
      if (m != null) {
        final n = int.parse(m[1]!);
        if (n >= expected && n <= expected + 2) {
          paras.add([n, m[2]!.trim()]);
          expected = n + 1;
          continue;
        }
      }
      if (line.isEmpty) continue;
      if (paras.isNotEmpty) {
        final prev = paras.last[1] as String;
        paras.last[1] = (prev.endsWith('-') && !prev.endsWith(' -'))
            ? prev.substring(0, prev.length - 1) + line
            : '$prev $line'.trim();
      } else {
        pre.add(line);
      }
    }
    return (
      pre,
      [
        for (final e in paras)
          if ((e[1] as String).trim().isNotEmpty) (e[0] as int, (e[1] as String).split(RegExp(r'\s+')).join(' '))
      ]
    );
  }

  static ParsedSermon parse(String fileName, String text) {
    final notes = <String>[];
    final (pre, parasRaw) = split(text);
    var paras = parasRaw;
    var (code, date) = parseCode(fileName);
    if (code == null) (code, date) = parseCode(pre.take(30).join('\n'));
    if (code == null) (code, date) = parseCode(text.length > 2000 ? text.substring(0, 2000) : text);
    if (code == null) {
      notes.add('code officiel introuvable');
      code = 'SANS-CODE-${sha1.convert(utf8.encode(fileName)).toString().substring(0, 8)}';
    }
    var stem = p.basenameWithoutExtension(fileName)
        .replaceFirst(RegExp(r'^(FRN|FRE|FR|LIN|ENG)[\s_-]*', caseSensitive: false), '')
        .replaceAll(code, ' ')
        .replaceAll(RegExp(r'\b(VGR|VOG|PDF)\b', caseSensitive: false), ' ')
        .replaceAll('_', ' ')
        .replaceAll('-', ' - ')
        .split(RegExp(r'\s+'))
        .join(' ')
        .trim();
    while (stem.startsWith('-') || stem.endsWith('-')) {
      stem = stem.replaceAll(RegExp(r'^[\s-]+|[\s-]+$'), '');
    }
    var title = stem;
    if (title.length < 3 || RegExp(r'^[\d\s-]+$').hasMatch(title)) {
      title = pre.take(8).firstWhere(
          (l) => l.length >= 3 && l.length <= 90 && !codeRe.hasMatch(l) && !locationHints.any(l.contains),
          orElse: () => '');
      if (title.isEmpty) {
        notes.add('titre introuvable');
        title = fileName;
      }
    }
    String? location;
    final head = [...pre.take(20), ...(text.length > 3000 ? text.substring(0, 3000) : text).split('\n').take(20)];
    for (final l in head) {
      final t = l.trim();
      if (t.length > 4 && t.length < 90 && t.contains(',') && locationHints.any(t.contains)) {
        location = t.split(RegExp(r'\s+')).join(' ');
        break;
      }
    }
    if (location == null) notes.add('lieu introuvable');
    if (paras.isEmpty) {
      notes.add('aucun paragraphe numéroté reconnu');
      final body = text.split(RegExp(r'\s+')).join(' ').trim();
      paras = body.isEmpty ? [] : [(1, body)];
    } else {
      var gaps = 0;
      for (var i = 1; i < paras.length; i++) {
        if (paras[i].$1 != paras[i - 1].$1 + 1) gaps++;
      }
      if (gaps > 0) notes.add('numérotation discontinue ($gaps saut(s))');
    }
    final year = RegExp(r'^\d').hasMatch(code) ? int.parse('19${code.substring(0, 2)}') : null;
    return ParsedSermon(code, date, year, title, location, detectLanguage(text), paras, notes);
  }
}
