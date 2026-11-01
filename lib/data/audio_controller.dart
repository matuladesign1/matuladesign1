import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'models.dart';

/// Lecture audio des prédications : arrière-plan + contrôles dans la notification Android.
class AudioController extends ChangeNotifier {
  final player = AudioPlayer();
  Sermon? current;
  String? error;

  static const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> play(Sermon s) async {
    final url = s.audioUrl;
    if (url == null) return;
    error = null;
    if (current?.id != s.id) {
      current = s;
      notifyListeners();
      try {
        await player.setAudioSource(AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: '${s.id}',
            title: s.title,
            album: '${s.code} · ${s.shortLocation}',
            artist: 'William Marrion Branham',
          ),
        ));
      } catch (e) {
        error = 'Audio indisponible : $e';
        notifyListeners();
        return;
      }
    }
    await player.play();
  }

  Future<void> toggle() async => player.playing ? player.pause() : player.play();

  Future<void> skip(int seconds) async {
    final d = player.duration ?? Duration.zero;
    var t = player.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (d > Duration.zero && t > d) t = d;
    await player.seek(t);
  }

  Future<void> setSpeed(double s) async {
    await player.setSpeed(s);
    notifyListeners();
  }

  Future<void> stop() async {
    await player.stop();
    current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
