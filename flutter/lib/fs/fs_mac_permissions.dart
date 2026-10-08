// FS Support — assistant d'autorisations macOS (Atelier).
//
// Accroche dans `fs/fs_desktop_home.dart` : posé au-dessus du champ de connexion, sur macOS seulement,
// tant qu'une autorisation manque ; il se replie de lui-même quand tout est accordé.
// Vérifications et demandes : celles de RustDesk (`bind.mainIsProcessTrusted`, `bind.mainIsCanScreenRecording`,
// `bind.mainIsCanInputMonitoring`, `prompt: true` pour la demande système), mêmes règles que ses cartes
// « Permissions » (`desktop/pages/desktop_home_page.dart`, `buildHelpCards`), qui se taisent pendant ce temps.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/multi_window_manager.dart';
import '../utils/platform_channel.dart';

/// Une autorisation macOS demandée par RustDesk.
enum FsMacPermission { accessibility, screenRecording, inputMonitoring }

/// Autorisations exigées sur ce poste. Comme RustDesk : en « sortant seulement », ce Mac n'est jamais
/// contrôlé, seule la surveillance de l'entrée (clavier pendant une prise en main) reste utile.
List<FsMacPermission> fsMacRequiredPermissions() {
  if (!isMacOS) return const [];
  final outgoingOnly = bind.isOutgoingOnly();
  return [
    if (!outgoingOnly) FsMacPermission.accessibility,
    if (!outgoingOnly) FsMacPermission.screenRecording,
    FsMacPermission.inputMonitoring,
  ];
}

bool fsMacPermissionGranted(FsMacPermission p) => switch (p) {
      FsMacPermission.accessibility => bind.mainIsProcessTrusted(prompt: false),
      FsMacPermission.screenRecording => bind.mainIsCanScreenRecording(prompt: false),
      FsMacPermission.inputMonitoring => bind.mainIsCanInputMonitoring(prompt: false),
    };

/// Vrai tant qu'une autorisation exigée manque : l'assistant est alors à l'écran.
bool fsMacPermissionsMissing() => fsMacRequiredPermissions().any((p) => !fsMacPermissionGranted(p));

/// Ouvre le bon panneau de Confidentialité (Préférences Système jusqu'à macOS 12, Réglages Système ensuite).
Future<void> fsOpenMacPrivacyPane(FsMacPermission p) async {
  final anchor = switch (p) {
    FsMacPermission.accessibility => 'Privacy_Accessibility',
    FsMacPermission.screenRecording => 'Privacy_ScreenCapture',
    FsMacPermission.inputMonitoring => 'Privacy_ListenEvent',
  };
  try {
    await launchUrl(Uri.parse('x-apple.systempreferences:com.apple.preference.security?$anchor'));
  } catch (_) {}
}

/// Demande système (elle inscrit FS Support, décoché, dans la liste du panneau), puis ouverture du panneau.
Future<void> fsRequestMacPermission(FsMacPermission p) async {
  switch (p) {
    case FsMacPermission.accessibility:
      bind.mainIsProcessTrusted(prompt: true);
    case FsMacPermission.screenRecording:
      bind.mainIsCanScreenRecording(prompt: true);
    case FsMacPermission.inputMonitoring:
      bind.mainIsCanInputMonitoring(prompt: true);
  }
  // Laisse macOS enregistrer la demande : ouvert trop tôt, le panneau n'affiche pas encore FS Support.
  await Future.delayed(const Duration(milliseconds: 700));
  await fsOpenMacPrivacyPane(p);
}

