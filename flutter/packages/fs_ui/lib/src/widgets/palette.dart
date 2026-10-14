// Choix de la couleur de l'interface (14/10/2026) : « Atelier » ou « Ardoise ».
//
// [FsPalettePreview] dessine un vrai petit accueil (rail, liste filetée, bouton) avec les jetons de la
// palette, en clair ou en sombre ; [FsPaletteCard] réunit les deux aperçus, le nom et une phrase.
// Les cartes sont utilisées par la fenêtre du premier lancement et par Paramètres (client, lib/fs/).
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Mini accueil FS Support aux couleurs d'une palette.
class FsPalettePreview extends StatelessWidget {
  const FsPalettePreview({super.key, required this.palette, required this.brightness, this.height = 104});

  final FsPalette palette;
  final Brightness brightness;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.forBrightness(brightness, palette);
    Widget barre(double w, Color c, {double h = 5}) => Container(width: w, height: h, color: c);
    Widget ligne(bool enLigne) => Container(
          height: 18,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line2))),
          child: Row(children: [
            Container(width: 10, height: 10, color: t.bg2, margin: const EdgeInsets.only(right: 6)),
            Expanded(child: Align(alignment: Alignment.centerLeft, child: barre(46, t.ink.withOpacity(0.75)))),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: enLigne ? t.on : t.off, shape: BoxShape.circle),
            ),
          ]),
        );
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: height,
      decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Rail
        Container(
          width: 46,
          padding: const EdgeInsets.fromLTRB(7, 8, 7, 8),
          decoration: BoxDecoration(color: t.bg2, border: Border(right: BorderSide(color: t.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 14, height: 14, color: t.acc),
            const SizedBox(height: 8),
            barre(28, t.ink),
            const SizedBox(height: 5),
            barre(22, t.muted),
            const SizedBox(height: 5),
            barre(25, t.muted),
            const Spacer(),
            barre(18, t.off, h: 4),
          ]),
        ),
        // Contenu
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(color: t.field, border: Border.all(color: t.line)),
                  ),
                ),
                const SizedBox(width: 5),
                Container(width: 26, height: 14, color: t.acc, alignment: Alignment.center, child: barre(12, t.accFg, h: 3)),
              ]),
              const SizedBox(height: 6),
              ligne(true),
              ligne(false),
              ligne(true),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Carte d'une palette : aperçus clair et sombre, nom, phrase ; bordure d'accent quand elle est choisie.
class FsPaletteCard extends StatelessWidget {
  const FsPaletteCard({super.key, required this.palette, required this.selected, this.onTap, this.previewHeight = 104});

  final FsPalette palette;
  final bool selected;
  final VoidCallback? onTap;
  final double previewHeight;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${FsStrings.paletteWord} ${palette.label}',
      child: FsHover(
        onTap: onTap,
        builder: (context, hover, down) => AnimatedContainer(
          duration: FsMotion.quick,
          curve: FsMotion.ease,
          transform: Matrix4.translationValues(0, down ? 1 : 0, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? t.sel : (hover ? t.hov : t.hov.withOpacity(0)),
            border: Border.all(color: selected ? t.acc : t.line, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: FsPalettePreview(palette: palette, brightness: Brightness.light, height: previewHeight)),
              const SizedBox(width: 6),
              Expanded(child: FsPalettePreview(palette: palette, brightness: Brightness.dark, height: previewHeight)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FsText(palette.label, style: FsType.sans(16, FontWeight.w800, em: -0.02, color: t.ink)),
              ),
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: FsMotion.quick,
                curve: FsMotion.ease,
                child: Icon(Icons.check_circle_rounded, size: 20, color: t.acc),
              ),
            ]),
            const SizedBox(height: 2),
            FsText(palette.description, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Les deux cartes, côte à côte (ou l'une sous l'autre sur un écran étroit).
class FsPalettePicker extends StatelessWidget {
  const FsPalettePicker({super.key, required this.selected, required this.onSelect, this.previewHeight = 104});

  final FsPalette selected;
  final ValueChanged<FsPalette> onSelect;
  final double previewHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final etroit = c.maxWidth < 520;
      final cartes = [
        for (final p in FsPalette.values)
          FsPaletteCard(palette: p, selected: p == selected, onTap: () => onSelect(p), previewHeight: previewHeight),
      ];
      if (etroit) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cartes[0],
          const SizedBox(height: 10),
          cartes[1],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: cartes[0]),
        const SizedBox(width: 12),
        Expanded(child: cartes[1]),
      ]);
    });
  }
}
