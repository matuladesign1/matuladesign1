import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/audio_controller.dart';

String fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Mini-lecteur affiché au-dessus de la navigation pendant une écoute.
class AudioBar extends StatelessWidget {
  const AudioBar({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final s = audio.current;
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      child: InkWell(
        onTap: () => showAudioSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(children: [
            const Icon(Icons.graphic_eq_rounded, color: Brand.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(s.code, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ]),
            ),
            StreamBuilder<PlayerState>(
              stream: audio.player.playerStateStream,
              builder: (_, snap) => IconButton(
                icon: Icon((snap.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: audio.toggle,
              ),
            ),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: audio.stop),
          ]),
        ),
      ),
    );
  }
}

void showAudioSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const AudioControls(),
  );
}

class AudioControls extends StatelessWidget {
  const AudioControls({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final s = audio.current;
    if (s == null) return const SizedBox(height: 80);
    final p = audio.player;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${s.code} · ${s.shortLocation}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (audio.error != null) Padding(padding: const EdgeInsets.all(8), child: Text(audio.error!)),
          const SizedBox(height: 12),
          StreamBuilder<Duration>(
            stream: p.positionStream,
            builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = p.duration ?? Duration.zero;
              final max = dur.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
              return Column(children: [
                Slider(
                  value: pos.inMilliseconds.toDouble().clamp(0, max),
                  max: max,
                  onChanged: (v) => p.seek(Duration(milliseconds: v.round())),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(fmt(pos)), Text(fmt(dur))]),
              ]);
            },
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(iconSize: 36, icon: const Icon(Icons.fast_rewind_rounded), tooltip: '-15 s', onPressed: () => audio.skip(-15)),
            const SizedBox(width: 12),
            StreamBuilder<PlayerState>(
              stream: p.playerStateStream,
              builder: (_, snap) => IconButton.filled(
                iconSize: 44,
                icon: Icon((snap.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: audio.toggle,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(iconSize: 36, icon: const Icon(Icons.fast_forward_rounded), tooltip: '+15 s', onPressed: () => audio.skip(15)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final sp in AudioController.speeds)
              ChoiceChip(
                label: Text('${sp.toString().replaceAll('.', ',')}x'),
                selected: p.speed == sp,
                onSelected: (_) => audio.setSpeed(sp),
              ),
          ]),
          if (!s.audioCues)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Synchronisation texte/audio indisponible : pas de repères temporels pour ce sermon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}
