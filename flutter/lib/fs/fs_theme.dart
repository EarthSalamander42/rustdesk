// FS Support — thème « A · Atelier » appliqué au client.
//
// Accroche unique dans `common.dart` : `MyTheme.lightTheme = fsClientTheme(ThemeData(...), Brightness.light)`
// (idem en sombre). Toutes les fenêtres (accueil, sessions, transfert de fichiers, gestionnaire de connexions)
// passent par `MyTheme`, le thème se propage donc partout sans autre modification.
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart' show ColorThemeExtension;
import '../desktop/widgets/tabbar_widget.dart' show TabbarTheme;

/// Thème Material de l'Atelier, avec les extensions RustDesk recolorées (filets, onglets, toasts).
ThemeData fsClientTheme(ThemeData base, Brightness brightness) {
  final t = FsTokens.forBrightness(brightness);
  final themed = fsAtelierTheme(base, brightness);
  final dark = brightness == Brightness.dark;
  final ext = themed.extensions.values
      .where((e) => e is! ColorThemeExtension && e is! TabbarTheme)
      .followedBy([
    ColorThemeExtension(
      border: t.line,
      border2: t.line,
      border3: t.line,
      highlight: t.sel,
      drag_indicator: t.muted,
      shadow: dark ? Colors.black : const Color(0xFF11140D),
      errorBannerBg: dark ? const Color(0xFF3A1F17) : const Color(0xFFF6E3DC),
      me: t.on,
      toastBg: t.ink.withOpacity(0.92),
      toastText: t.bg,
      divider: t.line,
    ),
    TabbarTheme(
      selectedTabIconColor: t.acc,
      unSelectedTabIconColor: t.off,
      selectedTextColor: t.ink,
      unSelectedTextColor: t.muted,
      selectedIconColor: t.ink,
      unSelectedIconColor: t.muted,
      dividerColor: t.line,
      hoverColor: t.hov,
      closeHoverColor: t.bg,
      selectedTabBackgroundColor: t.bg,
    ),
  ]);
  return themed.copyWith(extensions: ext);
}