/// Relance FS Support : macOS n'applique l'enregistrement de l'écran qu'à un processus relancé.
/// Un petit script détaché attend la fin de ce processus, relance le service s'il tourne à part
/// (agent de lancement « accès sans surveillance », relancé par launchd avec la nouvelle autorisation)
/// puis rouvre l'application. Faux si la relance n'a pas pu être préparée.
Future<bool> fsRelaunchMacApp() async {
  final exe = Platform.resolvedExecutable; // …/FS Support.app/Contents/MacOS/FS Support
  final bundle = File(exe).parent.parent.parent.path;
  if (!bundle.endsWith('.app')) return false;
  const script = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
if pkill -f "^$3 --server"; then
  sleep 1
  i=0
  while ! pgrep -f "^$3 --server" >/dev/null && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
fi
open "$2"
''';
  try {
    await Process.start('/bin/sh', ['-c', script, 'fs-relance', '$pid', bundle, exe], mode: ProcessStartMode.detached);
  } catch (_) {
    return false;
  }
  try {
    await rustDeskWinManager.closeAllSubWindows();
  } catch (_) {}
  // Même fermeture que RustDesk (`onActiveWindowChanged`), puis sortie forcée si macOS ne ferme pas l'app :
  // le script attend la fin de ce processus avant de rouvrir.
  periodic_immediate(const Duration(milliseconds: 30), RdPlatformChannel.instance.terminate);
  Timer(const Duration(seconds: 3), () => exit(0));
  return true;
}

class _S {
  _S._();

  static const eyebrow = 'Préparer ce Mac';
  static String title(int n) => n == 1 ? 'Encore une autorisation à donner' : '$n autorisations à donner';
  static const intro = 'Cliquez sur « Autoriser », puis cochez FS Support dans la liste qui s’ouvre. Une minute suffit.';
  static const later = 'Plus tard';
  static const allow = 'Autoriser';
  static const allowAgain = 'Rouvrir les Réglages';
  static const settings = 'Réglages';
  static const granted = 'Autorisé';
  static const relaunch = 'Relancer FS Support';
  static const relaunching = 'Relance…';
  static const relaunchFailed = 'Relance impossible : quittez FS Support (⌘Q) puis rouvrez-le.';
  static const recheck = 'Déjà coché ? Décochez-le puis recochez-le.';
}

class _PermText {
  const _PermText(this.icon, this.label, this.why, this.after);
  final IconData icon;
  final String label;
  final String why;

  /// Consigne une fois la demande faite (panneau ouvert).
  final String after;
}

_PermText _text(FsMacPermission p) => switch (p) {
      FsMacPermission.accessibility => const _PermText(
          Icons.touch_app_rounded,
          'Accessibilité',
          'Permet de cliquer et d’écrire sur ce Mac à distance.',
          'Cochez FS Support dans la liste (cadenas fermé : cliquez d’abord dessus). ${_S.recheck}',
        ),
      FsMacPermission.screenRecording => const _PermText(
          Icons.screenshot_monitor_rounded,
          'Enregistrement de l’écran',
          'Permet de voir l’écran de ce Mac à distance.',
          'Cochez FS Support dans la liste, puis relancez l’application : macOS l’exige. ${_S.recheck}',
        ),
      FsMacPermission.inputMonitoring => const _PermText(
          Icons.keyboard_rounded,
          'Surveillance de l’entrée',
          'Permet d’utiliser votre clavier quand vous contrôlez un autre poste.',
          'Cochez FS Support dans la liste. ${_S.recheck}',
        ),
    };

/// Assistant d'autorisations macOS : une ligne par autorisation, état relevé en direct.
class FsMacPermissionsWizard extends StatefulWidget {
  const FsMacPermissionsWizard({super.key});

  @override
  State<FsMacPermissionsWizard> createState() => _FsMacPermissionsWizardState();
}

class _FsMacPermissionsWizardState extends State<FsMacPermissionsWizard> {
  /// « Plus tard » : masqué jusqu'à la prochaine ouverture de FS Support.
  static bool _later = false;

  Timer? _timer;
  Map<FsMacPermission, bool> _granted = const {};
  final Set<FsMacPermission> _asked = {};
  bool _relaunching = false;

  @override
  void initState() {
    super.initState();
    if (!isMacOS) return;
    _granted = _read();
    if (!_later && _granted.containsValue(false)) {
      _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<FsMacPermission, bool> _read() => {for (final p in fsMacRequiredPermissions()) p: fsMacPermissionGranted(p)};

  void _poll() {
    if (!mounted) return;
    final next = _read();
    final changed = next.length != _granted.length || next.entries.any((e) => _granted[e.key] != e.value);
    if (changed) setState(() => _granted = next);
    if (!next.containsValue(false)) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ask(FsMacPermission p) async {
    setState(() => _asked.add(p));
    await fsRequestMacPermission(p);
    _poll();
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    setState(() => _later = true);
  }

  Future<void> _relaunch() async {
    if (_relaunching) return;
    setState(() => _relaunching = true);
    final ok = await fsRelaunchMacApp();
    if (!ok && mounted) {
      setState(() => _relaunching = false);
      FsToastHost.of(context)?.show(_S.relaunchFailed);
    }
  }

  Widget _button(String label, VoidCallback? onPressed,
          {Key? key, IconData? leading, IconData? trailing, FsButtonKind kind = FsButtonKind.primary}) =>
      FsButton(
        key: key,
        label: label,
        onPressed: onPressed,
        leading: leading,
        trailing: trailing,
        kind: kind,
        height: 36,
        fontSize: 13.5,
        iconSize: 17,
        hPadding: 14,
      );

  Widget _actions(FsTokens t, FsMacPermission p, bool ok, bool asked) {
    if (ok) {
      return Row(key: const ValueKey('ok'), mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, size: 18, color: t.on),
        const SizedBox(width: 6),
        FsText(_S.granted, style: FsType.sans(13, FontWeight.w600, color: t.on)),
      ]);
    }
    if (p == FsMacPermission.screenRecording && asked) {
      return Row(key: const ValueKey('relaunch'), mainAxisSize: MainAxisSize.min, children: [
        _button(_S.settings, () => fsOpenMacPrivacyPane(p), kind: FsButtonKind.ghost),
        const SizedBox(width: 8),
        _button(_relaunching ? _S.relaunching : _S.relaunch, _relaunching ? null : _relaunch,
            leading: Icons.restart_alt_rounded),
      ]);
    }
    return _button(asked ? _S.allowAgain : _S.allow, () => _ask(p),
        key: ValueKey(asked ? 'again' : 'ask'),
        trailing: asked ? Icons.open_in_new_rounded : Icons.arrow_forward_rounded,
        kind: asked ? FsButtonKind.ghost : FsButtonKind.primary);
  }

  Widget _row(BuildContext context, FsMacPermission p) {
    final t = FsTokens.of(context);
    final ok = _granted[p] ?? false;
    final asked = _asked.contains(p);
    final txt = _text(p);
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        AnimatedSwitcher(
          duration: FsMotion.fade,
          child: Icon(txt.icon, key: ValueKey(ok), size: 21, color: ok ? t.on : t.muted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FsText(txt.label, style: FsType.sans(14.5, FontWeight.w600, color: t.ink)),
            // Avant la demande : à quoi sert l'autorisation. Après : la consigne, en encre.
            AnimatedSize(
              duration: FsMotion.accordion,
              curve: FsMotion.ease,
              alignment: Alignment.topLeft,
              child: AnimatedSwitcher(
                duration: FsMotion.fade,
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, if (cur != null) cur]),
                child: asked && !ok
                    ? FsText(txt.after, key: const ValueKey('after'), style: FsType.sans(12.5, FontWeight.w600, color: t.ink))
                    : FsText(txt.why, key: const ValueKey('why'), style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        AnimatedSwitcher(duration: FsMotion.fade, child: _actions(t, p, ok, asked)),
      ]),
    );
  }

  Widget _card(BuildContext context, int missing) {
    final t = FsTokens.of(context);
    return ConstrainedBox(
      key: const ValueKey('fs-mac-wizard'),
      // Fenêtre basse : l'assistant défile plutôt que d'écraser la liste des appareils.
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
      child: Container(
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: t.bg2,
          border: Border(
            top: BorderSide(color: t.acc, width: 2),
            left: BorderSide(color: t.line),
            right: BorderSide(color: t.line),
            bottom: BorderSide(color: t.line),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const FsEyebrow(_S.eyebrow),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: FsMotion.fade,
                      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, if (cur != null) cur]),
                      child: FsText(_S.title(missing),
                          key: ValueKey(missing), style: FsType.sans(20, FontWeight.w800, em: -0.03, color: t.ink)),
                    ),
                    const SizedBox(height: 2),
                    FsText(_S.intro, style: FsType.sans(13, FontWeight.w400, color: t.muted)),
                  ]),
                ),
                const SizedBox(width: 16),
                FsHover(
                  onTap: _dismiss,
                  builder: (context, hover, _) =>
                      FsText(_S.later, style: FsType.sans(12.5, FontWeight.w600, color: hover ? t.ink : t.muted)),
                ),
              ]),
            ),
            for (final p in _granted.keys) _row(context, p),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missing = _granted.values.where((g) => !g).length;
    final visible = isMacOS && !_later && missing > 0;
    return AnimatedSize(
      duration: FsMotion.accordion,
      curve: FsMotion.ease,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: FsMotion.fade,
        child: visible ? _card(context, missing) : const SizedBox(key: ValueKey('fs-mac-ok'), width: double.infinity),
      ),
    );
  }
}
