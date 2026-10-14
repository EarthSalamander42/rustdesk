// Couleurs de l'interface : Atelier (charte) et Ardoise (maquette FS Suite).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_ui/fs_ui.dart';

void main() {
  tearDown(() => FsTokens.palette = FsPalette.atelier);

  test('valeur enregistrée -> palette (inconnue ou vide : Atelier)', () {
    expect(FsPalette.fromId('ardoise'), FsPalette.ardoise);
    expect(FsPalette.fromId(' Ardoise '), FsPalette.ardoise);
    expect(FsPalette.fromId('atelier'), FsPalette.atelier);
    expect(FsPalette.fromId(''), FsPalette.atelier);
    expect(FsPalette.fromId(null), FsPalette.atelier);
    expect(FsPalette.fromId('fs-signature'), FsPalette.atelier);
    expect(FsPalette.atelier.label, 'Atelier');
    expect(FsPalette.ardoise.label, 'Ardoise');
  });

  test('Atelier inchangé, Ardoise = valeurs de la maquette FS Suite', () {
    expect(FsTokens.forBrightness(Brightness.light, FsPalette.atelier).bg, const Color(0xFFF7F4EA));
    expect(FsTokens.forBrightness(Brightness.dark, FsPalette.atelier).bg, const Color(0xFF10130D));
    final al = FsTokens.forBrightness(Brightness.light, FsPalette.ardoise);
    expect(al.bg, const Color(0xFFF1F0ED));
    expect(al.ink, const Color(0xFF1D1E1B));
    expect(al.acc, const Color(0xFF3D4238));
    final ad = FsTokens.forBrightness(Brightness.dark, FsPalette.ardoise);
    expect(ad.bg, const Color(0xFF2A2E31));
    expect(ad.acc, const Color(0xFFB7C78F));
    expect(ad.isDark, isTrue);
  });

  test('la palette en vigueur pilote le thème', () {
    FsTokens.palette = FsPalette.ardoise;
    expect(FsTokens.forBrightness(Brightness.light).bg, const Color(0xFFF1F0ED));
    final theme = fsAtelierTheme(null, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF2A2E31));
    expect(theme.extension<FsTokens>()!.acc, const Color(0xFFB7C78F));
    // Un aperçu peut forcer une palette sans changer celle en vigueur.
    expect(fsAtelierTheme(null, Brightness.light, FsPalette.atelier).scaffoldBackgroundColor, const Color(0xFFF7F4EA));
    expect(FsTokens.palette, FsPalette.ardoise);
  });

  for (final largeur in [340.0, 640.0]) {
    testWidgets('choix des deux couleurs sans débordement à ${largeur.toInt()} px', (tester) async {
      FsPalette? choisie;
      await tester.pumpWidget(MaterialApp(
        theme: fsAtelierTheme(null, Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: largeur,
              child: FsPalettePicker(selected: FsPalette.atelier, onSelect: (p) => choisie = p),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Atelier'), findsOneWidget);
      expect(find.text('Ardoise'), findsOneWidget);
      await tester.tap(find.text('Ardoise'));
      expect(choisie, FsPalette.ardoise);
    });
  }
}
