// FS Support — Mode « Ecran client » (ecran mural d'un client, gere a distance sans intervention).
//
// Ce mode remplace et englobe l'ancien reglage « Acces direct » : un seul reglage, pas deux.
// Il comprend :
//   - un assistant de mise en place (FsClientScreenWizard), propose au premier lancement sur Android
//     puis accessible depuis l'ecran serveur, avec de gros boutons qui se cochent tout seuls quand
//     l'etat reel est bon (verification periodique + au retour de l'appli) ;
//   - l'activation du mode : mot de passe permanent, approbation « mot de passe seulement »,
//     demarrage au boot, et cote Kotlin la validation automatique (accessibilite) de la fenetre de
//     capture et de l'installateur de mise a jour, plus la notification « geree a distance ».
//
// Cote serveur (FsShareBody.footer) : FsClientScreenSection resume l'etat et ouvre l'assistant.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart' show setPasswordDialog;
import 'package:fs_ui/fs_ui.dart';

// common.dart définit aussi une classe Dialog : on garde celle de Material.
import '../common.dart' hide Dialog;
import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';

/// Le mode « Ecran client » est-il actif (option locale) ?
bool fsClientScreenEnabled() =>
    bind.mainGetLocalOption(key: kOptionFsClientScreen) == 'Y';

/// Migre un appareil deja configure en « Acces direct » (ancienne cle) vers « Ecran client ».
Future<void> fsMigrateLegacyDirectAccess() async {
  if (!isAndroid) return;
  if (fsClientScreenEnabled()) return;
  if (bind.mainGetLocalOption(key: kOptionFsDirectAccessLegacy) != 'Y') return;
  await bind.mainSetLocalOption(key: kOptionFsClientScreen, value: 'Y');
  await bind.mainSetLocalOption(key: kOptionFsDirectAccessLegacy, value: '');
  try {
    await gFFI.invokeMethod(AndroidChannel.kFsSetClientScreen, true);
  } catch (_) {}
}

/// Ouvre l'assistant de mise en place en plein ecran.
Future<void> showFsClientScreenWizard(
    BuildContext context, ServerModel serverModel) async {
  await bind.mainSetLocalOption(
      key: kOptionFsClientScreenWizardSeen, value: 'Y');
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => FsClientScreenWizard(serverModel: serverModel),
    fullscreenDialog: true,
  ));
}

/// Doit-on proposer l'assistant au premier lancement ? (jamais vu + mode inactif)
bool fsShouldOfferWizard() {
  if (!isAndroid) return false;
  if (fsClientScreenEnabled()) return false;
  return bind.mainGetLocalOption(key: kOptionFsClientScreenWizardSeen) != 'Y';
}

// ===========================================================================
// Section posee sous les autorisations de l'ecran serveur (slot footer).
// ===========================================================================
class FsClientScreenSection extends StatefulWidget {
  const FsClientScreenSection({super.key, required this.serverModel});
  final ServerModel serverModel;

  @override
  State<FsClientScreenSection> createState() => _FsClientScreenSectionState();
}

