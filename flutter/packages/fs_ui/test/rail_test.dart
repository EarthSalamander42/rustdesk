// Rail de l'accueil sur petit écran (14/10/2026) : le haut défile, Paramètres et crédit restent en bas,
// flèches et fondus quand du contenu est caché ; aucun bouton du rail ne déborde de sa carte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_ui/fs_ui.dart';

Widget _app(Widget child, {Size taille = const Size(1280, 720)}) => MediaQuery(
      data: MediaQueryData(size: taille),
      child: MaterialApp(
        theme: fsAtelierTheme(null, Brightness.light),
        home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
      ),
    );

Widget _carteSurSite() => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFC7C9B8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FsText(FsStrings.onsiteTitle, style: FsType.sans(13, FontWeight.w700)),
        const SizedBox(height: 10),
        const FsButton(
          label: FsStrings.onsiteButton,
          kind: FsButtonKind.ghost,
          height: 36,
          fontSize: 12.5,
          iconSize: 16,
          hPadding: 10,
          expand: true,
          leading: Icons.home_repair_service_outlined,
        ),
      ]),
    );

void main() {
  for (final largeur in [140.0, 206.0, 236.0]) {
    testWidgets('bouton pleine largeur sans débordement à ${largeur.toInt()} px (libellé long)', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        width: largeur,
        child: const FsButton(
          label: 'Demander une intervention sur site, avec un libellé vraiment très long',
          leading: Icons.home_repair_service_outlined,
          trailing: Icons.arrow_forward_rounded,
          height: 36,
          expand: true,
        ),
      )));
      expect(tester.takeException(), isNull);
      // Le cadre suit le texte (2 lignes au plus) et ne descend jamais sous la hauteur demandée.
      expect(tester.getSize(find.byType(FsButton)).height, greaterThanOrEqualTo(36));
      expect(tester.getSize(find.byType(FsButton)).width, largeur);
    });
  }

  testWidgets('carte « Besoin d’un technicien sur place ? » sans débordement dans le rail', (tester) async {
    await tester.pumpWidget(_app(SizedBox(width: 206, child: _carteSurSite())));
    expect(tester.takeException(), isNull);
  });

  for (final taille in const [Size(1280, 720), Size(1024, 576), Size(1093, 614), Size(853, 480)]) {
    // 1280×720 et 1366×768 à 125 % / 150 % donnent ces surfaces logiques (ou plus petites).
    testWidgets('rail ${taille.width.toInt()}×${taille.height.toInt()} : le haut défile, le pied reste en bas', (tester) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        SizedBox(
          height: taille.height,
          child: FsRail(
            me: const SizedBox(height: 220),
            nav: Column(children: [for (var i = 0; i < 9; i++) SizedBox(height: FsDims.navItem, child: Text('Entrée $i'))]),
            extra: _carteSurSite(),
            version: '1.0.120',
            onSettings: () {},
          ),
        ),
        taille: taille,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Paramètres toujours visible et cliquable.
      expect(find.text(FsStrings.settings).hitTestable(), findsOneWidget);
      final etat = tester.state<FsRailScrollState>(find.byType(FsRailScroll));
      if (!etat.hiddenBelow) return; // assez de place : rien à faire défiler
      expect(etat.hiddenAbove, isFalse);
      // Flèche vers le bas : défilement en douceur, puis flèche vers le haut.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(etat.hiddenAbove, isTrue);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded).hitTestable(), findsOneWidget);
      // Jusqu'en bas : la carte « sur site » devient visible.
      for (var i = 0; i < 6 && etat.hiddenBelow; i++) {
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pumpAndSettle();
      }
      expect(etat.hiddenBelow, isFalse);
      expect(find.text(FsStrings.onsiteButton).hitTestable(), findsOneWidget);
      expect(find.text(FsStrings.settings).hitTestable(), findsOneWidget);
    });
  }
}
