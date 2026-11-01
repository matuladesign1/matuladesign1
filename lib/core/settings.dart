import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// Préférences de l'utilisateur, persistées localement.
class Settings extends ChangeNotifier {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  ThemeMode get themeMode => ThemeMode.values[_p.getInt('theme') ?? ThemeMode.dark.index];
  set themeMode(ThemeMode m) => _set(() => _p.setInt('theme', m.index));

  String get lang => _p.getString('lang') ?? 'fr';
  set lang(String v) => _set(() => _p.setString('lang', v));
  S get s => S(lang);

  double get textScale => _p.getDouble('textScale') ?? 1.0;
  set textScale(double v) => _set(() => _p.setDouble('textScale', v));

  String get userName => _p.getString('userName') ?? '';
  set userName(String v) => _set(() => _p.setString('userName', v));

  String get userEmail => _p.getString('userEmail') ?? '';
  set userEmail(String v) => _set(() => _p.setString('userEmail', v));

  String get joinedAt {
    var v = _p.getString('joinedAt');
    if (v == null) {
      v = DateTime.now().toIso8601String().substring(0, 10);
      _p.setString('joinedAt', v);
    }
    return v;
  }

  bool get notifyVerse => _p.getBool('notifyVerse') ?? false;
  set notifyVerse(bool v) => _set(() => _p.setBool('notifyVerse', v));
  bool get notifyReading => _p.getBool('notifyReading') ?? false;
  set notifyReading(bool v) => _set(() => _p.setBool('notifyReading', v));
  bool get searchNotes => _p.getBool('searchNotes') ?? false;
  set searchNotes(bool v) => _set(() => _p.setBool('searchNotes', v));

  /// Serveur IA (Supabase). Les clés OpenAI restent côté serveur.
  /// Valeurs par défaut injectables à la compilation :
  /// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  String get serverUrl =>
      _p.getString('serverUrl') ?? const String.fromEnvironment('SUPABASE_URL');
  set serverUrl(String v) => _set(() => _p.setString('serverUrl', v.trim()));
  String get serverKey =>
      _p.getString('serverKey') ?? const String.fromEnvironment('SUPABASE_ANON_KEY');
  set serverKey(String v) => _set(() => _p.setString('serverKey', v.trim()));
  bool get hasServer => serverUrl.startsWith('https://') && serverKey.isNotEmpty;

  String get bibleVersion => _p.getString('bibleVersion') ?? 'LSG';
  set bibleVersion(String v) => _set(() => _p.setString('bibleVersion', v));

  int get bibleAssetVersion => _p.getInt('bibleAssetVersion') ?? 0;
  set bibleAssetVersion(int v) => _p.setInt('bibleAssetVersion', v);

  void _set(Future<bool> Function() f) {
    f();
    notifyListeners();
  }
}