class _FsClientScreenSectionState extends State<FsClientScreenSection> {
  bool _enabled = false;
  bool _forceClicks = false;
  int _ready = 0; // nombre de prerequis au vert
  int _total = 0;
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
    await fsMigrateLegacyDirectAccess();
    final enabled = fsClientScreenEnabled();
    final force =
        bind.mainGetLocalOption(key: kOptionFsForceAccessibilityClicks) == 'Y';
    final steps = await fsComputeClientScreenSteps(widget.serverModel);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _forceClicks = force;
      _ready = steps.where((s) => s.done).length;
      _total = steps.length;
    });
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
          const FsEyebrow('ÉCRAN CLIENT'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FsText(
                      'Écran géré à distance par FS Solutions',
                      style: FsType.sans(16, FontWeight.w700, color: t.ink),
                    ),
                    const SizedBox(height: 2),
                    FsText(
                      _enabled
                          ? 'Mode actif · $_ready/$_total prêts'
                          : 'Mise en place une seule fois sur place, puis plus aucune intervention.',
                      style: FsType.sans(12, FontWeight.w400,
                          color: _enabled && _ready < _total ? t.danger : t.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                _enabled ? Icons.verified_rounded : Icons.tv_rounded,
                size: 22,
                color: _enabled ? t.on : t.muted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          FsButton(
            label: _enabled ? 'Reprendre la mise en place' : 'Assistant de mise en place',
            leading: Icons.auto_fix_high_rounded,
            trailing: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () async {
              await showFsClientScreenWizard(context, widget.serverModel);
              await _refresh();
            },
          ),
          const SizedBox(height: 16),
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
}

// ===========================================================================
// Etape de l'assistant : libelle, etat reel, action, repli manuel.
// ===========================================================================
class FsClientScreenStep {
  FsClientScreenStep({
    required this.title,
    required this.text,
    required this.done,
    required this.onAction,
    required this.actionLabel,
    required this.manual,
  });
  final String title;
  final String text;
  final bool done;
  final Future<void> Function() onAction;
  final String actionLabel;
  final String manual;
}

/// Calcule les etapes et leur etat reel (partage entre l'assistant et le resume du pied).
Future<List<FsClientScreenStep>> fsComputeClientScreenSteps(
    ServerModel serverModel) async {
  final overlayOk = await AndroidPermissionManager.check(kSystemAlertWindow);
  final batteryOk =
      await AndroidPermissionManager.check(kRequestIgnoreBatteryOptimizations);
  var unknownOk = false;
  try {
    unknownOk = (await gFFI.invokeMethod(AndroidChannel.kFsCanInstallUnknown)) == true;
  } catch (_) {}
  final notifOk = androidVersion < 33
      ? true
      : await AndroidPermissionManager.check(kAndroid13Notification);
  final permanentSet =
      (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
  final approve = await bind.mainGetOption(key: kOptionApproveMode);
  final verif = await bind.mainGetOption(key: kOptionVerificationMethod);
  final passwordOk =
      approve == 'password' && verif == kUsePermanentPassword && permanentSet;

  final steps = <FsClientScreenStep>[
    FsClientScreenStep(
      title: 'Contrôle à distance (accessibilité)',
      text:
          'Touchez la ligne « Utiliser FS Support Input » (pas le raccourci), puis Autoriser.',
      done: serverModel.inputOk,
      actionLabel: 'Ouvrir l\'accessibilité',
      onAction: () async {
        try {
          await gFFI.invokeMethod(AndroidChannel.kFsOpenAccessibilityDetails);
        } catch (_) {}
      },
      manual:
          'Réglages > Accessibilité > FS Support Input. Touchez la LIGNE du service (pas « Raccourci »), '
          'puis Autoriser. Sur certains écrans TV, aucun interrupteur n\'apparaît : c\'est normal, '
          'touchez la ligne elle-même.',
    ),
    FsClientScreenStep(
      title: 'Affichage par-dessus les applis',
      text: 'Autorisez FS Support à s\'afficher par-dessus les autres applis.',
      done: overlayOk,
      actionLabel: 'Autoriser l\'affichage',
      onAction: () async {
        if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
          await AndroidPermissionManager.request(kSystemAlertWindow);
        }
      },
      manual:
          'Réglages > Applis > FS Support > Afficher par-dessus les autres applis (ou « Superposition »). '
          'Activez l\'autorisation.',
    ),
    FsClientScreenStep(
      title: 'Mises à jour automatiques',
      text:
          'Autorisez l\'installation de mises à jour FS Support sans intervention.',
      done: unknownOk,
      actionLabel: 'Autoriser les mises à jour',
      onAction: () async {
        try {
          await gFFI.invokeMethod(AndroidChannel.kFsOpenUnknownSources);
        } catch (_) {}
      },
      manual:
          'Réglages > Applis > FS Support > Installer des applis inconnues : activez « Autoriser ».',
    ),
    FsClientScreenStep(
      title: 'Batterie non restreinte',
      text:
          'Laissez FS Support fonctionner en permanence (pas d\'optimisation de batterie).',
      done: batteryOk,
      actionLabel: 'Régler la batterie',
      onAction: () async {
        if (!await AndroidPermissionManager.check(
            kRequestIgnoreBatteryOptimizations)) {
          await AndroidPermissionManager.request(kRequestIgnoreBatteryOptimizations);
        }
      },
      manual:
          'Réglages > Applis > FS Support > Batterie > Sans restriction (ou « Ne pas optimiser »).',
    ),
    if (androidVersion >= 33)
      FsClientScreenStep(
        title: 'Notifications',
        text: 'Autorisez la notification « écran géré à distance ».',
        done: notifOk,
        actionLabel: 'Autoriser les notifications',
        onAction: () async {
          if (!await AndroidPermissionManager.check(kAndroid13Notification)) {
            await AndroidPermissionManager.request(kAndroid13Notification);
          }
        },
        manual:
            'Réglages > Applis > FS Support > Notifications : activez les notifications.',
      ),
    FsClientScreenStep(
      title: 'Mot de passe permanent',
      text:
          'Définissez un mot de passe permanent : l\'écran sera joignable sans clic d\'acceptation.',
      done: passwordOk,
      actionLabel: 'Définir le mot de passe',
      onAction: () async {
        final hasPwd =
            (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
        Future<void> apply() async {
          await serverModel.setApproveMode('password');
          await serverModel.setVerificationMethod(kUsePermanentPassword);
          await serverModel.updatePasswordModel();
        }

        if (!hasPwd) {
          if (isChangePermanentPasswordDisabled()) {
            showToast(translate('Set permanent password'));
            return;
          }
          setPasswordDialog(notEmptyCallback: () {
            apply();
          });
          return;
        }
        await apply();
      },
      manual:
          'Sur l\'écran de partage, touchez « Nouveau mot de passe » et choisissez un mot de passe '
          'permanent. L\'approbation passe alors en « mot de passe seulement ».',
    ),
  ];
  return steps;
}

// ===========================================================================
// Assistant plein ecran.
// ===========================================================================
class FsClientScreenWizard extends StatefulWidget {
  const FsClientScreenWizard({super.key, required this.serverModel});
  final ServerModel serverModel;

  @override
  State<FsClientScreenWizard> createState() => _FsClientScreenWizardState();
}

class _FsClientScreenWizardState extends State<FsClientScreenWizard>
    with WidgetsBindingObserver {
  bool _activated = false; // le mode « Ecran client » a-t-il ete active (ecran d'info passe) ?
  List<FsClientScreenStep> _steps = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activated = fsClientScreenEnabled();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour de l'appli (apres un reglage systeme), on relit l'etat reel tout de suite.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!isAndroid) return;
    await widget.serverModel.checkAndroidPermission();
    final steps = await fsComputeClientScreenSteps(widget.serverModel);
    if (!mounted) return;
    setState(() => _steps = steps);
  }

  Future<void> _activate() async {
    await bind.mainSetLocalOption(key: kOptionFsClientScreen, value: 'Y');
    try {
      await gFFI.invokeMethod(AndroidChannel.kFsSetClientScreen, true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _activated = true);
    await _refresh();
  }

  bool get _allDone => _steps.isNotEmpty && _steps.every((s) => s.done);

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: FsToastHost(
            bottom: 24,
            child: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBar(context, t),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                        child: _activated
                            ? _buildSteps(context, t)
                            : _buildIntro(context, t),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, FsTokens t) {
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(children: [
        const FsMark(size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: FsText('Écran client',
              style: FsType.sans(18, FontWeight.w800, em: -0.03, color: t.ink)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.close_rounded, size: 22, color: t.muted),
          ),
        ),
      ]),
    );
  }

  Widget _buildIntro(BuildContext context, FsTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const FsEyebrow('MODE ÉCRAN CLIENT'),
        const SizedBox(height: 8),
        FsText(
          'Préparer cet écran pour FS Solutions',
          style: FsType.sans(26, FontWeight.w800, height: 1.08, em: -0.04, color: t.ink),
        ),
        const SizedBox(height: 14),
        FsText(
          'Une fois ce mode activé, FS Solutions pourra voir et contrôler cet écran à distance '
          'pour l\'assistance, sans qu\'une personne soit présente. Une notification permanente '
          '« Écran géré à distance par FS Solutions » reste affichée, et FS Support valide seul les '
          'fenêtres système de capture d\'écran et de mise à jour (uniquement quand elles le concernent).',
          style: FsType.sans(15, FontWeight.w400, height: 1.5, color: t.muted),
        ),
        const SizedBox(height: 14),
        FsText(
          'Vous installez cet écran une seule fois, puis aucune intervention sur place ne sera '
          'nécessaire. Activez le mode pour lancer la mise en place.',
          style: FsType.sans(15, FontWeight.w400, height: 1.5, color: t.muted),
        ),
        const SizedBox(height: 24),
        FsButton(
          label: 'Activer le mode Écran client',
          leading: Icons.check_circle_rounded,
          expand: true,
          height: 56,
          fontSize: 16,
          onPressed: _activate,
        ),
      ],
    );
  }

  Widget _buildSteps(BuildContext context, FsTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const FsEyebrow('MISE EN PLACE'),
        const SizedBox(height: 6),
        FsText(
          _allDone ? 'Écran prêt' : 'Encore quelques réglages',
          style: FsType.sans(24, FontWeight.w800, height: 1.1, em: -0.04, color: t.ink),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _steps.length; i++) ...[
          _StepCard(
            index: i + 1,
            step: _steps[i],
            onManual: () => _showManual(context, _steps[i]),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: FsMotion.theme,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _allDone ? t.acc : t.bg2,
            border: Border.all(color: _allDone ? t.acc : t.line),
          ),
          child: Row(children: [
            Icon(_allDone ? Icons.verified_rounded : Icons.hourglass_bottom_rounded,
                size: 24, color: _allDone ? t.accFg : t.muted),
            const SizedBox(width: 12),
            Expanded(
              child: FsText(
                _allDone
                    ? 'Écran prêt : géré à distance par FS Solutions.'
                    : 'Cochez chaque étape ci-dessus. Elles se valident toutes seules.',
                style: FsType.sans(14, FontWeight.w600,
                    color: _allDone ? t.accFg : t.ink),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_allDone)
          FsButton(
            label: 'Terminer',
            leading: Icons.done_all_rounded,
            expand: true,
            height: 52,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }

  void _showManual(BuildContext context, FsClientScreenStep step) {
    final t = FsTokens.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FsText('Je ne trouve pas',
                  style: FsType.sans(13, FontWeight.w900, em: 0.14, color: t.muted)),
              const SizedBox(height: 10),
              FsText(step.title,
                  style: FsType.sans(18, FontWeight.w800, color: t.ink)),
              const SizedBox(height: 12),
              FsText(step.manual,
                  style: FsType.sans(14, FontWeight.w400, height: 1.5, color: t.muted)),
              const SizedBox(height: 18),
              FsButton(
                label: 'Compris',
                expand: true,
                onPressed: () => Navigator.of(ctx).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard(
      {required this.index, required this.step, required this.onManual});
  final int index;
  final FsClientScreenStep step;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final done = step.done;
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: done ? t.sel : t.bg2,
        border: Border.all(color: done ? t.on : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: FsMotion.fade,
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? t.on : t.field,
                  border: Border.all(color: done ? t.on : t.line),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 18, color: t.bg)
                    : FsText('$index',
                        style: FsType.sans(15, FontWeight.w800, color: t.ink)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FsText(step.title,
                        style: FsType.sans(16, FontWeight.w700, color: t.ink)),
                    const SizedBox(height: 3),
                    FsText(step.text,
                        style: FsType.sans(13, FontWeight.w400,
                            height: 1.4, color: t.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FsButton(
                label: done ? 'Refaire' : step.actionLabel,
                kind: done ? FsButtonKind.ghost : FsButtonKind.primary,
                leading: done ? Icons.refresh_rounded : Icons.open_in_new_rounded,
                expand: true,
                height: 48,
                onPressed: () => step.onAction(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onManual,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: FsText('Je ne trouve pas',
                    style: FsType.sans(12, FontWeight.w600, color: t.muted)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
