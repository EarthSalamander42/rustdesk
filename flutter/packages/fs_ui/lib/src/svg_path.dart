// Petit lecteur de chemins SVG (M L H V C A Z, absolus et relatifs) : suffisant pour les
// pictogrammes de la maquette (Windows, Android) sans dépendre de flutter_svg.

import 'package:flutter/widgets.dart';

final RegExp _token = RegExp(r'[MmLlHhVvCcAaZz]|[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');

/// Convertit l'attribut `d` d'un chemin SVG en [Path].
Path parseSvgPath(String d) {
  final toks = _token.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  double cx = 0, cy = 0, sx = 0, sy = 0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(toks[i++]);
  while (i < toks.length) {
    if (isCmd(toks[i])) cmd = toks[i++];
    switch (cmd) {
      case 'M':
      case 'm':
        final x = n(), y = n();
        cx = cmd == 'm' ? cx + x : x;
        cy = cmd == 'm' ? cy + y : y;
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
        cmd = cmd == 'm' ? 'l' : 'L';
        break;
      case 'L':
      case 'l':
        final x = n(), y = n();
        cx = cmd == 'l' ? cx + x : x;
        cy = cmd == 'l' ? cy + y : y;
        path.lineTo(cx, cy);
        break;
      case 'H':
      case 'h':
        final x = n();
        cx = cmd == 'h' ? cx + x : x;
        path.lineTo(cx, cy);
        break;
      case 'V':
      case 'v':
        final y = n();
        cy = cmd == 'v' ? cy + y : y;
        path.lineTo(cx, cy);
        break;
      case 'C':
      case 'c':
        final r = cmd == 'c';
        final x1 = n(), y1 = n(), x2 = n(), y2 = n(), x = n(), y = n();
        path.cubicTo(r ? cx + x1 : x1, r ? cy + y1 : y1, r ? cx + x2 : x2,
            r ? cy + y2 : y2, r ? cx + x : x, r ? cy + y : y);
        cx = r ? cx + x : x;
        cy = r ? cy + y : y;
        break;
      case 'A':
      case 'a':
        final rx = n(), ry = n(), rot = n();
        final large = n() != 0, sweep = n() != 0;
        final x = n(), y = n();
        final ex = cmd == 'a' ? cx + x : x;
        final ey = cmd == 'a' ? cy + y : y;
        path.arcToPoint(Offset(ex, ey),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: large,
            clockwise: sweep);
        cx = ex;
        cy = ey;
        break;
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
        // une commande Z n'a pas d'argument : on repart sur la commande suivante
        if (i < toks.length && !isCmd(toks[i])) cmd = 'L';
        break;
      default:
        i++;
    }
  }
  return path;
}

/// Pictogramme vectoriel dessiné dans une boîte carrée de [size], viewBox 24×24 par défaut.
class FsPathIcon extends StatelessWidget {
  const FsPathIcon(this.d, {super.key, required this.size, required this.color, this.viewBox = 24});
  final String d;
  final double size;
  final Color color;
  final double viewBox;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PathPainter(d, color, viewBox)),
      );
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.d, this.color, this.viewBox);
  final String d;
  final Color color;
  final double viewBox;
  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final p = _cache.putIfAbsent(d, () => parseSvgPath(d));
    canvas.save();
    canvas.scale(size.width / viewBox, size.height / viewBox);
    canvas.drawPath(p, Paint()..color = color..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PathPainter oldDelegate) => oldDelegate.d != d || oldDelegate.color != color;
}

/// Chemins des systèmes d'exploitation (repris de la maquette).
class FsOsPaths {
  FsOsPaths._();
  static const String windows =
      'M3 5.6l7.4-1v7H3zm8.4-1.15L21 3v8.6h-9.6zM3 12.6h7.4v7L3 18.4zm8.4 0H21V21l-9.6-1.4z';
  static const String android =
      'M17.6 9.48l1.84-3.18a.38.38 0 0 0-.66-.38l-1.86 3.22a11.4 11.4 0 0 0-9.84 0L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z';
  static const String apple =
      'M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.5-1-2.5-3.9zM14 5.5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1.1.1 2.1-.6 2.8-1.4z';
  static const String linux =
      'M12 2c-2.2 0-3.6 1.9-3.6 4.6 0 1.2.3 2.2.1 3.2-.3 1.5-2.6 3.4-3.2 5.9-.4 1.5.2 2.3.9 2.1.5-.1.6-.9 1.2-.7.3.1.2.9.6 1.5.6.9 2.6 1.4 4 1.4s3.4-.5 4-1.4c.4-.6.3-1.4.6-1.5.6-.2.7.6 1.2.7.7.2 1.3-.6.9-2.1-.6-2.5-2.9-4.4-3.2-5.9-.2-1 .1-2 .1-3.2C15.6 3.9 14.2 2 12 2z';
}
