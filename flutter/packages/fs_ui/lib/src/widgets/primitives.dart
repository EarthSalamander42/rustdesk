// Briques de base de l'Atelier : survol, logo, boutons, puce, interrupteur, pastille, filets pointillés, toast.
// Tout est animé (durées de la maquette) : couleur, bordure, position ; aucun changement d'état brutal.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';

/// Suit le survol et l'appui d'une zone, et reconstruit son contenu en conséquence.
class FsHover extends StatefulWidget {
  const FsHover({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.cursor,
    this.forceHover = false,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final MouseCursor? cursor;

  /// Force l'état « survolé » (captures du banc, sélection clavier).
  final bool forceHover;

  @override
  State<FsHover> createState() => _FsHoverState();
}

class _FsHoverState extends State<FsHover> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onDoubleTap != null;
    return MouseRegion(
      cursor: widget.cursor ?? (interactive ? SystemMouseCursors.click : MouseCursor.defer),
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        onTapDown: interactive ? (_) => setState(() => _down = true) : null,
        onTapUp: interactive ? (_) => setState(() => _down = false) : null,
        onTapCancel: interactive ? () => setState(() => _down = false) : null,
        child: widget.builder(context, _hover || widget.forceHover, _down),
      ),
    );
  }
}

/// Monogramme FS : olive en clair, papier en sombre (fondu enchaîné au changement de thème).
class FsMark extends StatelessWidget {
  const FsMark({super.key, required this.size, this.variant});
  final double size;

  /// `olive`, `paper` ou `lime` ; par défaut selon le thème.
  final String? variant;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final v = variant ?? (t.isDark ? 'paper' : 'olive');
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: FsMotion.theme,
        child: Image.asset(
          'assets/brand/mark-$v.png',
          key: ValueKey(v),
          package: FsType.package,
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
        ),
      ),
    );
  }
}

/// Bouton-icône carré (`.A-ib`) : 32 px, icône 18 px, filet au survol de l'état actif.
class FsIconButton extends StatefulWidget {
  const FsIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.on = false,
    this.size = FsDims.iconButton,
    this.iconSize = 18,
    this.spinOnPress = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool on;
  final double size;
  final double iconSize;

  /// Tour complet de l'icône à chaque appui (bouton « nouveau mot de passe »).
  final bool spinOnPress;

  @override
  State<FsIconButton> createState() => _FsIconButtonState();
}

class _FsIconButtonState extends State<FsIconButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: FsMotion.spin);

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _tap() {
    if (widget.spinOnPress) _spin.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    Widget b = FsHover(
      onTap: widget.onPressed == null ? null : _tap,
      builder: (context, hover, _) {
        final fg = hover || widget.on ? t.ink : t.muted;
        return AnimatedContainer(
          duration: FsMotion.hover,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: hover ? t.hov : t.hov.withOpacity(0),
            border: Border.all(color: widget.on ? t.line : t.line.withOpacity(0)),
          ),
          alignment: Alignment.center,
          child: RotationTransition(
            turns: CurvedAnimation(parent: _spin, curve: FsMotion.ease),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: fg),
              duration: FsMotion.hover,
              builder: (context, c, _) => Icon(widget.icon, size: widget.iconSize, color: c),
            ),
          ),
        );
      },
    );
    if (widget.tooltip != null) b = Tooltip(message: widget.tooltip!, child: b);
    return b;
  }
}

enum FsButtonKind { primary, ghost }

