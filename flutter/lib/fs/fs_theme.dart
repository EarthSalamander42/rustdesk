// FS Support — thème « A · Atelier » appliqué au client.
//
// Accroche unique : `fsApplyClientTheme()` en tête de `main()` (main.dart), qui remplace `MyTheme.lightTheme`
// et `MyTheme.darkTheme`. Les définitions de `common.dart` restent celles de RustDesk : le script CI
// Flutter 3.44 (.github/patches) s’ancre sur elles. Toutes les fenêtres (accueil, sessions, transfert de fichiers, gestionnaire de connexions)
// passent par `MyTheme`, le thème se propage donc partout sans autre modification.
//
// Couleur de l'interface (14/10/2026) : « Atelier » ou « Ardoise » ([FsPalette]), chacune en clair et en sombre ;
// le mode clair / sombre / système reste le réglage RustDesk. Le choix vit dans le fichier de l'Atelier
// (`FS Support_atelier.json`, clé `fs-palette`, comme les entreprises : `LocalConfig` écrase `_local.toml`).
// - `fsLoadPalette()` : relu après `initEnv` (le pont Rust n'existe pas encore au moment de `fsApplyClientTheme`),
//   dans chaque fenêtre ; les thèmes sont reconstruits avant le premier `runApp`.
// - `fsSetPalette()` : choix fait dans la fenêtre de premier lancement ou dans Paramètres ; les racines
//   (`fsPaletteBuilder`) se reconstruisent, `MaterialApp` anime le passage des couleurs ; les autres fenêtres
//   relisent le choix à l'événement « theme » que la fenêtre principale leur envoie.
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart' show ColorThemeExtension, MyTheme, ParseToString, isDesktop;
import '../desktop/widgets/tabbar_widget.dart' show TabbarTheme;
import '../models/platform_model.dart';

/// Clé de la couleur dans le fichier de l'Atelier.
const String kOptionFsPalette = 'fs-palette';

/// Préfixe des réglages de l'Atelier (`ATELIER_OPTION_PREFIX` de `src/fs_support.rs`).
const String _kAtelierPrefix = 'fs-atelier:';

bool _fsThemeApplied = false;
ThemeData? _baseLight;
ThemeData? _baseDark;

/// Palette en vigueur : les racines d'application l'écoutent pour se reconstruire.
final ValueNotifier<FsPalette> fsPaletteNotifier = ValueNotifier(FsPalette.atelier);

/// Applique l'Atelier aux thèmes RustDesk, une seule fois par isolat (fenêtre principale et sous-fenêtres).
void fsApplyClientTheme() {
  if (_fsThemeApplied) return;
  _fsThemeApplied = true;
  _baseLight = MyTheme.lightTheme;
  _baseDark = MyTheme.darkTheme;
  _rebuildThemes();
}

void _rebuildThemes() {
  if (_baseLight == null || _baseDark == null) return;
  MyTheme.lightTheme = fsClientTheme(_baseLight!, Brightness.light);
  MyTheme.darkTheme = fsClientTheme(_baseDark!, Brightness.dark);
}

/// Couleur enregistrée (Atelier par défaut).
FsPalette fsStoredPalette() {
  try {
    return FsPalette.fromId(bind.mainGetCommonSync(key: '$_kAtelierPrefix$kOptionFsPalette'));
  } catch (_) {
    return FsPalette.atelier;
  }
}

void _apply(FsPalette p) {
  if (FsTokens.palette != p) {
    FsTokens.palette = p;
    _rebuildThemes();
  }
  fsPaletteNotifier.value = p;
}

/// Applique une couleur sans l'enregistrer (aperçu en direct de la fenêtre de choix).
void fsPreviewPalette(FsPalette p) => _apply(p);

/// Relit la couleur enregistrée (démarrage d'une fenêtre, ou changement fait dans une autre fenêtre).
void fsLoadPalette() => _apply(fsStoredPalette());

/// Enregistre et applique une couleur. Depuis la fenêtre principale du bureau, les autres fenêtres
/// (sessions, transferts, gestionnaire de connexions) la reprennent par l'événement « theme ».
Future<void> fsSetPalette(FsPalette p, {bool notifyOtherWindows = true}) async {
  await bind.mainSetCommon(key: '$_kAtelierPrefix$kOptionFsPalette', value: p.id);
  _apply(p);
  if (notifyOtherWindows && isDesktop) {
    try {
      await bind.mainChangeTheme(dark: MyTheme.getThemeModePreference().toShortString());
    } catch (_) {}
  }
}

/// Reconstruit [builder] à chaque changement de palette (racines `GetMaterialApp`).
Widget fsPaletteBuilder(WidgetBuilder builder) => ValueListenableBuilder<FsPalette>(
      valueListenable: fsPaletteNotifier,
      builder: (context, _, __) => builder(context),
    );

/// Thème Material de l'Atelier, avec les extensions RustDesk recolorées (filets, onglets, toasts).
/// [palette] : palette donnée (aperçus) ; à défaut, celle en vigueur.
ThemeData fsClientTheme(ThemeData base, Brightness brightness, [FsPalette? palette]) {
  final t = FsTokens.forBrightness(brightness, palette);
  final themed = fsAtelierTheme(base, brightness, palette);
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
      shadow: dark ? Colors.black : t.ink,
      errorBannerBg: dark ? Color.alphaBlend(t.danger.withOpacity(0.18), t.bg) : Color.alphaBlend(t.danger.withOpacity(0.12), t.bg),
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
