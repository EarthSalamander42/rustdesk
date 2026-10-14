// FS Support : lien d'enrôlement `fs-support://enrol?t=<jeton>` (13/10/2026).
//
// Le CRM de FS Full Flux génère ce lien depuis la fiche d'un client : il range le poste chez ce
// client dans l'inventaire des postes FS Support. Sous Windows, le lien est traité par Rust avant
// l'interface (src/core_main.rs) ; sous macOS et Android, il arrive ici par uni_links et repart
// vers Rust (`main_set_common("fs-enrolment-uri", …)`, voir src/fs_enrolment.rs), qui range le
// jeton et l'envoie avec le prochain sysinfo.

import '../models/platform_model.dart';

/// Même forme que `is_valid_token` côté Rust : 16 à 64 caractères `[A-Za-z0-9_-]`.
final RegExp _fsEnrolTokenRe = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// Lien d'enrôlement, valide ou non (`<schéma>://enrol…`).
bool fsIsEnrolUri(Uri uri) => uri.host.toLowerCase() == 'enrol';

/// Transmet le lien à Rust et renvoie le message à afficher.
String fsHandleEnrolUri(Uri uri) {
  final pathToken = uri.pathSegments.firstWhere((s) => s.isNotEmpty,
      orElse: () => '');
  final token = uri.queryParameters['t'] ?? pathToken;
  if (!_fsEnrolTokenRe.hasMatch(token)) {
    return "Ce lien FS Support n'est pas valide. Demandez-en un nouveau à votre prestataire.";
  }
  bind.mainSetCommon(key: 'fs-enrolment-uri', value: uri.toString());
  return 'Lien reçu : ce poste va être relié à votre dossier client dans quelques instants.';
}
