import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Paysages dessinés en vectoriel (aucune image téléchargée, fonctionne hors ligne).
class LandscapePainter extends CustomPainter {
  LandscapePainter(this.variant);
  final int variant;

  static const _skies = [
    [Color(0xFF6E8FB5), Color(0xFFC9A27A), Color(0xFF39404D)], // coucher de soleil sur la mer
    [Color(0xFF2E4A3B), Color(0xFF6E8F6A), Color(0xFF1B2620)], // forêt
    [Color(0xFF3B2F4A), Color(0xFFE39A5B), Color(0xFF211A26)], // crépuscule
    [Color(0xFF7FA6C9), Color(0xFFDCE6EE), Color(0xFF55708A)], // hiver
    [Color(0xFF475A6B), Color(0xFF9AA9B3), Color(0xFF2B3640)], // sentier nuageux
    [Color(0xFF071D45), Color(0xFF123E78), Color(0xFF040F25)], // nuit bleue
    [Color(0xFF8C5A2B), Color(0xFFF6CE69), Color(0xFF3A2410)], // aube dorée
    [Color(0xFF365E73), Color(0xFF78B7F0), Color(0xFF1C3442)], // lac
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = _skies[variant % _skies.length];
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c[0], c[1], c[2]],
                  stops: const [0, .55, 1])
              .createShader(rect));
    final rnd = math.Random(variant * 31 + 7);
    // soleil / lune
    final sun = Offset(size.width * (.2 + rnd.nextDouble() * .6), size.height * (.3 + rnd.nextDouble() * .15));
    canvas.drawCircle(sun, size.shortestSide * .09,
        Paint()..color = Colors.white.withValues(alpha: .25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    // deux rangées de collines
    for (var layer = 0; layer < 3; layer++) {
      final base = size.height * (.58 + layer * .12);
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, base);
      final waves = 3 + layer;
      for (var i = 0; i <= waves; i++) {
        final x = size.width * i / waves;
        final y = base - size.height * (.04 + rnd.nextDouble() * .1);
        path.quadraticBezierTo(x - size.width / waves / 2, y, x, base - size.height * .02 * rnd.nextDouble());
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = Color.lerp(c[2], Colors.black, .15 + layer * .2)!.withValues(alpha: .55 + layer * .15));
    }
  }

  @override
  bool shouldRepaint(LandscapePainter old) => old.variant != variant;
}

class Landscape extends StatelessWidget {
  const Landscape({super.key, required this.variant, this.child, this.radius = 18});
  final int variant;
  final Widget? child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: LandscapePainter(variant),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: .05), Colors.black.withValues(alpha: .45)]),
            ),
            child: child,
          ),
        ),
      );
}

/// Affiche un extrait où les termes trouvés sont entourés de \u0001 … \u0002.
class MarkedText extends StatelessWidget {
  const MarkedText(this.text, {super.key, this.style, this.maxLines});
  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    final parts = text.split('\u0001');
    for (var i = 0; i < parts.length; i++) {
      if (i == 0) {
        spans.add(TextSpan(text: parts[i]));
        continue;
      }
      final end = parts[i].indexOf('\u0002');
      if (end < 0) {
        spans.add(TextSpan(text: parts[i]));
        continue;
      }
      spans.add(TextSpan(
          text: parts[i].substring(0, end),
          style: TextStyle(
              backgroundColor: Brand.gold.withValues(alpha: .35),
              color: cs.onSurface,
              fontWeight: FontWeight.w600)));
      spans.add(TextSpan(text: parts[i].substring(end + 1)));
    }
    return Text.rich(TextSpan(children: spans),
        style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: Brand.gold),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
          if (action != null)
            TextButton(
                onPressed: onAction,
                child: Text(action!, style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// Pastille d'icône arrondie (raccourcis de l'accueil).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 10),
            FittedBox(child: Text(label, style: const TextStyle(fontSize: 14))),
          ]),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
