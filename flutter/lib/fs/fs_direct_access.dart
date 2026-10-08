// FS Support — Reglage « Acces direct (sans intervention sur place) » de l'ecran serveur Android.
//
// Pose sous les autorisations (slot `footer` de FsShareBody). Un interrupteur maitre qui, une
// fois active : impose un mot de passe permanent (ouvre la saisie RustDesk s'il n'y en a pas),
// passe l'approbation en « mot de passe seulement » (plus de clic d'acceptation) et active le
// demarrage au boot. L'etat reel de chaque prerequis est affiche en ✓ / ✗.
//
// Un second interrupteur « Clics compatibles ecrans interactifs » force tous les clics, appuis
// longs et defilements a passer par les noeuds d'accessibilite (option locale lue cote Kotlin).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart' show setPasswordDialog;
import 'package:fs_ui/fs_ui.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';

class FsDirectAccessSection extends StatefulWidget {
  const FsDirectAccessSection({super.key, required this.serverModel});
  final ServerModel serverModel;

  @override
  State<FsDirectAccessSection> createState() => _FsDirectAccessSectionState();
}

class _FsDirectAccessSectionState extends State<FsDirectAccessSection> {
  bool _enabled = false;
  bool _forceClicks = false;

  // Prerequis.
  bool _captureOk = false; // appops PROJECT_MEDIA accordee
  bool _accessibilityOk = false; // service d'accessibilite lie
  bool _overlayOk = false; // SYSTEM_ALERT_WINDOW
  bool _batteryOk = false; // optimisation de batterie ignoree
  bool _passwordOk = false; // mot de passe permanent defini + approbation par mot de passe

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!isAndroid) return;
    final enabled = bind.mainGetLocalOption(key: kOptionFsDirectAccess) == 'Y';
    final force =
        bind.mainGetLocalOption(key: kOptionFsForceAccessibilityClicks) == 'Y';

    final overlay = await AndroidPermissionManager.check(kSystemAlertWindow);
    final battery = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    final permanentSet =
        (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
    final approve = await bind.mainGetOption(key: kOptionApproveMode);
    final verif = await bind.mainGetOption(key: kOptionVerificationMethod);
    final passwordMode = approve == 'password' &&
        verif == kUsePermanentPassword &&
        permanentSet;

    var capture = false;
    final accessibility = widget.serverModel.inputOk;
    try {
      capture = await gFFI.invokeMethod(AndroidChannel.kFsProjectMediaAllowed);
    } catch (_) {
      // Pas Android ou canal indisponible : capture consideree non confirmee.
    }

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _forceClicks = force;
      _captureOk = capture;
      _accessibilityOk = accessibility;
      _overlayOk = overlay;
      _batteryOk = battery;
      _passwordOk = passwordMode;
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (!value) {
      await bind.mainSetLocalOption(key: kOptionFsDirectAccess, value: '');
      await _refresh();
      return;
    }
    // 1. Mot de passe permanent obligatoire : s'il n'y en a pas, on ouvre la saisie RustDesk
    //    existante (on n'en genere jamais en silence).
    final hasPwd =
        (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
    if (!hasPwd) {
      if (isChangePermanentPasswordDisabled()) {
        showToast(translate('Set permanent password'));
        return;
      }
      setPasswordDialog(notEmptyCallback: () {
        _applyEnable();
      });
      return;
    }
    await _applyEnable();
  }

  Future<void> _applyEnable() async {
    // 2. Approbation par mot de passe seulement (plus de clic d'acceptation) + mot de passe permanent.
    await widget.serverModel.setApproveMode('password');
    await widget.serverModel.setVerificationMethod(kUsePermanentPassword);

    // 3. Demarrage au boot (memes permissions que l'ecran Reglages).
    if (!await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations)) {
      await AndroidPermissionManager.request(kRequestIgnoreBatteryOptimizations);
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      await AndroidPermissionManager.request(kSystemAlertWindow);
    }
    await gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, true);

    await bind.mainSetLocalOption(key: kOptionFsDirectAccess, value: 'Y');
    await widget.serverModel.updatePasswordModel();
    await _refresh();
  }

  Future<void> _setForceClicks(bool value) async {
    await bind.mainSetLocalOption(
        key: kOptionFsForceAccessibilityClicks, value: value ? 'Y' : '');
    if (!mounted) return;
    setState(() => _forceClicks = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.ink, width: 2),
          bottom: BorderSide(color: t.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FsEyebrow('ACCÈS DIRECT'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FsText(
                  'Accès direct (sans intervention sur place)',
                  style: FsType.sans(16, FontWeight.w700, color: t.ink),
                ),
              ),
              const SizedBox(width: 12),
              FsToggle(value: _enabled, onChanged: (v) => _setEnabled(v)),
            ],
          ),
          const SizedBox(height: 4),
          FsText(
            'Mot de passe permanent, approbation sans clic, démarrage au boot.',
            style: FsType.sans(12, FontWeight.w400, color: t.muted),
          ),
          const SizedBox(height: 14),
          _status('Capture autorisée d\'office', _captureOk,
              'Lancer acces-direct.ps1 (appops PROJECT_MEDIA).'),
          _status('Accessibilité (contrôle à distance)', _accessibilityOk,
              'Activer dans Réglages > Accessibilité, ou acces-direct.ps1.'),
          _status('Fenêtre par-dessus l\'écran', _overlayOk,
              'Autoriser « Superposition », ou acces-direct.ps1.'),
          _status('Batterie non restreinte', _batteryOk,
              'Ignorer l\'optimisation de batterie, ou acces-direct.ps1.'),
          _status('Mot de passe permanent', _passwordOk,
              'Définir un mot de passe permanent ci-dessus.'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FsText(
                      'Clics compatibles écrans interactifs',
                      style: FsType.sans(15, FontWeight.w600, color: t.ink),
                    ),
                    const SizedBox(height: 2),
                    FsText(
                      'À activer si l\'écran se voit mais que seuls Accueil et Retour répondent.',
                      style: FsType.sans(12, FontWeight.w400, color: t.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FsToggle(value: _forceClicks, onChanged: (v) => _setForceClicks(v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _status(String label, bool ok, String hint) {
    final t = FsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18, color: ok ? t.on : t.off),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FsText(label, style: FsType.sans(14, FontWeight.w500, color: t.ink)),
                if (!ok)
                  FsText(hint, style: FsType.sans(11, FontWeight.w400, color: t.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
