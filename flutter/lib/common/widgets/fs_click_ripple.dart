import 'package:flutter/material.dart';

/// FS Support : retour visuel de clic sur la vue distante.
///
/// Un petit cercle s'élargit puis s'efface (~300 ms) à l'endroit de chaque appui, pour que le
/// technicien voie que son clic est parti même quand l'écran distant ne réagit pas tout de suite.
/// Le [Listener] est translucide et le dessin ignore les pointeurs : la saisie n'est jamais gênée.
class FsClickRipple extends StatefulWidget {
  final Widget child;
  const FsClickRipple({Key? key, required this.child}) : super(key: key);

  @override
  State<FsClickRipple> createState() => _FsClickRippleState();
}

class _FsRipple {
  final Offset position;
  final AnimationController controller;
  _FsRipple(this.position, this.controller);
}

class _FsClickRippleState extends State<FsClickRipple>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 320);
  // Au-delà, les plus anciens partent : un double clic rapide n'empile pas de cercles.
  static const _maxRipples = 4;
  final List<_FsRipple> _ripples = [];

  void _add(Offset position) {
    final controller = AnimationController(vsync: this, duration: _duration);
    final ripple = _FsRipple(position, controller);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _ripples.remove(ripple));
        controller.dispose();
      }
    });
    setState(() {
      _ripples.add(ripple);
      while (_ripples.length > _maxRipples) {
        final old = _ripples.removeAt(0);
        old.controller.stop();
        old.controller.dispose();
      }
    });
    controller.forward();
  }

  @override
  void dispose() {
    for (final r in _ripples) {
      r.controller.dispose();
    }
    _ripples.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _add(event.localPosition),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          for (final r in _ripples)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: r.controller,
                  builder: (context, _) => CustomPaint(
                    painter: _FsRipplePainter(
                        r.position, Curves.easeOut.transform(r.controller.value), color),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FsRipplePainter extends CustomPainter {
  final Offset center;
  final double t;
  final Color color;
  _FsRipplePainter(this.center, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    final radius = 8.0 + 18.0 * t;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity(0.25 * opacity)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity(0.9 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
  }

  @override
  bool shouldRepaint(_FsRipplePainter old) =>
      old.t != t || old.center != center || old.color != color;
}
