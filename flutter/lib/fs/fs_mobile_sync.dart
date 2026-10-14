// FS Support — indicateur de synchronisation des appareils sur Android (14/10/2026).
//
// Accroche unique dans `mobile/pages/connection_page.dart` (sous le champ d'ID, au-dessus de la liste
// d'appareils). Même logique que l'accueil du bureau (`fs_saas_devices.dart`) : hors connexion, bandeau
// « Appareils enregistrés sur cet appareil seulement — connectez-vous pour les sauvegarder » + « Se connecter » ;
// connecté, pastille « Synchronisation… » / « Synchronisé » / « Synchronisation impossible, nouvel essai… ».
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/widgets/login.dart';
import '../models/platform_model.dart';
import 'fs_saas_devices.dart';

class FsMobileSyncIndicator extends StatefulWidget {
  const FsMobileSyncIndicator({super.key});

  @override
  State<FsMobileSyncIndicator> createState() => _FsMobileSyncIndicatorState();
}

class _FsMobileSyncIndicatorState extends State<FsMobileSyncIndicator> {
  @override
  void initState() {
    super.initState();
    fsSyncDemarrer();
  }

  @override
  Widget build(BuildContext context) {
    if (bind.isDisableAccount() || bind.isDisableAb()) return const SizedBox.shrink();
    return Obx(() {
      final user = gFFI.userModel;
      final etat = fsSyncEtat();
      final t = FsTokens.of(context);
      final Widget contenu = user.isLogin
          ? Padding(
              key: const ValueKey('compte'),
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Row(children: [
                Flexible(child: FsSyncBadge(state: etat, tooltip: fsSyncInfobulle())),
                const SizedBox(width: 8),
                Flexible(
                  child: FsText('· ${user.displayNameOrUserName}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
                ),
              ]),
            )
          : Padding(
              key: const ValueKey('local'),
              padding: const EdgeInsets.only(bottom: 10),
              child: FsSyncLocalBanner(mobile: true, onSignIn: () => loginDialog()),
            );
      return AnimatedSize(
        duration: FsMotion.slide,
        curve: FsMotion.ease,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(duration: FsMotion.fade, child: contenu),
      );
    });
  }
}
