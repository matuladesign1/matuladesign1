import 'dart:math' as math;

import 'db.dart';
import 'models.dart';

/// Portée d'une recherche.
class SearchScope {
  const SearchScope({this.sermons = true, this.bible = true, this.notes = false, this.sermonId});
  final bool sermons, bible, notes;

  /// Limite la recherche à un seul sermon (onglet « CELLE-CI »).
  final int? sermonId;

  static const all = SearchScope();
}

class SearchPage {
  SearchPage(this.hits, this.total, {this.suggestion, this.approximate = false});
  final List<SearchHit> hits;
  final int total;

  /// Proposition de correction quand aucun résultat n'est trouvé.
  final String? suggestion;

  /// Vrai pour le mode « Sens » hors ligne (classement par pertinence lexicale).
  final bool approximate;
}

/// Moteur de recherche plein texte (SQLite FTS5, insensible aux accents et à la casse).
class SearchService {
  SearchService(this.adb) {
    adb.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS temp.pvocab USING fts5vocab(main, paragraphs_fts, 'row')");
    adb.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS temp.bvocab USING fts5vocab(bible, verses_fts, 'row')");
  }
  final AppDb adb;

  static final _tokenRe = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  static const _stop = {
    'le', 'la', 'les', 'l', 'un', 'une', 'des', 'de', 'du', 'd', 'et', 'ou', 'a', 'au', 'aux',
    'en', 'dans', 'sur', 'pour', 'par', 'que', 'qui', 'quoi', 'ce', 'cet', 'cette', 'ces',
    'est', 'il', 'elle', 'ils', 'on', 'nous', 'vous', 'je', 'tu', 'se', 's', 'ne', 'pas',
    'plus', 'son', 'sa', 'ses', 'leur', 'leurs', 'mon', 'ma', 'mes', 'y', 'dit', 'dire',
    'parle', 'parler', 'quel', 'quels', 'quelle', 'quelles', 'ou', 'comment', 'pourquoi',
    'branham', 'sermon', 'sermons', 'predication', 'predications', 'passage', 'passages',
    'trouve', 'trouver', 'montre', 'moi', 'tous', 'toutes', 'explique', 'expliquer',
  };

  /// Quelques équivalences doctrinales pour le mode « Sens » hors ligne.
  static const _related = <String, List<String>>{
    'retour': ['venue', 'avenement', 'enlevement', 'revient'],
    'jesus': ['christ', 'seigneur', 'fils'],
    'christ': ['jesus', 'seigneur', 'messie'],
    'foi': ['croire', 'croyance', 'assurance'],
    'bapteme': ['baptiser', 'baptise', 'immersion'],
    'saint': ['esprit', 'sanctification'],
    'esprit': ['saint', 'onction'],
    'colombe': ['esprit', 'agneau'],
    'aigle': ['prophete', 'aiglon', 'aiglons'],
    'epouse': ['eglise', 'elue'],
    'eglise': ['epouse', 'assemblee'],
    'fin': ['derniers', 'jours', 'temps'],
    'nouvelle': ['naissance', 'naitre', 'ne'],
    'naissance': ['naitre', 'nouvelle', 'regeneration'],
    'guerison': ['gueri', 'guerir', 'malade'],
    'sceaux': ['sceau', 'mystere', 'apocalypse'],
    'priere': ['prier', 'prie'],
    'parole': ['ecriture', 'ecritures', 'verbe'],
  };

