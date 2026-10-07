// Typographie de l'Atelier : Inter (texte), Archivo Black (ID), JetBrains Mono (codes).
// Polices embarquées dans le paquet (licence OFL, fichiers dans assets/fonts) : aucun téléchargement à l'exécution.
//
// Pour coller au rendu CSS de la maquette :
// - la hauteur de ligne est un multiple de la taille (`line-height: 1.4`), avec l'interlignage réparti
//   également au-dessus et au-dessous (`TextLeadingDistribution.even`), comme un navigateur ;
// - un texte plus petit posé dans une ligne plus haute (span dans un bloc) passe par [FsType.strut],
//   qui reproduit la « ligne fantôme » (strut) du bloc parent.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'tokens.dart';

class FsType {
  FsType._();

  static const String package = 'fs_ui';
  static const String fInter = 'Inter';
  static const String fArchivo = 'ArchivoBlack';
  static const String fMono = 'JetBrainsMono';

  /// Nom complet de la famille Inter, utilisable hors du paquet (ThemeData.fontFamily).
  static const String interFamily = 'packages/fs_ui/Inter';

  static const TextHeightBehavior heightBehavior = TextHeightBehavior(
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle _s(
    String family,
    double size,
    FontWeight weight, {
    double height = 1.4,
    double letterSpacing = 0,
    Color? color,
    List<FontFeature>? features,
  }) =>
      TextStyle(
        fontFamily: family,
        package: package,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
        fontFeatures: features,
        decoration: TextDecoration.none,
      );

  /// Inter. `em` est l'espacement des lettres exprimé en em, comme en CSS.
  static TextStyle sans(double size, FontWeight weight,
          {double height = 1.4, double em = 0, Color? color, bool tabular = false}) =>
      _s(fInter, size, weight,
          height: height,
          letterSpacing: em * size,
          color: color,
          features: tabular ? const [FontFeature.tabularFigures()] : null);

  /// Archivo Black (identifiant du poste).
  static TextStyle display(double size,
          {double height = 1.15, double em = 0.005, Color? color}) =>
      _s(fArchivo, size, FontWeight.w400,
          height: height, letterSpacing: em * size, color: color);

  /// JetBrains Mono (mot de passe, identifiants des appareils).
  static TextStyle mono(double size, FontWeight weight,
          {double height = 1.4, double em = 0, Color? color}) =>
      _s(fMono, size, weight, height: height, letterSpacing: em * size, color: color);

  /// Étiquette en capitales espacées (`.A-eb`) : 10,5 px, 900, 0,18 em.
  static TextStyle eyebrow(Color color, {double size = 10.5, double em = 0.18}) =>
      sans(size, FontWeight.w900, em: em, color: color);

  /// Ligne fantôme d'un bloc : impose la hauteur de ligne et la ligne de base du parent CSS.
  static StrutStyle strut(double size, {double height = 1.4, String family = fInter}) =>
      StrutStyle(
        fontFamily: family,
        package: package,
        fontSize: size,
        height: height,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      );
}

/// Texte de l'Atelier : applique le comportement de hauteur « navigateur » et, au besoin, une ligne fantôme.
class FsText extends StatelessWidget {
  const FsText(
    this.text, {
    super.key,
    required this.style,
    this.strut,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.upper = false,
    this.softWrap,
  });

  final String text;
  final TextStyle style;
  final StrutStyle? strut;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool upper;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final lh = strut != null
        ? (strut!.fontSize ?? 14) * (strut!.height ?? 1)
        : (style.fontSize ?? 14) * (style.height ?? 1.4);
    return FsExactLines(
      lineHeight: lh,
      child: Text(
        upper ? text.toUpperCase() : text,
        style: style,
        strutStyle: strut,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
        textHeightBehavior: FsType.heightBehavior,
        textScaler: TextScaler.noScaling,
      ),
    );
  }
}

/// Hauteur exacte « navigateur » : le moteur de texte arrondit chaque ligne au pixel (14,7 → 15),
/// ce qui décale tout ce qui suit. On garde le paragraphe tel quel mais on déclare n × hauteur exacte.
class FsExactLines extends SingleChildRenderObjectWidget {
  const FsExactLines({super.key, required this.lineHeight, super.child});
  final double lineHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFsExactLines(lineHeight);

  @override
  void updateRenderObject(BuildContext context, RenderFsExactLines renderObject) => renderObject.lineHeight = lineHeight;
}

class RenderFsExactLines extends RenderProxyBox {
  RenderFsExactLines(this._lh);
  double _lh;
  set lineHeight(double v) {
    if (v == _lh) return;
    _lh = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child!;
    c.layout(constraints, parentUsesSize: true);
    final n = (c.size.height / _lh).round().clamp(1, 1 << 20);
    size = constraints.constrain(Size(c.size.width, n * _lh));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _exact(super.computeMinIntrinsicHeight(width));
  @override
  double computeMaxIntrinsicHeight(double width) => _exact(super.computeMaxIntrinsicHeight(width));
  double _exact(double h) => (h / _lh).round().clamp(1, 1 << 20) * _lh;
}

/// Étiquette en capitales (`.A-eb`) : couleur « muted » du thème par défaut.
class FsEyebrow extends StatelessWidget {
  const FsEyebrow(this.text, {super.key, this.size = 10.5, this.em = 0.18, this.color, this.strut});
  final String text;
  final double size;
  final double em;
  final Color? color;
  final StrutStyle? strut;

  @override
  Widget build(BuildContext context) => FsText(text,
      upper: true,
      strut: strut,
      style: FsType.eyebrow(color ?? FsTokens.of(context).muted, size: size, em: em));
}
