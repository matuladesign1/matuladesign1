import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';

/// Une lecture du jour : soit des chapitres bibliques, soit une prédication.
class Reading {
  Reading.bible(this.book, this.chapter, this.label) : sermonCode = null;
  Reading.sermon(String code, this.label)
      : sermonCode = code,
        book = 0,
        chapter = 0;
  final int book, chapter;
  final String? sermonCode;
  final String label;
}

class PlanDef {
  PlanDef(this.id, this.title, this.description, this.days, this.palette, {this.series});
  final String id, title, description;

  /// Lectures par jour (index 0 = jour 1).
  final List<List<Reading>> days;
  final int palette;

  /// Pour les plans d'étude d'une série de sermons.
  final String? series;
}

class PlanState {
  PlanState(this.startedAt, this.paused, this.lastReadAt, this.done);
  final String startedAt;
  final bool paused;
  final String? lastReadAt;
  final Set<int> done;
}

/// Plans de lecture, générés à partir de la Bible embarquée et des séries importées.
class Plans extends ChangeNotifier {
  Plans(this.adb) {
    _build();
  }
  final AppDb adb;
  late List<PlanDef> all;

  static const studySeries = [
    'La Révélation des Sept Sceaux',
    'Les Sept Âges de l\'Église',
    'Exposé des Sept Âges de l\'Église',
  ];

  void _build() {
    final books = adb.books();
    List<Reading> chapters(Iterable<int> bookIds) => [
          for (final b in books.where((b) => bookIds.contains(b.id)))
            for (var c = 1; c <= b.chapters; c++) Reading.bible(b.id, c, '${b.name} $c')
        ];
    List<List<Reading>> spread(List<Reading> items, int days) {
      final out = <List<Reading>>[];
      for (var d = 0; d < days; d++) {
        final from = (items.length * d / days).floor();
        final to = (items.length * (d + 1) / days).floor();
        out.add(items.sublist(from, to));
      }
      return out;
    }

    all = [
      PlanDef('bible-1an', 'Lire toute la Bible en un an',
          'Les 66 livres, de la Genèse à l\'Apocalypse, environ 3 à 4 chapitres par jour.',
          spread(chapters(List.generate(66, (i) => i + 1)), 365), 0),
      PlanDef('nt-90', 'Le Nouveau Testament en 90 jours',
          'De Matthieu à l\'Apocalypse, environ 3 chapitres par jour.',
          spread(chapters(List.generate(27, (i) => i + 40)), 90), 1),
      PlanDef('psaumes-30', 'Lire les Psaumes', 'Les 150 psaumes en 30 jours, 5 psaumes par jour.',
          spread(chapters([19]), 30), 2),
      PlanDef('proverbes-31', 'Lire les Proverbes', 'Un chapitre des Proverbes chaque jour du mois.',
          spread(chapters([20]), 31), 3),
    ];
    for (final (i, s) in studySeries.indexed) {
      final sermons = adb.sermons(series: s, kind: null);
      final seen = <String>{};
      final days = <List<Reading>>[
        for (final ser in sermons)
          if (seen.add(ser.code)) [Reading.sermon(ser.code, '${ser.code} · ${ser.title}')]
      ];
      all.add(PlanDef('serie-$i', 'Étudier : $s',
          days.isEmpty
              ? 'Importez les prédications de cette série pour activer ce plan.'
              : 'Une prédication par jour, dans l\'ordre chronologique.',
          days, 4 + i, series: s));
    }
    // Plans personnalisés : un par série importée qui n'est pas déjà couverte.
    for (final s in adb.seriesCounts().keys.where((s) => !studySeries.contains(s))) {
      final seen = <String>{};
      final days = <List<Reading>>[
        for (final ser in adb.sermons(series: s, kind: null))
          if (seen.add(ser.code)) [Reading.sermon(ser.code, '${ser.code} · ${ser.title}')]
      ];
      all.add(PlanDef('serie-${s.hashCode}', 'Étudier : $s', 'Une prédication par jour.', days, 7, series: s));
    }
  }

  void refresh() {
    _build();
    notifyListeners();
  }

  PlanDef byId(String id) => all.firstWhere((p) => p.id == id);

  PlanState? state(String id) {
    final r = adb.db.select('SELECT * FROM plan_state WHERE plan_id=?', [id]).firstOrNull;
    if (r == null) return null;
    final done = adb.db
        .select('SELECT day FROM plan_progress WHERE plan_id=?', [id])
        .map((e) => e['day'] as int)
        .toSet();
    return PlanState(r['started_at'] as String, (r['paused'] as int) == 1, r['last_read_at'] as String?, done);
  }

  List<PlanDef> mine() => all.where((p) => state(p.id) != null).toList();

  void start(String id) {
    adb.db.execute('INSERT OR IGNORE INTO plan_state(plan_id, started_at) VALUES(?,?)', [id, nowIso()]);
    adb.db.execute('UPDATE plan_state SET paused=0 WHERE plan_id=?', [id]);
    notifyListeners();
  }

  void pause(String id, bool paused) {
    adb.db.execute('UPDATE plan_state SET paused=? WHERE plan_id=?', [paused ? 1 : 0, id]);
    notifyListeners();
  }

  void stop(String id) {
    adb.db.execute('DELETE FROM plan_state WHERE plan_id=?', [id]);
    adb.db.execute('DELETE FROM plan_progress WHERE plan_id=?', [id]);
    notifyListeners();
  }

  void toggleDay(String id, int day) {
    final exists = adb.db.select('SELECT 1 FROM plan_progress WHERE plan_id=? AND day=?', [id, day]).isNotEmpty;
    if (exists) {
      adb.db.execute('DELETE FROM plan_progress WHERE plan_id=? AND day=?', [id, day]);
    } else {
      adb.db.execute('INSERT INTO plan_progress VALUES(?,?,?)', [id, day, nowIso()]);
      adb.db.execute('UPDATE plan_state SET last_read_at=? WHERE plan_id=?', [nowIso(), id]);
    }
    notifyListeners();
  }

  int completedPlans() {
    var n = 0;
    for (final p in mine()) {
      final s = state(p.id)!;
      if (p.days.isNotEmpty && s.done.length >= p.days.length) n++;
    }
    return n;
  }

  /// Retrouve le sermon (version française de préférence) d'une lecture.
  Sermon? sermonFor(Reading r) =>
      r.sermonCode == null ? null : (adb.sermonVersion(r.sermonCode!, 'fr') ?? adb.sermons(filter: r.sermonCode!, kind: null).firstOrNull);
}
