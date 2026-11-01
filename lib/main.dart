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
  final progress = ValueNotifier<double?>(null);
  runApp(_Preparing(progress: progress));
  final adb = await AppDb.open(settings, onProgress: (v) => progress.value = v);
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

/// Écran affiché pendant la première installation de la bibliothèque.
class _Preparing extends StatelessWidget {
  const _Preparing({required this.progress});
  final ValueNotifier<double?> progress;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Brand.deepBlue,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/images/logo_small.png', width: 140)),
                  const SizedBox(height: 32),
                  if (v != null) ...[
                    LinearProgressIndicator(value: v, color: Brand.gold, backgroundColor: Colors.white24),
                    const SizedBox(height: 16),
                    const Text('Installation de la bibliothèque des prédications…',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 4),
                    const Text('Une seule fois, au premier démarrage.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
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
