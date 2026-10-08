// FS Support — écran Android « Partager mon écran » (Atelier), branché sur le ServerModel de RustDesk.
//
// Accroche dans `mobile/pages/server_page.dart` (`_ServerPageState.build`) : le corps RustDesk (cartes
// « Votre appareil », « Le service ne fonctionne pas », « Autorisations ») cède la place à [FsMobileShare].
// Les actions restent celles de RustDesk : démarrage/arrêt du service (avec l'avertissement anti-arnaque),
// bascules d'autorisations, liste des connexions (`ConnectionManager`), nouveau mot de passe.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart';
import '../consts.dart';
import '../mobile/pages/server_page.dart' show ConnectionManager, showScamWarning;
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'fs_direct_access.dart';

/// Active l'écran de partage de l'Atelier sur Android.
const bool kFsAtelierMobile = true;

class FsMobileShare extends StatefulWidget {
  const FsMobileShare({super.key, required this.serverModel});
  final ServerModel serverModel;

  @override
  State<FsMobileShare> createState() => _FsMobileShareState();
}

class _FsMobileShareState extends State<FsMobileShare> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  bool get _scamWarningDue =>
      gFFI.userModel.userName.value.isEmpty && bind.mainGetLocalOption(key: 'show-scam-warning') != 'N';

  @override
  Widget build(BuildContext context) {
    final m = widget.serverModel;
    final showOneTime = m.approveMode != 'click' && m.verificationMethod != kUsePermanentPassword;
    final hideStopService = isAndroid && bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final allowPermChange = option2bool(
        kOptionEnablePermChangeInAcceptWindow, bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow));
    final locked = isAndroid && m.clients.any((c) => !c.disconnected) && !allowPermChange;
    final id = m.serverId.value.text.trim();

    VoidCallback? toggle() {
      if (!m.isStart) {
        return () => _scamWarningDue ? showScamWarning(context, m) : m.toggleService();
      }
      return hideStopService ? null : m.toggleService;
    }

    final perms = <FsPermission>[
      if (!hideStopService || !m.mediaOk)
        FsPermission(
          icon: Icons.screenshot_monitor_rounded,
          label: FsStrings.screenCapture,
          value: m.mediaOk,
          onChanged: (_) => !m.mediaOk && _scamWarningDue ? showScamWarning(context, m) : m.toggleService(),
        ),
      FsPermission(
        icon: Icons.touch_app_rounded,
        label: FsStrings.remoteInput,
        value: m.inputOk,
        warning: FsStrings.accessibilityTodo,
        onChanged: (_) => m.toggleInput(),
      ),
      // Carte native « Demande de prise en main » par-dessus les autres applis (MainService.kt) :
      // la bascule ouvre le réglage système ; l'état est relu par ServerPage toutes les 3 s.
      if (isAndroid)
        FsPermission(
          icon: Icons.layers_rounded,
          label: FsStrings.overlay,
          value: m.overlayOk,
          warning: FsStrings.overlayTodo,
          onChanged: (_) => m.openOverlayPermissionSettings(),
        ),
      FsPermission(
        icon: Icons.folder_open_rounded,
        label: FsStrings.fileTransfer,
        value: m.fileOk,
        onChanged: locked ? null : (_) => m.toggleFile(),
      ),
      if (androidVersion >= 30)
        FsPermission(
          icon: Icons.mic_none_rounded,
          label: FsStrings.audio,
          value: m.audioOk,
          onChanged: locked ? null : (_) => m.toggleAudio(),
        ),
      FsPermission(
        icon: Icons.content_paste_rounded,
        label: FsStrings.clipboard,
        value: m.clipboardOk,
        onChanged: locked ? null : (_) => m.toggleClipboard(),
      ),
    ];

    return FsToastHost(
      bottom: 24,
      child: Builder(
        builder: (context) => FsShareBody(
          controller: m.controller,
          header: buildPresetPasswordWarningMobile(),
          id: fsFormatId(id.replaceAll(' ', '')),
          password: showOneTime ? m.serverPasswd.value.text : '-',
          running: m.isStart,
          version: _version,
          onToggle: toggle(),
          onRefresh: showOneTime ? () => bind.mainUpdateTemporaryPassword() : null,
          onCopyId: () {
            Clipboard.setData(ClipboardData(text: id.replaceAll(' ', '')));
            FsToastHost.of(context)?.show(FsStrings.idCopied);
          },
          permissions: perms,
          connections: const ConnectionManager(),
          // FS Support : reglage « Acces direct » (prise en main sans personne devant l'ecran).
          footer: isAndroid ? FsDirectAccessSection(serverModel: m) : null,
        ),
      ),
    );
  }
}
