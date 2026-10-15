// Bouton « Continuer avec FS Connect » (15/10/2026) : contraste AA dans les 4 thèmes, rendu sans débordement
// de 280 à 480 px (clair / sombre, Atelier / Ardoise), états chargement / erreur / désactivé, clavier.
//
// Les planches « captures » (tag `captures`) ne comparent rien : la CI les produit avec `--update-goldens`
// et les dépose dans la pré-release publique fs-test, pour les voir sans compte GitHub.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_ui/fs_ui.dart';

/// Ressources du paquet lues sur le disque (le test tourne depuis la racine du paquet).
class _DisqueBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final chemin = key.startsWith('packages/fs_ui/') ? key.substring('packages/fs_ui/'.length) : key;
    final octets = await File(chemin).readAsBytes();
    return ByteData.sublistView(octets);
  }
}

final _bundle = _DisqueBundle();

class _Theme {
  const _Theme(this.nom, this.palette, this.brightness);
  final String nom;
  final FsPalette palette;
  final Brightness brightness;
  FsTokens get tokens => FsTokens.forBrightness(brightness, palette);
}

const _themes = [
  _Theme('atelier-clair', FsPalette.atelier, Brightness.light),
  _Theme('atelier-sombre', FsPalette.atelier, Brightness.dark),
  _Theme('ardoise-clair', FsPalette.ardoise, Brightness.light),
  _Theme('ardoise-sombre', FsPalette.ardoise, Brightness.dark),
];

Widget _app(_Theme th, Widget child, {bool reduireAnimations = false}) => DefaultAssetBundle(
      bundle: _bundle,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fsAtelierTheme(null, th.brightness, th.palette),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduireAnimations),
            child: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
          ),
        ),
      ),
    );