  static String fold(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  static List<String> tokens(String q) => _tokenRe.allMatches(fold(q)).map((m) => m.group(0)!).toList();

  /// Construit l'expression FTS5. Retourne null si la requête est vide.
  static String? buildMatch(String query, SearchMode mode, {bool prefixLast = false}) {
    final t = tokens(query);
    if (t.isEmpty) return null;
    switch (mode) {
      case SearchMode.exact:
        return '"${t.join(' ')}"';
      case SearchMode.words:
        final parts = [for (var i = 0; i < t.length; i++) (prefixLast && i == t.length - 1) ? '"${t[i]}"*' : '"${t[i]}"'];
        return parts.join(' ');
      case SearchMode.meaning:
        final kept = t.where((w) => !_stop.contains(w) && w.length > 1).toList();
        final base = kept.isEmpty ? t : kept;
        final terms = <String>{};
        for (final w in base) {
          terms.add(_stem(w));
          for (final r in _related[w] ?? const <String>[]) {
            terms.add(_stem(r));
          }
        }
        return terms.join(' OR ');
    }
  }

  static String _stem(String w) {
    if (w.length >= 7) return '"${w.substring(0, w.length - 2)}"*';
    if (w.length >= 4) return '"$w"*';
    return '"$w"';
  }

  int _count(String sql, List<Object?> args) => adb.db.select(sql, args).first['c'] as int;

  SearchPage search(String query, SearchMode mode,
      {SearchScope scope = SearchScope.all, int offset = 0, int limit = 30, bool live = false}) {
    final match = buildMatch(query, mode, prefixLast: live && mode == SearchMode.words);
    if (match == null) return SearchPage(const [], 0);

    final sermonFilter = scope.sermonId != null ? ' AND p.sermon_id = ${scope.sermonId}' : '';
    final order = scope.sermonId != null && mode != SearchMode.meaning ? 'p.number' : 'bm25(paragraphs_fts)';

    final nS = scope.sermons
        ? _count(
            'SELECT count(*) c FROM paragraphs_fts JOIN paragraphs p ON p.id=paragraphs_fts.rowid '
            'WHERE paragraphs_fts MATCH ?$sermonFilter',
            [match])
        : 0;
    final doBible = scope.bible && scope.sermonId == null;
    final nB = doBible ? _count('SELECT count(*) c FROM bible.verses_fts WHERE verses_fts MATCH ?', [match]) : 0;
    final doNotes = scope.notes && scope.sermonId == null;
    final nN = doNotes ? _count('SELECT count(*) c FROM notes_fts WHERE notes_fts MATCH ?', [match]) : 0;

    final hits = <SearchHit>[];
    var off = offset;
    var left = limit;

    if (left > 0 && off < nS) {
      final rows = adb.db.select(
          "SELECT p.id, p.sermon_id, p.number, s.title, s.code, s.date, s.location, s.language, "
          "snippet(paragraphs_fts, 0, char(1), char(2), '…', 48) snip "
          'FROM paragraphs_fts JOIN paragraphs p ON p.id=paragraphs_fts.rowid '
          'JOIN sermons s ON s.id=p.sermon_id '
          'WHERE paragraphs_fts MATCH ?$sermonFilter ORDER BY $order LIMIT ? OFFSET ?',
          [match, left, off]);
      for (final r in rows) {
        final loc = (r['location'] as String?) ?? '';
        hits.add(SearchHit(
          kind: HitKind.sermon,
          id: r['id'] as int,
          sermonId: r['sermon_id'] as int,
          number: r['number'] as int,
          language: r['language'] as String,
          title: r['title'] as String,
          reference: '${r['code']} · ¶${r['number']}',
          subtitle: [loc, r['date'] ?? ''].where((e) => '$e'.isNotEmpty).join(' · '),
          snippet: r['snip'] as String,
        ));
      }
      left -= rows.length;
      off = 0;
    } else {
      off -= nS;
    }

    if (left > 0 && doBible && off < nB) {
      final rows = adb.db.select(
          "SELECT v.id, v.book, v.chapter, v.verse, v.version, b.name, "
          "snippet(verses_fts, 0, char(1), char(2), '…', 48) snip "
          'FROM bible.verses_fts JOIN bible.verses v ON v.id=verses_fts.rowid '
          'JOIN bible.books b ON b.id=v.book '
          'WHERE verses_fts MATCH ? ORDER BY bm25(verses_fts) LIMIT ? OFFSET ?',
          [match, left, off]);
      for (final r in rows) {
        hits.add(SearchHit(
          kind: HitKind.bible,
          id: r['id'] as int,
          title: '${r['name']} ${r['chapter']}:${r['verse']}',
          reference: r['version'] as String,
          subtitle: 'Bible',
          snippet: r['snip'] as String,
        ));
      }
      left -= rows.length;
      off = 0;
    } else if (doBible) {
      off -= nB;
    }

    if (left > 0 && doNotes && off < nN) {
      final rows = adb.db.select(
          "SELECT n.id, n.title, snippet(notes_fts, 1, char(1), char(2), '…', 32) snip "
          'FROM notes_fts JOIN notes n ON n.id=notes_fts.rowid WHERE notes_fts MATCH ? '
          'ORDER BY bm25(notes_fts) LIMIT ? OFFSET ?',
          [match, left, off]);
      for (final r in rows) {
        hits.add(SearchHit(
            kind: HitKind.note,
            id: r['id'] as int,
            title: (r['title'] as String).isEmpty ? 'Note' : r['title'] as String,
            reference: 'Note personnelle',
            snippet: r['snip'] as String));
      }
    }

    final total = nS + nB + nN;
    String? suggestion;
    if (total == 0 && offset == 0 && mode != SearchMode.meaning) suggestion = suggest(query);
    return SearchPage(hits, total, suggestion: suggestion, approximate: mode == SearchMode.meaning);
  }

  /// Correction des fautes simples : remplace chaque mot inconnu par le terme
  /// indexé le plus fréquent à une distance d'édition de 1 (ou 2 pour les mots longs).
  String? suggest(String query) {
    final t = tokens(query);
    var changed = false;
    final out = <String>[];
    for (final w in t) {
      final known = adb.db.select(
          'SELECT (SELECT count(*) FROM temp.pvocab WHERE term=?) + (SELECT count(*) FROM temp.bvocab WHERE term=?) c',
          [w, w]).first['c'] as int;
      if (known > 0 || w.length < 3) {
        out.add(w);
        continue;
      }
      final prefix = w.substring(0, 1);
      final cands = adb.db.select(
          'SELECT term, sum(doc) d FROM (SELECT term, doc FROM temp.pvocab WHERE term >= ? AND term < ? '
          'UNION ALL SELECT term, doc FROM temp.bvocab WHERE term >= ? AND term < ?) '
          'WHERE length(term) BETWEEN ? AND ? GROUP BY term',
          [prefix, '$prefix￿', prefix, '$prefix￿', w.length - 2, w.length + 2]);
      final maxDist = w.length >= 7 ? 2 : 1;
      String? best;
      var bestScore = -1;
      for (final c in cands) {
        final term = c['term'] as String;
        final d = _lev(w, term, maxDist);
        if (d <= maxDist) {
          final score = (c['d'] as int) * (maxDist - d + 1);
          if (score > bestScore) {
            bestScore = score;
            best = term;
          }
        }
      }
      if (best != null) {
        out.add(best);
        changed = true;
      } else {
        out.add(w);
      }
    }
    return changed ? out.join(' ') : null;
  }

  static int _lev(String a, String b, int cap) {
    if ((a.length - b.length).abs() > cap) return cap + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
        rowMin = math.min(rowMin, cur[j]);
      }
      if (rowMin > cap) return cap + 1;
      prev = cur;
    }
    return prev[b.length];
  }

  /// Suggestions pendant la saisie : termes de l'index commençant par le dernier mot.
  List<String> completions(String query) {
    final t = tokens(query);
    if (t.isEmpty || t.last.length < 2) return const [];
    final last = t.last;
    final head = t.sublist(0, t.length - 1).join(' ');
    return adb.db
        .select(
            'SELECT term, sum(doc) d FROM (SELECT term, doc FROM temp.pvocab WHERE term >= ? AND term < ? '
            'UNION ALL SELECT term, doc FROM temp.bvocab WHERE term >= ? AND term < ?) '
            'GROUP BY term ORDER BY d DESC LIMIT 6',
            [last, '$last￿', last, '$last￿'])
        .map((r) => head.isEmpty ? r['term'] as String : '$head ${r['term']}')
        .toList();
  }

  /// Paragraphes voisins d'un résultat (contexte avant/après).
  ({String? before, String? after}) context(int sermonId, int number) {
    String? get(int n) => adb.db
        .select('SELECT text FROM paragraphs WHERE sermon_id=? AND number=?', [sermonId, n])
        .firstOrNull?['text'] as String?;
    return (before: get(number - 1), after: get(number + 1));
  }

  // --------------------------------------------------------- historique
  void remember(String query, SearchMode mode) {
    if (query.trim().isEmpty) return;
    adb.db.execute('INSERT OR REPLACE INTO search_history VALUES(?,?,?)', [query.trim(), mode.name, nowIso()]);
  }

  List<({String query, SearchMode mode})> recent({int limit = 15}) => adb.db
      .select('SELECT query, mode FROM search_history ORDER BY ts DESC LIMIT ?', [limit])
      .map((r) => (query: r['query'] as String, mode: SearchMode.values.byName(r['mode'] as String)))
      .toList();

  void clearHistory() => adb.db.execute('DELETE FROM search_history');
}
