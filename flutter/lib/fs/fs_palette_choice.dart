// FS Support — choix de la couleur de l'interface : « Atelier » ou « Ardoise » (14/10/2026).
//
// Au tout premier lancement, et à la première ouverture après la mise à jour pour les installations existantes,
// une fenêtre présente les deux couleurs en aperçu réel (l'application derrière change en direct) et enregistre
// le choix, une seule fois (`fs-palette-choisie` dans le fichier de l'Atelier). Fermer la fenêtre garde Atelier.
// Ensuite : Paramètres › Général (bureau) ou Réglages (Android), [FsPaletteSettings].
//
// Jamais de fenêtre :
// - pendant une prise en main entrante (bureau : le gestionnaire de connexions est ouvert ; Android : une
//   connexion est en cours) — la proposition attend la fin de la session ;
// - en mode « Écran client » Android (réglage Flutter ou préférence Kotlin) : l'écran garde Atelier ;
// - dans la petite fenêtre « réception seule », les sous-fenêtres et sur iOS / web.
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import 'fs_client_screen.dart' show fsClientScreenEnabled;
import 'fs_theme.dart';

/// Marqueur « couleur choisie » (fichier de l'Atelier).
const String kOptionFsPaletteChosen = 'fs-palette-choisie';
const String _kAtelierPrefix = 'fs-atelier:';

bool _propositionEnCours = false;

bool _dejaChoisie() {
  try {
    return bind.mainGetCommonSync(key: '$_kAtelierPrefix$kOptionFsPaletteChosen') == 'Y';
  } catch (_) {
    return true;
  }
}

Future<void> _marquerChoisie() => bind.mainSetCommon(key: '$_kAtelierPrefix$kOptionFsPaletteChosen', value: 'Y');

/// Mode « Écran client » actif (réglage Flutter, ou préférence Kotlin lue par le service) ?
Future<bool> _ecranClient() async {
  if (!isAndroid) return false;
  if (fsClientScreenEnabled()) return true;
  try {
    return await gFFI.invokeMethodWithResult<bool>(AndroidChannel.kFsGetClientScreen) == true;
  } catch (_) {
    return false;
  }
}

/// Prise en main entrante en cours ?
Future<bool> _priseEnMainEntrante() async {
  if (isAndroid) return gFFI.serverModel.clients.any((c) => !c.disconnected);
  try {
    return await bind.mainGetCommon(key: 'fs-incoming-session') == 'true';
  } catch (_) {
    return false;
  }
}

/// Propose le choix de couleur si ce n'est pas déjà fait (voir l'en-tête pour les cas exclus).
Future<void> fsMaybeOfferPalette(BuildContext context) async {
  if (_propositionEnCours || isWeb || isIOS) return;
  if (isDesktop && desktopType != DesktopType.main) return;
  if (_dejaChoisie() || bind.isIncomingOnly()) return;
  _propositionEnCours = true;
  try {
    // Laisser l'accueil s'installer (et les fenêtres de mise en place passer en premier).
    await Future.delayed(const Duration(milliseconds: 1200));
    while (true) {
      if (!context.mounted || _dejaChoisie()) return;
      if (await _ecranClient()) return; // L'écran garde Atelier, sans rien demander.
      if (!await _priseEnMainEntrante() && ModalRoute.of(context)?.isCurrent != false) break;
      // Une session entrante ou une autre fenêtre est ouverte : on repasse plus tard.
      await Future.delayed(const Duration(seconds: 20));
    }
    if (!context.mounted) return;
    await fsShowPaletteDialog(context);
  } finally {
    _propositionEnCours = false;
  }
}

/// Fenêtre de choix (premier lancement). L'application change de couleur en direct à chaque clic ;
/// « Continuer avec … » enregistre ; fermer sans choisir garde la couleur enregistrée (Atelier).
Future<void> fsShowPaletteDialog(BuildContext context) async {
  final depart = fsStoredPalette();
  var choix = depart;
  final valide = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: FsStrings.paletteTitle,
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: FsMotion.slide,
    transitionBuilder: (context, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: FsMotion.ease);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(c), child: child),
      );
    },
    pageBuilder: (context, _, __) => StatefulBuilder(builder: (context, setState) {
      final t = FsTokens.of(context);
      final largeur = MediaQuery.of(context).size.width;
      final etroit = largeur < 600;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: etroit ? largeur - 24 : 640),
          child: Material(
            color: t.bg,
            shape: RoundedRectangleBorder(side: BorderSide(color: t.line)),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(etroit ? 18 : 26),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FsText(FsStrings.paletteTitle, style: FsType.sans(etroit ? 19 : 22, FontWeight.w800, em: -0.03, color: t.ink)),
                const SizedBox(height: 6),
                FsText(FsStrings.paletteText, style: FsType.sans(13.5, FontWeight.w400, color: t.muted)),
                const SizedBox(height: 18),
                FsPalettePicker(
                  selected: choix,
                  previewHeight: etroit ? 84 : 104,
                  onSelect: (p) {
                    setState(() => choix = p);
                    fsPaletteApercu(p);
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: etroit ? Alignment.center : Alignment.centerRight,
                  child: FsButton(
                    label: FsStrings.paletteContinue(choix.label),
                    trailing: Icons.arrow_forward_rounded,
                    expand: etroit,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }),
  );
  if (valide == true) {
    await fsSetPalette(choix);
  } else {
    fsPaletteApercu(depart);
  }
  await _marquerChoisie();
}

/// Applique une couleur à l'écran sans l'enregistrer (aperçu en direct).
void fsPaletteApercu(FsPalette p) {
  fsPreviewPalette(p);
}

/// Carte « Couleur de l'interface » des réglages (bureau : Paramètres › Général ; Android : Réglages).
class FsPaletteSettings extends StatefulWidget {
  const FsPaletteSettings({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  State<FsPaletteSettings> createState() => _FsPaletteSettingsState();
}

class _FsPaletteSettingsState extends State<FsPaletteSettings> {
  late FsPalette _choix = fsStoredPalette();

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Padding(
      padding: widget.padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FsText(FsStrings.paletteSettingsText, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
        const SizedBox(height: 10),
        FsPalettePicker(
          selected: _choix,
          previewHeight: 84,
          onSelect: (p) async {
            setState(() => _choix = p);
            await fsSetPalette(p);
            await _marquerChoisie();
          },
        ),
      ]),
    );
  }
}