void main() {
  group('contraste (WCAG AA)', () {
    for (final th in _themes) {
      test(th.nom, () {
        final t = th.tokens;
        final c = FsConnectColors.of(t);
        // Texte du bouton (normal et chargement) : 4,5:1.
        expect(fsContrastRatio(c.label, c.background), greaterThanOrEqualTo(4.5), reason: 'libellé / fond');
        // Lettres du monogramme sur le carré : traitées comme du texte.
        expect(fsContrastRatio(c.glyph, c.tile), greaterThanOrEqualTo(4.5), reason: 'monogramme / carré');
        // Carré du monogramme et filet de focus (plein accent) : 3:1 contre le fond du bouton et de la fenêtre.
        expect(fsContrastRatio(c.tile, c.background), greaterThanOrEqualTo(3), reason: 'carré / fond');
        expect(fsContrastRatio(t.acc, c.background), greaterThanOrEqualTo(3), reason: 'focus / fond du bouton');
        expect(fsContrastRatio(t.acc, t.bg), greaterThanOrEqualTo(3), reason: 'focus / fenêtre');
        // Encadré d'erreur : message 4,5:1, pictogramme et filet gauche 3:1.
        expect(fsContrastRatio(c.errorText, c.errorBackground), greaterThanOrEqualTo(4.5), reason: 'erreur');
        expect(fsContrastRatio(c.errorAccent, c.errorBackground), greaterThanOrEqualTo(3), reason: 'pictogramme');
        expect(fsContrastRatio(c.errorDetail, c.errorBackground), greaterThanOrEqualTo(4.5), reason: 'détail');
        // Lien « Annuler » sur le fond de la fenêtre.
        expect(fsContrastRatio(c.link, t.bg), greaterThanOrEqualTo(4.5), reason: 'Annuler');
        expect(fsContrastRatio(c.linkHover, t.bg), greaterThanOrEqualTo(4.5), reason: 'Annuler (survol)');
      });
    }
  });

  group('rendu', () {
    for (final th in _themes) {
      for (final largeur in const [280.0, 360.0, 480.0]) {
        testWidgets('${th.nom} à ${largeur.toInt()} px : pleine largeur, 46 px au moins, sans débordement',
            (tester) async {
          await tester.pumpWidget(_app(th, SizedBox(width: largeur, child: FsConnectButton(onPressed: () {}))));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          final taille = tester.getSize(find.byType(FsConnectButton));
          expect(taille.width, largeur);
          expect(taille.height, greaterThanOrEqualTo(FsConnectDims.minHeight));
          expect(find.text(FsStrings.fsConnectContinue), findsOneWidget);
        });

        testWidgets('${th.nom} à ${largeur.toInt()} px : chargement et erreur sans débordement', (tester) async {
          await tester.pumpWidget(_app(
              th,
              SizedBox(
                width: largeur,
                child: Column(children: [
                  FsConnectButton(loading: true, onPressed: () {}, onCancel: () {}),
                  const SizedBox(height: 16),
                  FsConnectButton(
                    onPressed: () {},
                    error: FsStrings.fsConnectFailed,
                    errorDetail: 'Délai dépassé en joignant connect.fs-solutions.fr',
                  ),
                ]),
              )));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('dans une fenêtre à largeur intrinsèque (AlertDialog)', (tester) async {
      await tester.pumpWidget(_app(
          _themes.first,
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(width: double.infinity, child: FsConnectButton(onPressed: () {})),
                ),
              ]),
            ),
          )));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FsConnectButton)).width, 400);
    });

    testWidgets('animations réduites : aucune exception, rendu immédiat', (tester) async {
      await tester.pumpWidget(_app(_themes.first, SizedBox(width: 360, child: FsConnectButton(onPressed: () {})),
          reduireAnimations: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('comportement', () {
    testWidgets('un clic lance la connexion', (tester) async {
      var n = 0;
      await tester.pumpWidget(_app(_themes.first, SizedBox(width: 360, child: FsConnectButton(onPressed: () => n++))));
      await tester.tap(find.byType(FsConnectButton));
      expect(n, 1);
    });

    testWidgets('chargement : libellé, cercle, bouton inerte, « Annuler » appelle onCancel', (tester) async {
      var lance = 0, annule = 0;
      await tester.pumpWidget(_app(
          _themes.first,
          SizedBox(
            width: 360,
            child: FsConnectButton(loading: true, onPressed: () => lance++, onCancel: () => annule++),
          )));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(FsStrings.fsConnectInProgress), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text(FsStrings.fsConnectInProgress));
      expect(lance, 0);
      await tester.tap(find.text(FsStrings.fsConnectCancel));
      expect(annule, 1);
    });

    testWidgets('désactivé : rien ne se passe, annoncé comme désactivé', (tester) async {
      final semantique = tester.ensureSemantics();
      await tester.pumpWidget(_app(_themes.first, const SizedBox(width: 360, child: FsConnectButton())));
      await tester.tap(find.byType(FsConnectButton), warnIfMissed: false);
      expect(
        tester.getSemantics(find.bySemanticsLabel(FsStrings.fsConnectContinue)),
        matchesSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: FsStrings.fsConnectContinue),
      );
      semantique.dispose();
    });

    testWidgets('erreur : message affiché, le bouton sert à réessayer', (tester) async {
      var n = 0;
      await tester.pumpWidget(_app(
          _themes.first,
          SizedBox(width: 360, child: FsConnectButton(onPressed: () => n++, error: FsStrings.fsConnectFailed)),
        ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(FsStrings.fsConnectFailed), findsOneWidget);
      await tester.tap(find.text(FsStrings.fsConnectContinue));
      expect(n, 1);
    });

    testWidgets('clavier : Tab puis Entrée ou Espace lance la connexion', (tester) async {
      var n = 0;
      await tester.pumpWidget(_app(_themes.first, SizedBox(width: 360, child: FsConnectButton(onPressed: () => n++))));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(n, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(n, 2);
    });
  });

  // Planches pour Jason : une image par thème, trois largeurs × six états.
  group('captures', () {
    for (final th in _themes) {
      testWidgets('planche ${th.nom}', (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(1440 * 2, 760 * 2);
        addTearDown(tester.view.reset);
        final t = th.tokens;
        const largeurs = [280.0, 360.0, 480.0];
        final etats = <(String, FsConnectButton)>[
          ('Repos', FsConnectButton(onPressed: () {})),
          ('Survol', FsConnectButton(onPressed: () {}, forceHover: true)),
          ('Focus clavier', FsConnectButton(onPressed: () {}, forceFocus: true)),
          ('Chargement', FsConnectButton(loading: true, onPressed: () {}, onCancel: () {})),
          ('Désactivé', const FsConnectButton()),
          (
            'Erreur',
            FsConnectButton(
              onPressed: () {},
              error: FsStrings.fsConnectFailed,
              errorDetail: 'Délai dépassé (8 s)',
            )
          ),
        ];
        // Lettres du monogramme : image décodée pour de vrai (hors horloge simulée) avant la planche.
        final amorce = GlobalKey();
        await tester.pumpWidget(_app(th, SizedBox(key: amorce, width: 10, height: 10)));
        await tester.runAsync(() => precacheImage(
            const ExactAssetImage(FsConnectMonogram.asset, package: 'fs_ui', scale: 1), tester.element(find.byKey(amorce))));
        final cle = GlobalKey();
        await tester.pumpWidget(_app(
          th,
          RepaintBoundary(
            key: cle,
            child: Container(
              color: t.bg,
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                FsText('Bouton FS Connect · ${th.nom}', style: FsType.sans(15, FontWeight.w800, color: t.ink)),
                const SizedBox(height: 4),
                FsText('Largeurs 280, 360 et 480 px', style: FsType.sans(12, FontWeight.w500, color: t.muted)),
                const SizedBox(height: 18),
                for (final (nom, bouton) in etats) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 120,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: FsText(nom, style: FsType.sans(12.5, FontWeight.w700, color: t.muted)),
                      ),
                    ),
                    for (final l in largeurs) ...[
                      SizedBox(width: l, child: bouton),
                      const SizedBox(width: 32),
                    ],
                  ]),
                  const SizedBox(height: 22),
                ],
              ]),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 230));
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(cle), matchesGoldenFile('captures/fs-connect-${th.nom}.png'));
      }, tags: ['captures']);
    }
  });
}