/// Bouton plein ou filaire (`.A-btn`, `.A-btn.ghost`) : 48 px de haut, angles droits.
class FsButton extends StatelessWidget {
  const FsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
    this.trailing,
    this.kind = FsButtonKind.primary,
    this.height = FsDims.field,
    this.fontSize = 15,
    this.iconSize = 19,
    this.hPadding = 20,
    this.expand = false,
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final IconData? trailing;
  final FsButtonKind kind;
  final double height;
  final double fontSize;
  final double iconSize;
  final double hPadding;
  final bool expand;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final primary = kind == FsButtonKind.primary;
    final bg = background ?? (primary ? t.acc : t.acc.withOpacity(0));
    final fg = foreground ?? (primary ? t.accFg : t.ink);
    return FsHover(
      onTap: onPressed,
      builder: (context, hover, down) => AnimatedContainer(
        duration: FsMotion.theme,
        curve: FsMotion.cssEase,
        height: height,
        transform: Matrix4.translationValues(0, down ? 1 : 0, 0),
        padding: EdgeInsets.symmetric(horizontal: hPadding),
        decoration: BoxDecoration(
          color: bg,
          border: primary ? null : Border.all(color: t.line),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[
              Icon(leading, size: iconSize, color: fg),
              const SizedBox(width: 10),
            ],
            FsText(label,
                style: FsType.sans(fontSize, primary ? FontWeight.w700 : FontWeight.w600, color: fg)),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              AnimatedSlide(
                offset: Offset(hover && primary ? 3 / iconSize : 0, 0),
                duration: FsMotion.fade,
                curve: FsMotion.ease,
                child: Icon(trailing, size: iconSize, color: fg),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Puce à bascule (`.A-chip`) : « Par entreprise ».
class FsChip extends StatelessWidget {
  const FsChip({super.key, required this.label, this.icon, this.on = false, this.onPressed});
  final String label;
  final IconData? icon;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final fg = on ? t.bg : t.ink;
    return FsHover(
      onTap: onPressed,
      builder: (context, hover, _) => AnimatedContainer(
        duration: FsMotion.theme,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? t.ink : (hover ? t.hov : t.hov.withOpacity(0)),
          border: Border.all(color: on ? t.ink : t.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 7),
          ],
          FsText(label, style: FsType.sans(13, FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}

/// Pastille ronde (`.A-dot`).
class FsDot extends StatelessWidget {
  const FsDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: FsMotion.theme,
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Pastille qui pulse (partage actif sur Android : `aPulse`).
class FsPulseDot extends StatefulWidget {
  const FsPulseDot({super.key, required this.color, this.live = false});
  final Color color;
  final bool live;

  @override
  State<FsPulseDot> createState() => _FsPulseDotState();
}

class _FsPulseDotState extends State<FsPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.live) _c.repeat();
  }

  @override
  void didUpdateWidget(FsPulseDot old) {
    super.didUpdateWidget(old);
    if (widget.live && !_c.isAnimating) _c.repeat();
    if (!widget.live && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = Curves.easeOut.transform(_c.value);
          return AnimatedContainer(
            duration: FsMotion.theme,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: widget.live
                  ? [BoxShadow(color: widget.color.withOpacity(0.6 * (1 - v)), spreadRadius: 10 * v)]
                  : const [],
            ),
          );
        },
      );
}

/// Interrupteur carré (`.A-tg`) : 40 × 22, curseur de 14 px.
class FsToggle extends StatelessWidget {
  const FsToggle({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: FsMotion.fade,
        width: 40,
        height: 22,
        decoration: BoxDecoration(
          color: value ? t.acc : t.acc.withOpacity(0),
          border: Border.all(color: value ? t.acc : t.line),
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: FsMotion.slide,
            curve: FsMotion.ease,
            left: value ? 21 : 3,
            top: 3,
            child: AnimatedContainer(
              duration: FsMotion.fade,
              width: 14,
              height: 14,
              color: value ? t.accFg : t.muted,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Cadre en pointillés 1 px (`border: 1px dashed`), à la manière des navigateurs (tirets de 3 px).
class FsDashedBox extends StatelessWidget {
  const FsDashedBox({super.key, required this.color, required this.child, this.padding = EdgeInsets.zero, this.fill});
  final Color color;
  final Widget child;
  final EdgeInsets padding;
  final Color? fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(color, fill),
        child: Padding(padding: padding + const EdgeInsets.all(1), child: child),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.fill);
  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) canvas.drawRect(Offset.zero & size, Paint()..color = fill!);
    final p = Paint()..color = color;
    void run(double length, void Function(double from, double to) seg) {
      // tirets de 3, espaces ajustés pour retomber sur les angles (comme Chrome)
      const dash = 3.0;
      final n = math.max(1, ((length + dash) / (dash * 2)).floor());
      final gap = n > 1 ? (length - n * dash) / (n - 1) : 0.0;
      for (var i = 0; i < n; i++) {
        final a = i * (dash + gap);
        seg(a, math.min(a + dash, length));
      }
    }

    run(size.width, (a, b) {
      canvas.drawRect(Rect.fromLTRB(a, 0, b, 1), p);
      canvas.drawRect(Rect.fromLTRB(a, size.height - 1, b, size.height), p);
    });
    run(size.height, (a, b) {
      canvas.drawRect(Rect.fromLTRB(0, a, 1, b), p);
      canvas.drawRect(Rect.fromLTRB(size.width - 1, a, size.width, b), p);
    });
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color || oldDelegate.fill != fill;
}

/// Hachures fines à 135° (`repeating-linear-gradient(135deg, transparent 0 N, couleur N N+1)`).
class FsHatch extends CustomPainter {
  FsHatch(this.color, {this.period = 11});
  final Color color;
  final double period;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    // lignes perpendiculaires à la direction 135° : x + y = constante
    final d = period * math.sqrt2;
    for (double k = (period - 0.5) * math.sqrt2; k < size.width + size.height + d; k += d) {
      canvas.drawLine(Offset(k, 0), Offset(0, k), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FsHatch oldDelegate) => oldDelegate.color != color || oldDelegate.period != period;
}

/// Filet horizontal 1 px.
class FsRule extends StatelessWidget {
  const FsRule({super.key, this.color, this.thickness = 1});
  final Color? color;
  final double thickness;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: FsMotion.theme,
        height: thickness,
        color: color ?? FsTokens.of(context).line,
      );
}

/// Petit message éphémère en bas de la fenêtre (`.toast`).
class FsToastHost extends StatefulWidget {
  const FsToastHost({super.key, required this.child, this.bottom = 46});
  final Widget child;
  final double bottom;

  static FsToastHostState? of(BuildContext context) => context.findAncestorStateOfType<FsToastHostState>();

  @override
  State<FsToastHost> createState() => FsToastHostState();
}

class FsToastHostState extends State<FsToastHost> {
  String _text = '';
  bool _on = false;
  int _gen = 0;

  void show(String text) {
    final g = ++_gen;
    setState(() {
      _text = text;
      _on = true;
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && g == _gen) setState(() => _on = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Stack(children: [
      Positioned.fill(child: widget.child),
      Positioned(
        left: 0,
        right: 0,
        bottom: widget.bottom,
        child: IgnorePointer(
          child: Center(
            child: AnimatedSlide(
              offset: Offset(0, _on ? 0 : 0.42),
              duration: const Duration(milliseconds: 400),
              curve: FsMotion.ease,
              child: AnimatedOpacity(
                opacity: _on ? 1 : 0,
                duration: FsMotion.fade,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: t.ink,
                  child: FsText(_text, style: FsType.sans(13, FontWeight.w600, color: t.bg)),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Copie un texte et affiche le toast le plus proche.
Future<void> fsCopy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) FsToastHost.of(context)?.show(message);
}
