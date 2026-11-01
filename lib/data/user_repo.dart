import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';

/// Données personnelles : notes, favoris, surlignages, historique, activité.
/// Tout est sauvegardé immédiatement dans la base locale.
class UserRepo extends ChangeNotifier {
  UserRepo(this.adb) {
    markActiveToday();
  }
  final AppDb adb;

  // ------------------------------------------------------------ activité
  void markActiveToday() {
    final d = DateTime.now().toIso8601String().substring(0, 10);
    adb.db.execute('INSERT OR IGNORE INTO activity VALUES(?)', [d]);
  }

  /// Nombre de jours consécutifs d'activité, jusqu'à aujourd'hui.
  int streak() {
    final days = adb.db
        .select('SELECT day FROM activity ORDER BY day DESC LIMIT 400')
        .map((r) => DateTime.parse(r['day'] as String))
        .toList();
    if (days.isEmpty) return 0;
    var n = 0;
    var expected = DateTime.now();
    expected = DateTime(expected.year, expected.month, expected.day);
    for (final d in days) {
      if (d == expected) {
        n++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (d.isBefore(expected)) {
        break;
      }
    }
    return n;
  }

  int totalActiveDays() => adb.db.select('SELECT count(*) c FROM activity').first['c'] as int;

  static const badges = [3, 7, 30, 100, 365];

  int? nextBadge() {
    final s = streak();
    for (final b in badges) {
      if (s < b) return b;
    }
    return null;
  }

  List<int> earnedBadges() {
    final best = _bestStreak();
    return badges.where((b) => best >= b).toList();
  }

  int _bestStreak() {
    final days = adb.db.select('SELECT day FROM activity ORDER BY day').map((r) => DateTime.parse(r['day'] as String)).toList();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in days) {
      cur = (prev != null && d.difference(prev).inDays == 1) ? cur + 1 : 1;
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  // ------------------------------------------------------------ historique
  void visit(String type, String key, String label, {int position = 0}) {
    adb.db.execute('INSERT OR REPLACE INTO history VALUES(?,?,?,?,?)', [type, key, label, position, nowIso()]);
    // Notification différée : visit() est appelé pendant la construction/fermeture des écrans.
    Future.microtask(notifyListeners);
  }

  ({String key, String label, int position})? last(String type) {
    final r = adb.db
        .select('SELECT ref_key, label, position FROM history WHERE ref_type=? ORDER BY ts DESC LIMIT 1', [type])
        .firstOrNull;
    if (r == null) return null;
    return (key: r['ref_key'] as String, label: r['label'] as String, position: r['position'] as int);
  }

  List<({String type, String key, String label, String ts})> history({int limit = 100}) => adb.db
      .select('SELECT ref_type, ref_key, label, ts FROM history ORDER BY ts DESC LIMIT ?', [limit])
      .map((r) => (
            type: r['ref_type'] as String,
            key: r['ref_key'] as String,
            label: r['label'] as String,
            ts: r['ts'] as String
          ))
      .toList();

  void clearHistory() {
    adb.db.execute('DELETE FROM history');
    notifyListeners();
  }

  int countHistory(String type) =>
      adb.db.select('SELECT count(*) c FROM history WHERE ref_type=?', [type]).first['c'] as int;

  // ------------------------------------------------------------ favoris
  bool isFavorite(String type, String key) =>
      adb.db.select('SELECT 1 FROM favorites WHERE ref_type=? AND ref_key=?', [type, key]).isNotEmpty;

  void toggleFavorite(String type, String key, String label, {String? excerpt}) {
    if (isFavorite(type, key)) {
      adb.db.execute('DELETE FROM favorites WHERE ref_type=? AND ref_key=?', [type, key]);
    } else {
      adb.db.execute('INSERT INTO favorites(ref_type, ref_key, label, excerpt, created_at) VALUES(?,?,?,?,?)',
          [type, key, label, excerpt, nowIso()]);
    }
    notifyListeners();
  }

  void setFavoriteCollection(Favorite f, String? collection) {
    adb.db.execute('UPDATE favorites SET collection=? WHERE ref_type=? AND ref_key=?',
        [collection, f.refType, f.refKey]);
    notifyListeners();
  }

  List<Favorite> favorites({String? type, int limit = 500}) => adb.db
      .select(
          'SELECT ref_type, ref_key, label, excerpt, collection FROM favorites '
          '${type == null ? '' : 'WHERE ref_type=?'} ORDER BY created_at DESC LIMIT ?',
          [if (type != null) type, limit])
      .map(Favorite.fromRow)
      .toList();

  // ------------------------------------------------------------ surlignages
  /// Couleurs proposées (or, bleu clair, vert, rose).
  static const highlightColors = [0xFFE6B63E, 0xFF78B7F0, 0xFF7FD1A8, 0xFFF29CB8];

  Map<String, int> highlights(String type, String keyPrefix) => {
        for (final r in adb.db.select(
            'SELECT ref_key, color FROM highlights WHERE ref_type=? AND ref_key LIKE ?', [type, '$keyPrefix%']))
          r['ref_key'] as String: r['color'] as int
      };

  void setHighlight(String type, String key, int? color) {
    if (color == null) {
      adb.db.execute('DELETE FROM highlights WHERE ref_type=? AND ref_key=?', [type, key]);
    } else {
      adb.db.execute('INSERT OR REPLACE INTO highlights VALUES(?,?,?,?)', [type, key, color, nowIso()]);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ notes
  List<Note> notes({String? refType, String? refKey}) => adb.db
      .select(
          'SELECT * FROM notes ${refKey != null ? 'WHERE ref_type=? AND ref_key=?' : ''} ORDER BY updated_at DESC',
          [if (refKey != null) ...[refType, refKey]])
      .map(Note.fromRow)
      .toList();

  Set<String> notedKeys(String type, String keyPrefix) => adb.db
      .select('SELECT ref_key FROM notes WHERE ref_type=? AND ref_key LIKE ?', [type, '$keyPrefix%'])
      .map((r) => r['ref_key'] as String)
      .toSet();

  int saveNote({int? id, required String title, required String body, String? refType, String? refKey,
      String? refLabel, String? collection}) {
    final now = nowIso();
    if (id == null) {
      adb.db.execute(
          'INSERT INTO notes(title, body, ref_type, ref_key, ref_label, collection, created_at, updated_at) '
          'VALUES(?,?,?,?,?,?,?,?)',
          [title, body, refType, refKey, refLabel, collection, now, now]);
      id = adb.db.lastInsertRowId;
    } else {
      adb.db.execute('UPDATE notes SET title=?, body=?, collection=?, updated_at=? WHERE id=?',
          [title, body, collection, now, id]);
    }
    notifyListeners();
    return id;
  }

  void deleteNote(int id) {
    adb.db.execute('DELETE FROM notes WHERE id=?', [id]);
    notifyListeners();
  }

  int countNotes() => adb.db.select('SELECT count(*) c FROM notes').first['c'] as int;

  /// Exporte toutes les données personnelles (sauvegarde / partage).
  String exportNotesText() {
    final b = StringBuffer('Mes notes — Sermons de Branham Matomate\n\n');
    for (final n in notes()) {
      b.writeln('■ ${n.title.isEmpty ? 'Sans titre' : n.title}');
      if (n.refLabel != null) b.writeln('  (${n.refLabel})');
      b.writeln(n.body);
      b.writeln();
    }
    return b.toString();
  }
}
