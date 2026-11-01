import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'core/settings.dart';
import 'core/theme.dart';
import 'data/ai_service.dart';
import 'data/audio_controller.dart';
import 'data/db.dart';
import 'data/plans.dart';
import 'data/search_service.dart';
import 'data/user_repo.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.matuladesign.sermons.audio',
    androidNotificationChannelName: 'Lecture des prédications',
    androidNotificationOngoing: true,
  );
  final settings = await Settings.load();
  final adb = await AppDb.open(settings);
  final search = SearchService(adb);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      Provider.value(value: adb),
      Provider.value(value: search),
      ChangeNotifierProvider(create: (_) => LibraryState()),
      ChangeNotifierProvider(create: (_) => UserRepo(adb)),
      ChangeNotifierProvider(create: (_) => Plans(adb)),
      ChangeNotifierProvider(create: (_) => AudioController()),
      Provider(create: (_) => AiService(settings, search, adb)),
    ],
    child: const MatomateApp(),
  ));
}

/// Signale aux écrans que la bibliothèque a changé (import, suppression).
class LibraryState extends ChangeNotifier {
  int version = 0;
  void changed() {
    version++;
    notifyListeners();
  }
}

class MatomateApp extends StatelessWidget {
  const MatomateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return MaterialApp(
      title: 'Sermons de Branham Matomate',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * settings.textScale)),
        child: child!,
      ),
      home: Shell(key: Shell.globalKey),
    );
  }
}
