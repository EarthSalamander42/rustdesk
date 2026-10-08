// Jetons de la direction « A · Atelier » : la charte du site et des cartes FS Solutions
// (papier crème, encre, olive ; lime en sombre ; filets 1 px ; angles droits).
// Valeurs reprises une à une de la maquette (`fs-support-branding/src/a.css`, bloc `.A`).

import 'package:flutter/material.dart';

/// Couleurs de l'Atelier, en clair et en sombre. Accessible par `FsTokens.of(context)`.
@immutable
class FsTokens extends ThemeExtension<FsTokens> {
  const FsTokens({
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.field,
    required this.ink,
    required this.muted,
    required this.line,
    required this.line2,
    required this.acc,
    required this.accFg,
    required this.on,
    required this.off,
    required this.hov,
    required this.sel,
    required this.danger,
    required this.shadow,
  });

  final Brightness brightness;

  /// Fond papier (`--bg`).
  final Color bg;

  /// Fond secondaire : barre de titre, barre d'état (`--bg2`).
  final Color bg2;

  /// Fond des champs de saisie (`--field`).
  final Color field;

  /// Encre : texte principal et filets forts (`--ink`).
  final Color ink;

  /// Texte secondaire (`--muted`).
  final Color muted;

  /// Filet 1 px (`--line`).
  final Color line;

  /// Filet léger entre les lignes d'une liste (`--line2`).
  final Color line2;

  /// Accent : olive en clair, lime en sombre (`--acc`).
  final Color acc;

  /// Texte posé sur l'accent (`--acc-fg`).
  final Color accFg;

  /// Pastille « en ligne » (`--on`).
  final Color on;

  /// Pastille « hors ligne » (`--off`).
  final Color off;

  /// Survol (`--hov`).
  final Color hov;

  /// Sélection (`--sel`).
  final Color sel;

  /// Action destructrice : « Terminer » (`--danger`).
  final Color danger;

  /// Couleur des ombres portées (menus, barre de session).
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  static const FsTokens light = FsTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF7F4EA),
    bg2: Color(0xFFEEEADC),
    field: Color(0xFFFFFDF6),
    ink: Color(0xFF11140D),
    muted: Color(0xFF515844),
    line: Color(0xFFC7C9B8),
    line2: Color(0xFFDEDCCD),
    acc: Color(0xFF3A422D),
    accFg: Color(0xFFF7F4EA),
    on: Color(0xFF5B7A2C),
    off: Color(0xFFA7A996),
    hov: Color.fromRGBO(58, 66, 45, 0.05),
    sel: Color.fromRGBO(58, 66, 45, 0.09),
    danger: Color(0xFFA8432C),
    shadow: Color.fromRGBO(0, 0, 0, 0.55),
  );

  static const FsTokens dark = FsTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF10130D),
    bg2: Color(0xFF161A11),
    field: Color(0xFF0B0E08),
    ink: Color(0xFFF7F4EA),
    muted: Color(0xFFC7C9B8),
    line: Color.fromRGBO(199, 201, 184, 0.24),
    line2: Color.fromRGBO(199, 201, 184, 0.12),
    acc: Color(0xFF9FB65D),
    accFg: Color(0xFF11140D),
    on: Color(0xFF9FB65D),
    off: Color(0xFF5F6553),
    hov: Color.fromRGBO(199, 201, 184, 0.04),
    sel: Color.fromRGBO(159, 182, 93, 0.1),
    danger: Color(0xFFC8664F),
    shadow: Color.fromRGBO(0, 0, 0, 0.55),
  );

  /// Jetons du thème courant ; à défaut d'extension, déduits de la luminosité.
  static FsTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FsTokens>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  static FsTokens forBrightness(Brightness b) =>
      b == Brightness.dark ? dark : light;

  @override
  FsTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? bg2,
    Color? field,
    Color? ink,
    Color? muted,
    Color? line,
    Color? line2,
    Color? acc,
    Color? accFg,
    Color? on,
    Color? off,
    Color? hov,
    Color? sel,
    Color? danger,
    Color? shadow,
  }) =>
      FsTokens(
        brightness: brightness ?? this.brightness,
        bg: bg ?? this.bg,
        bg2: bg2 ?? this.bg2,
        field: field ?? this.field,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        line2: line2 ?? this.line2,
        acc: acc ?? this.acc,
        accFg: accFg ?? this.accFg,
        on: on ?? this.on,
        off: off ?? this.off,
        hov: hov ?? this.hov,
        sel: sel ?? this.sel,
        danger: danger ?? this.danger,
        shadow: shadow ?? this.shadow,
      );

  @override
  FsTokens lerp(ThemeExtension<FsTokens>? other, double t) {
    if (other is! FsTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FsTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      bg2: l(bg2, other.bg2),
      field: l(field, other.field),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      line2: l(line2, other.line2),
      acc: l(acc, other.acc),
      accFg: l(accFg, other.accFg),
      on: l(on, other.on),
      off: l(off, other.off),
      hov: l(hov, other.hov),
      sel: l(sel, other.sel),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Durées et courbes : identiques aux transitions CSS de la maquette.
/// Règle de Jason : du mouvement partout, aucune rupture.
class FsMotion {
  FsMotion._();

  /// `cubic-bezier(0.2, 0.7, 0.2, 1)` (`--ease`).
  static const Curve ease = Cubic(0.2, 0.7, 0.2, 1);

  /// Équivalent CSS `ease`.
  static const Curve cssEase = Cubic(0.25, 0.1, 0.25, 1);

  static const Duration hover = Duration(milliseconds: 200);
  static const Duration quick = Duration(milliseconds: 250);
  static const Duration fade = Duration(milliseconds: 300);
  static const Duration slide = Duration(milliseconds: 350);
  static const Duration accordion = Duration(milliseconds: 420);
  static const Duration theme = Duration(milliseconds: 450);
  static const Duration spin = Duration(milliseconds: 600);
}

/// Dimensions récurrentes (px logiques).
class FsDims {
  FsDims._();
  static const double titleBar = 38;
  static const double statusBar = 30;
  static const double rail = 256;
  static const double iconButton = 32;
  static const double field = 48;
  static const double row = 58;
  static const double groupHead = 46;
  static const double navItem = 38;

  /// Colonnes de la liste filetée : tuile, appareil (reste), ID, dernière session, actions.
  static const double colTile = 52;
  static const double colId = 140;
  static const double colLast = 150;
  static const double colActs = 176;
}

