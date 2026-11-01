import 'package:sqlite3/sqlite3.dart';

class BibleBook {
  BibleBook(this.id, this.name, this.abbr, this.testament, this.chapters);
  final int id;
  final String name, abbr, testament;
  final int chapters;
  factory BibleBook.fromRow(Row r) => BibleBook(
      r['id'] as int, r['name'] as String, r['abbr'] as String, r['testament'] as String, r['chapters'] as int);
}

class Verse {
  Verse(this.id, this.book, this.chapter, this.verse, this.text);
  final int id, book, chapter, verse;
  final String text;
  factory Verse.fromRow(Row r) =>
      Verse(r['id'] as int, r['book'] as int, r['chapter'] as int, r['verse'] as int, r['text'] as String);
  String get key => '$book:$chapter:$verse';
}

class Sermon {
  Sermon({
    required this.id,
    required this.code,
    required this.language,
    required this.title,
    this.date,
    this.year,
    this.location,
    this.durationSec,
    this.series,
    this.audioUrl,
    this.audioCues = false,
    this.pdfName,
    this.source,
    this.paragraphCount = 0,
    this.translationStatus = 'original',
    this.needsReview = false,
    this.reviewNotes,
  });
  final int id;
  final String code, language, title;
  final String? date, location, series, audioUrl, pdfName, source, reviewNotes;
  final int? year, durationSec;
  final bool audioCues, needsReview;
  final int paragraphCount;
  final String translationStatus;

  bool get isAiTranslation => translationStatus == 'ia_non_validee';

  String get durationLabel {
    final d = durationSec;
    if (d == null) return '—';
    return '${d ~/ 3600}:${((d % 3600) ~/ 60).toString().padLeft(2, '0')}';
  }

  /// "Oakland, Californie, USA" -> "Oakland, Californie"
  String get shortLocation {
    final l = location ?? '';
    final parts = l.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length > 2 && (parts.last == 'USA' || parts.last == 'U.S.A.')) parts.removeLast();
    return parts.join(', ');
  }

  String get dateLabel {
    final d = date;
    if (d == null) return '';
    const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'];
    final parts = d.split('-');
    if (parts.length != 3) return d;
    final m = int.tryParse(parts[1]) ?? 0;
    if (m < 1 || m > 12) return d;
    return '${int.parse(parts[2])} ${months[m - 1]} ${parts[0]}';
  }

  factory Sermon.fromRow(Row r) => Sermon(
        id: r['id'] as int,
        code: r['code'] as String,
        language: r['language'] as String,
        title: r['title'] as String,
        date: r['date'] as String?,
        year: r['year'] as int?,
        location: r['location'] as String?,
        durationSec: r['duration_sec'] as int?,
        series: r['series'] as String?,
        audioUrl: r['audio_url'] as String?,
        audioCues: (r['audio_cues'] as int? ?? 0) == 1,
        pdfName: r['pdf_name'] as String?,
        source: r['source'] as String?,
        paragraphCount: r['paragraph_count'] as int? ?? 0,
        translationStatus: r['translation_status'] as String? ?? 'original',
        needsReview: (r['needs_review'] as int? ?? 0) == 1,
        reviewNotes: r['review_notes'] as String?,
      );
}

class Paragraph {
  Paragraph(this.id, this.sermonId, this.number, this.text, this.startMs);
  final int id, sermonId, number;
  final String text;
  final int? startMs;
  factory Paragraph.fromRow(Row r) => Paragraph(
      r['id'] as int, r['sermon_id'] as int, r['number'] as int, r['text'] as String, r['start_ms'] as int?);
}

enum SearchMode { words, exact, meaning }

enum HitKind { sermon, bible, note }

class SearchHit {
  SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.reference,
    required this.snippet,
    this.subtitle = '',
    this.sermonId,
    this.number,
    this.language,
  });
  final HitKind kind;

  /// id du paragraphe, du verset ou de la note
  final int id;
  final String title, reference, subtitle;

  /// Extrait avec les termes trouvés entourés de \u0001 ... \u0002
  final String snippet;
  final int? sermonId, number;
  final String? language;
}

class Note {
  Note(this.id, this.title, this.body, this.refType, this.refKey, this.refLabel, this.collection, this.updatedAt);
  final int id;
  final String title, body, updatedAt;
  final String? refType, refKey, refLabel, collection;
  factory Note.fromRow(Row r) => Note(r['id'] as int, r['title'] as String, r['body'] as String,
      r['ref_type'] as String?, r['ref_key'] as String?, r['ref_label'] as String?,
      r['collection'] as String?, r['updated_at'] as String);
}

class Favorite {
  Favorite(this.refType, this.refKey, this.label, this.excerpt, this.collection);
  final String refType, refKey, label;
  final String? excerpt, collection;
  factory Favorite.fromRow(Row r) => Favorite(r['ref_type'] as String, r['ref_key'] as String,
      r['label'] as String, r['excerpt'] as String?, r['collection'] as String?);
}
