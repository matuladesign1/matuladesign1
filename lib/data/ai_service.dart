import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/settings.dart';
import 'db.dart';
import 'models.dart';
import 'search_service.dart';

class AiAnswer {
  AiAnswer(this.text, this.sources, {this.offline = false, this.error});

  /// Synthèse rédigée par l'IA (vide en mode local). Les citations [1], [2]…
  /// renvoient à [sources].
  final String text;
  final List<SearchHit> sources;
  final bool offline;
  final String? error;
}

class AiUnavailable implements Exception {
  AiUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Assistant « Le Message et la Bible ».
///
/// Fonctionnement (RAG) : 1) recherche réelle dans la base locale ;
/// 2) si un serveur est configuré, envoi de la question et des passages
/// trouvés à la fonction serveur, qui interroge OpenAI avec une consigne
/// stricte (ne répondre qu'à partir des passages, citer chaque affirmation).
/// La clé OpenAI ne quitte jamais le serveur.
class AiService {
  AiService(this.settings, this.search, this.adb);
  final Settings settings;
  final SearchService search;
  final AppDb adb;

  Uri _endpoint() => Uri.parse('${settings.serverUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/assistant');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.serverKey}',
        'apikey': settings.serverKey,
      };

  Future<Map<String, dynamic>> _call(Map<String, Object?> body) async {
    if (!settings.hasServer) throw AiUnavailable('Serveur IA non configuré (Paramètres > Assistant IA).');
    try {
      final r = await http
          .post(_endpoint(), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) {
        throw AiUnavailable('Le serveur IA a répondu ${r.statusCode} : ${utf8.decode(r.bodyBytes)}');
      }
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } on SocketException {
      throw AiUnavailable('Connexion Internet nécessaire pour l\'assistant IA.');
    } on HttpException catch (e) {
      throw AiUnavailable('Erreur réseau : ${e.message}');
    }
  }

  /// Recherche des passages pour une question en langage naturel.
  List<SearchHit> retrieve(String question, {int limit = 12}) {
    // Une expression entre guillemets dans la question = recherche exacte.
    final quoted = RegExp(r'[«"]\s*([^»"]+?)\s*[»"]').firstMatch(question);
    if (quoted != null) {
      final exact = search.search(quoted[1]!, SearchMode.exact, limit: limit, scope: const SearchScope(titles: false));
      if (exact.hits.isNotEmpty) return exact.hits;
    }
    final words = search.search(question, SearchMode.words, limit: limit, scope: const SearchScope(titles: false));
    if (words.hits.length >= 3) return words.hits;
    return search.search(question, SearchMode.meaning, limit: limit, scope: const SearchScope(titles: false)).hits;
  }

  Future<AiAnswer> ask(String question) async {
    var sources = retrieve(question);
    if (settings.hasServer) {
      try {
        final semantic = await _call({'action': 'semantic', 'query': question, 'limit': 8});
        final extra = _hitsFromServer(semantic['matches'] as List? ?? const []);
        final ids = sources.where((h) => h.kind == HitKind.sermon).map((h) => h.id).toSet();
        sources = [...sources, ...extra.where((h) => !ids.contains(h.id))].take(16).toList();
      } catch (_) {
        // la recherche sémantique serveur est facultative
      }
    }
    if (sources.isEmpty) return AiAnswer('', const [], offline: !settings.hasServer);
    if (!settings.hasServer) return AiAnswer('', sources, offline: true);
    try {
      final res = await _call({
        'action': 'ask',
        'question': question,
        'passages': [
          for (final (i, h) in sources.indexed)
            {
              'n': i + 1,
              'kind': h.kind.name,
              'title': h.title,
              'reference': h.reference,
              'text': _fullText(h),
            }
        ],
      });
      return AiAnswer(res['answer'] as String? ?? '', sources);
    } on AiUnavailable catch (e) {
      return AiAnswer('', sources, offline: true, error: e.message);
    }
  }

  String _fullText(SearchHit h) {
    if (h.kind == HitKind.sermon) {
      return adb.db.select('SELECT text FROM paragraphs WHERE id=?', [h.id]).first['text'] as String;
    }
    if (h.kind == HitKind.bible) return adb.verseById(h.id)?.text ?? h.snippet;
    return h.snippet.replaceAll('\u0001', '').replaceAll('\u0002', '');
  }

  List<SearchHit> _hitsFromServer(List matches) {
    final out = <SearchHit>[];
    for (final m in matches.cast<Map>()) {
      // Le serveur renvoie code + langue + numéro ; on relit le texte localement
      // pour ne jamais afficher un passage absent de la bibliothèque.
      final r = adb.db.select(
          'SELECT p.id, p.sermon_id, p.number, p.text, s.title, s.code, s.location, s.date, s.language '
          'FROM paragraphs p JOIN sermons s ON s.id=p.sermon_id WHERE s.code=? AND s.language=? AND p.number=?',
          [m['code'], m['language'], m['number']]).firstOrNull;
      if (r == null) continue;
      final text = r['text'] as String;
      out.add(SearchHit(
        kind: HitKind.sermon,
        id: r['id'] as int,
        sermonId: r['sermon_id'] as int,
        number: r['number'] as int,
        language: r['language'] as String,
        title: r['title'] as String,
        reference: '${r['code']} · ¶${r['number']}',
        subtitle: [r['location'] ?? '', r['date'] ?? ''].where((e) => '$e'.isNotEmpty).join(' · '),
        snippet: text.length > 320 ? '${text.substring(0, 320)}…' : text,
      ));
    }
    return out;
  }

  /// Recherche « Sens » par vecteurs (serveur). Lève [AiUnavailable] sans serveur.
  Future<List<SearchHit>> semantic(String query, {int limit = 30}) async {
    final res = await _call({'action': 'semantic', 'query': query, 'limit': limit});
    return _hitsFromServer(res['matches'] as List? ?? const []);
  }

  /// Traduction en lingala d'un sermon, paragraphe par paragraphe (numéros conservés).
  /// Le résultat est enregistré comme version « ia_non_validee ».
  Future<int> translateSermonToLingala(Sermon s, {void Function(int done, int total)? onProgress}) async {
    final paras = adb.paragraphs(s.id);
    final out = <(int, String)>[];
    const batch = 12;
    for (var i = 0; i < paras.length; i += batch) {
      final chunk = paras.sublist(i, i + batch > paras.length ? paras.length : i + batch);
      final res = await _call({
        'action': 'translate',
        'target': 'ln',
        'paragraphs': [for (final p in chunk) {'n': p.number, 'text': p.text}],
      });
      final map = {for (final t in (res['paragraphs'] as List).cast<Map>()) t['n'] as int: t['text'] as String};
      for (final p in chunk) {
        final t = map[p.number];
        if (t == null || t.trim().isEmpty) throw AiUnavailable('Paragraphe ${p.number} non traduit : traduction annulée.');
        out.add((p.number, t.trim()));
      }
      onProgress?.call(out.length, paras.length);
    }
    adb.db.execute('BEGIN');
    try {
      adb.db.execute("DELETE FROM sermons WHERE code=? AND language='ln' AND translation_status='ia_non_validee'",
          [s.code]);
      adb.db.execute(
          "INSERT INTO sermons(code,language,title,date,year,location,duration_sec,series,audio_url,source,"
          "paragraph_count,translation_status) VALUES(?,?,?,?,?,?,?,?,?,?,?,'ia_non_validee')",
          [s.code, 'ln', s.title, s.date, s.year, s.location, s.durationSec, s.series, s.audioUrl,
            'Traduction automatique IA de ${s.code} (${s.language}) — à valider', out.length]);
      final id = adb.db.lastInsertRowId;
      final st = adb.db.prepare('INSERT INTO paragraphs(sermon_id, number, text) VALUES(?,?,?)');
      for (final (n, t) in out) {
        st.execute([id, n, t]);
      }
      st.dispose();
      adb.db.execute('COMMIT');
      return id;
    } catch (_) {
      adb.db.execute('ROLLBACK');
      rethrow;
    }
  }
}
