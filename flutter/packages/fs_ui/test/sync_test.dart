// Logique de l'indicateur de synchronisation des appareils (fsSyncStateOf) et rendu de la pastille.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_ui/fs_ui.dart';

FsSyncState etat({
  bool signedIn = true,
  bool loaded = true,
  bool busy = false,
  bool hasError = false,
  int pending = 0,
}) =>
    fsSyncStateOf(signedIn: signedIn, loaded: loaded, busy: busy, hasError: hasError, pending: pending);

void main() {
  group('fsSyncStateOf', () {
    test('sans compte : appareils de ce poste seulement, quel que soit le reste', () {
      expect(etat(signedIn: false), FsSyncState.localOnly);
      expect(etat(signedIn: false, busy: true, hasError: true, pending: 3), FsSyncState.localOnly);
    });

    test('connecté, carnet chargé, rien en attente : synchronisé', () {
      expect(etat(), FsSyncState.synced);
    });

    test('un jeton ne suffit pas : carnet pas encore chargé = synchronisation', () {
      expect(etat(loaded: false), FsSyncState.syncing);
    });

    test('chargement ou envoi en cours, ou appareils en attente : synchronisation', () {
      expect(etat(busy: true), FsSyncState.syncing);
      expect(etat(pending: 2), FsSyncState.syncing);
    });

    test('un échec reste affiché pendant les nouveaux essais (pas de clignotement)', () {
      expect(etat(hasError: true), FsSyncState.error);
      expect(etat(hasError: true, busy: true), FsSyncState.error);
      expect(etat(hasError: true, loaded: false, pending: 4), FsSyncState.error);
    });
  });

  group('libellés', () {
    test('textes demandés', () {
      expect(fsSyncLabel(FsSyncState.synced), 'Synchronisé');
      expect(fsSyncLabel(FsSyncState.syncing), 'Synchronisation…');
      expect(fsSyncLabel(FsSyncState.error), 'Synchronisation impossible, nouvel essai…');
      expect(FsStrings.syncLocalOnlyPc,
          'Appareils enregistrés sur ce PC seulement — connectez-vous pour les sauvegarder');
    });
  });

  group('rendu', () {
    Widget hote(Widget enfant, {double largeur = 520}) => MaterialApp(
          theme: fsAtelierTheme(null, Brightness.light),
          home: Scaffold(body: Center(child: SizedBox(width: largeur, child: enfant))),
        );

    testWidgets('pastille : passe de « Synchronisation… » à « Synchronisé » en fondu', (tester) async {
      await tester.pumpWidget(hote(const FsSyncBadge(state: FsSyncState.syncing)));
      expect(find.text('Synchronisation…'), findsOneWidget);
      await tester.pumpWidget(hote(const FsSyncBadge(state: FsSyncState.synced)));
      // Fondu de 300 ms : à la fin, seule la coche reste.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Synchronisé'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('bandeau hors connexion : texte + « Se connecter », sans débordement à 360 px', (tester) async {
      var clic = 0;
      await tester.pumpWidget(hote(FsSyncLocalBanner(mobile: true, onSignIn: () => clic++), largeur: 360));
      expect(find.text(FsStrings.syncLocalOnlyDevice), findsOneWidget);
      await tester.tap(find.text(FsStrings.connect));
      expect(clic, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bandeau bureau sans débordement à 480 px', (tester) async {
      await tester.pumpWidget(hote(FsSyncLocalBanner(onSignIn: () {}), largeur: 480));
      expect(tester.takeException(), isNull);
    });
  });
}
