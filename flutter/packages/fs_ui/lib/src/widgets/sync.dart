// Indicateur de synchronisation des appareils avec le compte FS Solutions (14/10/2026).
//
// Hors connexion FS Connect : « Appareils enregistrés sur ce PC seulement — connectez-vous pour les
// sauvegarder » et un bouton « Se connecter ». Connecté : « Synchronisation… » pendant un chargement
// ou un envoi, une coche « Synchronisé » discrète une fois le carnet chargé et rien en attente, et
// « Synchronisation impossible, nouvel essai… » après un échec (le client réessaie seul).
// L'état vient de [fsSyncStateOf], fonction pure testée (test/sync_test.dart) : elle s'appuie sur
// l'état réel du carnet (chargement réussi, envoi en attente, erreurs), pas sur la seule présence
// d'un jeton de connexion.
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

enum FsSyncState {
  /// Pas de compte : les appareils restent sur ce poste.
  localOnly,

  /// Chargement du carnet ou envoi d'appareils en cours (ou en attente).
  syncing,

  /// Carnet chargé, rien en attente.
  synced,

  /// Dernier essai en échec ; un nouvel essai est programmé.
  error,
}

/// État de l'indicateur.
///
/// - [signedIn] : un compte FS Connect est connecté ;
/// - [loaded] : le carnet personnel du compte a été chargé avec succès (et c'est bien un carnet FS) ;
/// - [busy] : chargement ou envoi en cours ;
/// - [hasError] : dernier chargement ou envoi en échec (réseau, serveur, refus) ;
/// - [pending] : appareils de ce poste pas encore envoyés au carnet.
///
/// Une erreur reste affichée pendant les nouveaux essais, jusqu'au premier succès : l'indicateur ne
/// clignote pas entre « Synchronisation… » et « impossible » toutes les 30 secondes.
FsSyncState fsSyncStateOf({
  required bool signedIn,
  required bool loaded,
  required bool busy,
  required bool hasError,
  required int pending,
}) {
  if (!signedIn) return FsSyncState.localOnly;
  if (hasError) return FsSyncState.error;
  if (busy || !loaded || pending > 0) return FsSyncState.syncing;
  return FsSyncState.synced;
}

/// Libellé d'un état connecté.
String fsSyncLabel(FsSyncState state) {
  switch (state) {
    case FsSyncState.localOnly:
      return FsStrings.syncLocalOnlyPc;
    case FsSyncState.syncing:
      return FsStrings.syncInProgress;
    case FsSyncState.synced:
      return FsStrings.syncDone;
    case FsSyncState.error:
      return FsStrings.syncFailed;
  }
}

/// Pastille d'état connecté (coche, rotation, alerte), en fondu d'un état à l'autre.
class FsSyncBadge extends StatelessWidget {
  const FsSyncBadge({super.key, required this.state, this.tooltip});

  final FsSyncState state;

  /// Infobulle (ex. heure du dernier succès).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final Color fg;
    final Widget icon;
    switch (state) {
      case FsSyncState.synced:
        fg = t.muted;
        icon = Icon(Icons.check_circle_rounded, key: const ValueKey('ok'), size: 15, color: t.on);
        break;
      case FsSyncState.error:
        fg = t.danger;
        icon = Icon(Icons.sync_problem_rounded, key: const ValueKey('ko'), size: 15, color: t.danger);
        break;
      case FsSyncState.syncing:
      case FsSyncState.localOnly:
        fg = t.muted;
        icon = _FsSpin(key: const ValueKey('sync'), color: t.acc);
        break;
    }
    Widget badge = AnimatedSwitcher(
      duration: FsMotion.fade,
      switchInCurve: FsMotion.ease,
      switchOutCurve: FsMotion.ease,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(anim), child: child),
      ),
      child: Row(
        key: ValueKey(state),
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Flexible(
            child: FsText(fsSyncLabel(state),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FsType.sans(12.5, FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) badge = Tooltip(message: tooltip!, child: badge);
    return Semantics(label: fsSyncLabel(state), liveRegion: true, child: badge);
  }
}

/// Bandeau « Appareils enregistrés sur ce PC seulement — connectez-vous pour les sauvegarder ».
class FsSyncLocalBanner extends StatelessWidget {
  const FsSyncLocalBanner({super.key, required this.onSignIn, this.mobile = false});

  final VoidCallback? onSignIn;

  /// Téléphone ou tablette : « sur cet appareil » au lieu de « sur ce PC », bouton sous le texte.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final text = FsText(
      mobile ? FsStrings.syncLocalOnlyDevice : FsStrings.syncLocalOnlyPc,
      style: FsType.sans(13, FontWeight.w500, color: t.ink),
    );
    final button = onSignIn == null
        ? null
        : FsButton(
            label: FsStrings.connect,
            trailing: Icons.login_rounded,
            height: 34,
            fontSize: 13,
            iconSize: 16,
            hPadding: 14,
            onPressed: onSignIn,
          );
    final icon = Icon(Icons.cloud_off_rounded, size: 18, color: t.muted);
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: t.bg2, border: Border.all(color: t.line)),
      child: mobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: icon),
                const SizedBox(width: 10),
                Expanded(child: text),
              ]),
              if (button != null) ...[const SizedBox(height: 8), button],
            ])
          : Row(children: [
              icon,
              const SizedBox(width: 10),
              Expanded(child: text),
              if (button != null) ...[const SizedBox(width: 12), button],
            ]),
    );
  }
}

/// Icône de synchronisation qui tourne doucement.
class _FsSpin extends StatefulWidget {
  const _FsSpin({super.key, required this.color});
  final Color color;

  @override
  State<_FsSpin> createState() => _FsSpinState();
}

class _FsSpinState extends State<_FsSpin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accessibilité : pas de rotation si l'appareil demande moins d'animations.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return Icon(Icons.sync_rounded, size: 15, color: widget.color);
    }
    return RotationTransition(
      turns: Tween(begin: 0.0, end: -1.0).animate(_c),
      child: Icon(Icons.sync_rounded, size: 15, color: widget.color),
    );
  }
}
