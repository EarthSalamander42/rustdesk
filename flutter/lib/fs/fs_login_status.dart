// FS Support — fenêtre « Se connecter » : état de la demande des méthodes de connexion (14/10/2026).
//
// Accroche unique dans `common/widgets/login.dart` (`thirdAuthWidget`) quand [kFsConnectOnly] est vrai.
// Le widget de présentation est dans fs_ui (`FsLoginOptionsStatus`) ; ici, la traduction de l'erreur
// réelle (délai, réseau, HTTP) en état, et le fondu vers le bouton FS Connect.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common/hbbs/hbbs.dart' show RequestException;

/// Délai maximal de la demande des méthodes de connexion.
const Duration kFsLoginOptionsTimeout = Duration(seconds: 8);

/// Chargement / erreur / méthodes, avec un fondu enchaîné entre les trois.
Widget fsLoginOptionsView({
  required bool inProgress,
  required Object? error,
  required bool empty,
  required VoidCallback onRetry,
  required Widget options,
}) {
  FsLoginOptionsState? state;
  int? code;
  String? detail;
  if (inProgress) {
    state = FsLoginOptionsState.loading;
  } else if (error is RequestException) {
    state = FsLoginOptionsState.serverError;
    code = error.statusCode;
    detail = error.cause;
  } else if (error != null) {
    state = FsLoginOptionsState.unreachable;
    // Le délai dépassé se suffit à lui-même ; une autre erreur réseau garde son détail, replié.
    detail = error is TimeoutException ? null : error.toString();
  } else if (empty) {
    state = FsLoginOptionsState.unavailable;
  }
  return AnimatedSize(
    duration: FsMotion.slide,
    curve: FsMotion.ease,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: FsMotion.fade,
      switchInCurve: FsMotion.ease,
      switchOutCurve: FsMotion.ease,
      child: state == null
          ? KeyedSubtree(key: const ValueKey('methodes'), child: options)
          : FsLoginOptionsStatus(
              key: const ValueKey('etat'),
              state: state,
              statusCode: code,
              detail: detail,
              onRetry: state == FsLoginOptionsState.loading ? null : onRetry,
            ),
    ),
  );
}
