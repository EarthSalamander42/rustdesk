// FS Support — installation du service macOS : suivi et message d'erreur (20/10/2026).
//
// Avant : la carte « Installer » appelait `mainIsInstalledDaemon(prompt: true)` sans rien attendre ;
// un échec (nom « FS Support » avec espace, mot de passe refusé, launchctl…) restait invisible.
// Le Rust (`src/platform/macos.rs`) range maintenant l'issue dans l'option locale
// `fs-mac-service-install` : "en-cours", "ok" ou "erreur:<message en français>". On la suit ici
// et on affiche toujours un résultat.
import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../models/platform_model.dart';

const kFsMacServiceInstallOption = 'fs-mac-service-install';
const _kDelaiMax = Duration(minutes: 3);

bool _fsMacServiceInstallEnCours = false;

/// Lance l'installation du service et attend son issue ; `rafraichir` redessine les cartes en cas de succès.
Future<void> fsInstallMacService(VoidCallback rafraichir) async {
  if (_fsMacServiceInstallEnCours) return;
  _fsMacServiceInstallEnCours = true;
  try {
    await bind.mainSetLocalOption(key: kFsMacServiceInstallOption, value: '');
    bind.mainIsInstalledDaemon(prompt: true);
    final fin = DateTime.now().add(_kDelaiMax);
    var etat = bind.mainGetLocalOption(key: kFsMacServiceInstallOption);
    while (etat != 'ok' && !etat.startsWith('erreur:') && DateTime.now().isBefore(fin)) {
      await Future.delayed(const Duration(milliseconds: 500));
      etat = bind.mainGetLocalOption(key: kFsMacServiceInstallOption);
    }
    if (etat == 'ok' || bind.mainIsInstalledDaemon(prompt: false)) {
      showToast('Service FS Support installé.');
      rafraichir();
      return;
    }
    final message = etat.startsWith('erreur:')
        ? etat.substring('erreur:'.length)
        : etat == 'en-cours'
            ? "L'installation du service n'a pas abouti au bout de 3 minutes. "
                "Si la fenêtre du mot de passe administrateur est restée cachée derrière FS Support, "
                "validez-la puis réessayez."
            : "L'installation du service n'a pas pu démarrer. Fermez FS Support, rouvrez-le et réessayez.";
    fsMacServiceInstallErreur(message);
  } finally {
    _fsMacServiceInstallEnCours = false;
  }
}

void fsMacServiceInstallErreur(String message) {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('Service FS Support non installé'),
        content: SelectableText(
            '$message\n\nSi le problème persiste, appelez FS Solutions : ce message aide au diagnostic.'),
        actions: [dialogButton('OK', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      ));
}
