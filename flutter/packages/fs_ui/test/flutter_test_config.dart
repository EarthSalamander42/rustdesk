// Configuration commune des tests fs_ui : les vraies polices du paquet (Inter, Archivo Black, JetBrains Mono)
// sont chargées avant chaque fichier de test. Sans elles, flutter_test dessine chaque lettre comme un carré de
// la taille du texte : les mesures de largeur (débordements du rail, des boutons) ne voudraient rien dire.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _charger(String famille, List<String> fichiers) async {
  final loader = FontLoader(famille);
  var n = 0;
  for (final f in fichiers) {
    final file = File('assets/fonts/$f');
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    n++;
  }
  if (n > 0) await loader.load();
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const inter = [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'Inter-ExtraBold.ttf',
    'Inter-Black.ttf',
  ];
  const mono = ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf', 'JetBrainsMono-SemiBold.ttf'];
  // Familles telles que les demande FsType (package: 'fs_ui').
  await _charger('packages/fs_ui/Inter', inter);
  await _charger('packages/fs_ui/ArchivoBlack', ['ArchivoBlack-Regular.ttf']);
  await _charger('packages/fs_ui/JetBrainsMono', mono);
  // Icônes Material (sinon des carrés dans les captures) : police du SDK Flutter utilisé par le test.
  // flutter_tester vit dans <FLUTTER_ROOT>/bin/cache/artifacts/engine/<hôte>/ : la police est dans artifacts/material_fonts.
  final racine = Platform.environment['FLUTTER_ROOT'];
  final candidats = [
    if (racine != null) '$racine/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final chemin in candidats) {
    final icones = File(chemin);
    if (icones.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(icones.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      break;
    }
  }
  await testMain();
}
