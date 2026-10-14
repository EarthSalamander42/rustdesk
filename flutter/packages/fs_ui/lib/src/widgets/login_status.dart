// Fenêtre « Se connecter » : état de la demande des méthodes de connexion au serveur FS (14/10/2026).
//
// Avant : rien ne s'affichait pendant la requête (sans délai), puis l'erreur brute de la bibliothèque
// réseau (« reqwest … TimedOut »). Désormais : un chargement visible, un message clair en français
// avec « Réessayer », et le détail technique replié, en petit, seulement s'il apporte quelque chose.
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Ce que la fenêtre doit dire.
enum FsLoginOptionsState {
  /// Requête en cours.
  loading,

  /// Serveur injoignable (délai dépassé, pas de réseau, nom introuvable…).
  unreachable,

  /// Le serveur a répondu une erreur HTTP.
  serverError,

  /// Le serveur répond mais n'annonce aucune méthode (FS Connect désactivé).
  unavailable,
}

/// Message affiché pour un état (hors chargement).
String fsLoginOptionsMessage(FsLoginOptionsState state, {int? statusCode}) {
  switch (state) {
    case FsLoginOptionsState.loading:
      return FsStrings.loginLoading;
    case FsLoginOptionsState.unreachable:
      return FsStrings.loginUnreachable;
    case FsLoginOptionsState.serverError:
      return FsStrings.loginServerError(statusCode);
    case FsLoginOptionsState.unavailable:
      return FsStrings.fsConnectUnavailable;
  }
}

/// Chargement, ou message d'erreur + « Réessayer » (+ « Détails techniques » repliés).
class FsLoginOptionsStatus extends StatefulWidget {
  const FsLoginOptionsStatus({
    super.key,
    required this.state,
    this.statusCode,
    this.detail,
    this.onRetry,
  });

  final FsLoginOptionsState state;
  final int? statusCode;

  /// Détail technique (facultatif) : replié par défaut.
  final String? detail;
  final VoidCallback? onRetry;

  @override
  State<FsLoginOptionsStatus> createState() => _FsLoginOptionsStatusState();
}

class _FsLoginOptionsStatusState extends State<FsLoginOptionsStatus> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final loading = widget.state == FsLoginOptionsState.loading;
    final Widget body;
    if (loading) {
      body = Column(
        key: const ValueKey('chargement'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.acc),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FsText(fsLoginOptionsMessage(widget.state),
                  style: FsType.sans(13.5, FontWeight.w600, color: t.muted)),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 2, child: LinearProgressIndicator(color: t.acc, backgroundColor: t.line2)),
        ],
      );
    } else {
      final detail = (widget.detail ?? '').trim();
      body = Column(
        key: ValueKey('erreur-${widget.state.name}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.state == FsLoginOptionsState.unreachable ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
            size: 26,
            color: t.muted,
          ),
          const SizedBox(height: 8),
          FsText(
            fsLoginOptionsMessage(widget.state, statusCode: widget.statusCode),
            textAlign: TextAlign.center,
            style: FsType.sans(14, FontWeight.w600, color: t.ink),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 14),
            FsButton(
              label: FsStrings.retry,
              leading: Icons.refresh_rounded,
              height: 38,
              fontSize: 13.5,
              iconSize: 17,
              hPadding: 16,
              onPressed: widget.onRetry,
            ),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            FsHover(
              onTap: () => setState(() => _details = !_details),
              builder: (context, hover, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                FsText(FsStrings.techDetails,
                    style: FsType.sans(11.5, FontWeight.w600, color: hover ? t.ink : t.muted)),
                AnimatedRotation(
                  turns: _details ? 0.5 : 0,
                  duration: FsMotion.quick,
                  curve: FsMotion.ease,
                  child: Icon(Icons.expand_more_rounded, size: 16, color: t.muted),
                ),
              ]),
            ),
            AnimatedSize(
              duration: FsMotion.accordion,
              curve: FsMotion.ease,
              alignment: Alignment.topCenter,
              child: _details
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(
                        detail,
                        textAlign: TextAlign.center,
                        style: FsType.mono(10.5, FontWeight.w400, color: t.muted),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: AnimatedSwitcher(
        duration: FsMotion.fade,
        switchInCurve: FsMotion.ease,
        switchOutCurve: FsMotion.ease,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: body,
      ),
    );
  }
}
