// FS Support : appareils et entreprises rangés dans le SaaS FS Solutions (14/10/2026).
//
// Une fois connecté avec FS Connect (bouton « Se connecter », protocole OIDC de RustDesk Pro implémenté par le SaaS
// sous /fss/api), l'accueil « Appareils » s'appuie sur le carnet d'adresses PERSONNEL du compte, tenu par le SaaS :
// en changeant de PC, on retrouve tous ses appareils, rangés par entreprise. Les entreprises sont les étiquettes du
// carnet (une entreprise par appareil : sa première étiquette).
//
// Aucun nouveau client HTTP : tout passe par `gFFI.abModel` (ab_model.dart, amont RustDesk).
// Hors connexion (ou serveur injoignable), rien ne change : sessions récentes et entreprises locales
// (`fs_company_groups.dart`), comme avant.
//
// Reprise des données locales (`fsSaasSynchroniser`) : à la première connexion d'un compte sur ce poste, les
// entreprises locales deviennent des étiquettes et les sessions récentes des appareils du carnet (avec leur
// entreprise), sans doublon : le SaaS ignore un appareil déjà présent et complète seulement ses champs vides.
// Ensuite, chaque nouvelle session récente rejoint le carnet (« Non classés »). Un appareil retiré du carnet à la main
// n'y revient pas tout seul (le SaaS s'en souvient : ajout marqué `fs_auto`). Aucun mot de passe n'est envoyé.
//
// Indicateur de synchronisation (14/10/2026, `FsSyncBadge` / `FsSyncLocalBanner` de fs_ui) : l'état vient du
// carnet réel — dernier chargement réussi, envoi en attente ou en échec — relevé ici ([fsSyncEtat]). Un moteur
// unique ([fsSyncDemarrer]) relance la synchronisation toutes les 3 minutes, et toutes les 30 secondes après un
// échec (puis toutes les 3 minutes au-delà de 10 échecs), sur le bureau comme sur Android.

import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/widgets/fs_company_groups.dart';
import '../models/ab_model.dart' show ForcePullAb;
import '../models/peer_model.dart';
import '../models/platform_model.dart';

/// Préfixe des réglages de l'Atelier (`ATELIER_OPTION_PREFIX` de `src/fs_support.rs`).
const String _kAtelierPrefix = 'fs-atelier:';

/// Vrai quand l'accueil s'appuie sur le carnet du SaaS : compte connecté, carnet personnel (non « legacy ») chargé,
/// sans erreur de chargement. Lit des valeurs observables : à appeler dans un `Obx` pour suivre les changements.
bool fsSaasActif() {
  final ab = gFFI.abModel;
  final connecte = gFFI.userModel.isLogin;
  final legacy = ab.legacyMode.value;
  final erreur = ab.abPullError.value;
  final current = ab.current;
  return connecte && !legacy && erreur.isEmpty && current.initialized && current.isPersonal();
}

String _cle(String nom) => nom.trim().toLowerCase();

/// Étiquette du carnet portant ce nom (casse d'origine), ou null.
String? fsSaasEtiquette(String nom) {
  final k = _cle(nom);
  for (final t in gFFI.abModel.currentAbTags) {
    if (_cle(t) == k) return t;
  }
  return null;
}

/// Appareil du carnet, ou null.
Peer? fsSaasAppareil(String id) {
  for (final p in gFFI.abModel.currentAbPeers) {
    if (p.id == id) return p;
  }
  return null;
}

/// Entreprise d'un appareil du carnet : sa première étiquette, sinon vide.
String fsSaasEntrepriseDe(Peer peer) {
  final source = peer.tags.isNotEmpty ? peer : fsSaasAppareil(peer.id);
  if (source == null || source.tags.isEmpty) return '';
  return source.tags.first.toString();
}

Future<List<Peer>> _sessionsRecentes() async {
  try {
    final brut = await bind.mainLoadRecentPeersForAb(filter: '[]');
    if (brut.isEmpty) return [];
    final liste = jsonDecode(brut);
    if (liste is! List) return [];
    return liste.whereType<Map<String, dynamic>>().map((m) => Peer.fromJson(m)).toList();
  } catch (e) {
    debugPrint('fsSaas : sessions récentes illisibles : $e');
    return [];
  }
}

/// Appareil prêt à envoyer au carnet : jamais de « hash » ni de « password ».
Map<String, dynamic> _pourCarnet(String id, {Peer? p, String? entreprise, bool auto = true}) => {
      'id': id,
      if (p != null && p.alias.isNotEmpty) 'alias': p.alias,
      if (p != null && p.username.isNotEmpty) 'username': p.username,
      if (p != null && p.hostname.isNotEmpty) 'hostname': p.hostname,
      if (p != null && p.platform.isNotEmpty) 'platform': p.platform,
      'tags': entreprise == null ? <String>[] : <String>[entreprise],
      if (auto) 'fs_auto': true,
    };

/// Range un appareil dans une entreprise du carnet (vide = « Non classés »). L'ajoute au carnet s'il n'y est pas.
Future<void> fsSaasRangerAppareil(String id, String entreprise) async {
  final ab = gFFI.abModel;
  final nom = entreprise.trim();
  String? tag;
  if (nom.isNotEmpty && _cle(nom) != _cle(kFsUnclassified)) {
    tag = fsSaasEtiquette(nom);
    if (tag == null) {
      await ab.addTags([nom]);
      tag = fsSaasEtiquette(nom) ?? nom;
    }
  }
  if (fsSaasAppareil(id) != null) {
    await ab.changeTagForPeers([id], tag == null ? [] : [tag]);
  } else {
    final recents = await _sessionsRecentes();
    Peer? r;
    for (final p in recents) {
      if (p.id == id) r = p;
    }
    await ab.addPeersTo([_pourCarnet(id, p: r, entreprise: tag, auto: false)], ab.currentName.value);
  }
}

/// Renomme une entreprise ; si le nouveau nom existe déjà, ses appareils y sont regroupés.
Future<void> fsSaasRenommerEntreprise(String ancien, String nouveau) async {
  final ab = gFFI.abModel;
  final source = fsSaasEtiquette(ancien);
  final cible = nouveau.trim();
  if (source == null || cible.isEmpty) return;
  final existante = fsSaasEtiquette(cible);
  if (existante != null && _cle(existante) != _cle(source)) {
    final ids = ab.currentAbPeers.where((p) => p.tags.any((t) => _cle(t.toString()) == _cle(source))).map((p) => p.id).toList();
    if (ids.isNotEmpty) await ab.changeTagForPeers(ids, [existante]);
    await ab.deleteTag(source);
  } else {
    await ab.renameTag(source, cible);
  }
}

bool _synchroEnCours = false;
final Set<String> _dejaProposes = {};

// --- État réel de la synchronisation (indicateur) ------------------------------------------------

/// Synchronisation lancée par FS Support en cours (chargement de reprise ou envoi d'appareils).
final RxBool fsSyncEnCours = false.obs;

/// Dernier échec (lecture du carnet ou envoi), vide après un succès.
final RxString fsSyncErreur = ''.obs;

/// Heure du dernier succès complet (carnet chargé, rien en attente).
final Rxn<DateTime> fsSyncReussiLe = Rxn<DateTime>();

/// Appareils de ce poste pas encore arrivés dans le carnet.
final RxInt fsSyncEnAttente = 0.obs;

/// État de l'indicateur, d'après le carnet réel. Lit des valeurs observables : à appeler dans un `Obx`.
FsSyncState fsSyncEtat() {
  final user = gFFI.userModel;
  final ab = gFFI.abModel;
  final connecte = user.isLogin;
  final erreur = fsSyncErreur.value.isNotEmpty ||
      (connecte && user.networkError.value.isNotEmpty) ||
      ab.abPullError.value.isNotEmpty ||
      ab.currentAbPushError.value.isNotEmpty;
  return fsSyncStateOf(
    signedIn: connecte,
    loaded: fsSaasActif(),
    busy: fsSyncEnCours.value || ab.currentAbLoading.value,
    hasError: erreur,
    pending: fsSyncEnAttente.value,
  );
}

/// Infobulle de la pastille : heure du dernier succès.
String fsSyncInfobulle() {
  final d = fsSyncReussiLe.value;
  if (d == null) return '';
  String deux(int n) => n.toString().padLeft(2, '0');
  return FsStrings.syncLastAt('${deux(d.hour)}:${deux(d.minute)}');
}

Timer? _moteur;
int _tic = 0;
int _echecs = 0;

/// Démarre (une seule fois par fenêtre) le moteur de synchronisation : toutes les 3 min, toutes les 30 s
/// après un échec (10 essais, puis toutes les 3 min), et peu après la connexion d'un compte.
void fsSyncDemarrer() {
  if (_moteur != null || bind.isDisableAccount() || bind.isDisableAb()) return;
  _moteur = Timer.periodic(const Duration(seconds: 30), (_) {
    _tic++;
    if (!gFFI.userModel.isLogin) return;
    final enErreur = fsSyncErreur.value.isNotEmpty || !fsSaasActif();
    if ((enErreur && _echecs < 10) || _tic % 6 == 0) fsSaasSynchroniser();
  });
  gFFI.userModel.userName.listen((nom) {
    if (nom.isEmpty) {
      fsSyncErreur.value = '';
      fsSyncEnAttente.value = 0;
      fsSyncReussiLe.value = null;
      _echecs = 0;
    } else {
      Future.delayed(const Duration(seconds: 2), fsSaasSynchroniser);
    }
  });
  Future.delayed(const Duration(seconds: 3), fsSaasSynchroniser);
}

void _echec(String message) {
  _echecs++;
  fsSyncErreur.value = message;
}

/// Reprise des entreprises et sessions locales dans le carnet du SaaS (voir l'en-tête). Sans effet hors connexion.
/// Carnet pas encore chargé ou dernier chargement en échec : nouvel essai de chargement d'abord.
Future<void> fsSaasSynchroniser() async {
  if (_synchroEnCours || !gFFI.userModel.isLogin) return;
  _synchroEnCours = true;
  fsSyncEnCours.value = true;
  try {
    final ab = gFFI.abModel;
    if (!fsSaasActif()) {
      final user = gFFI.userModel;
      if (user.networkError.value.isNotEmpty) {
        // Compte non revérifié (serveur injoignable au démarrage) : nouvel essai, le carnet suivra.
        _echec(user.networkError.value);
        user.refreshCurrentUser();
        return;
      }
      ab.clearPullErrors();
      await ab.pullAb(force: ForcePullAb.listAndCurrent, quiet: true);
      if (!fsSaasActif()) {
        _echec(ab.legacyMode.value ? 'Carnet FS indisponible sur ce serveur' : 'Carnet FS injoignable');
        return;
      }
    }
    final compte = gFFI.userModel.userName.value;
    final drapeau = '${_kAtelierPrefix}fs-saas-import:$compte';
    final premiere = bind.mainGetCommonSync(key: drapeau) != 'Y';
    final local = fsLocalCompanySnapshot();
    var entreprisesAjoutees = 0;
    if (premiere) {
      final aAjouter = <String>[];
      for (final c in local.companies) {
        if (fsSaasEtiquette(c) == null && !aAjouter.any((x) => _cle(x) == _cle(c))) aAjouter.add(c);
      }
      if (aAjouter.isNotEmpty && await ab.addTags(aAjouter)) entreprisesAjoutees = aAjouter.length;
    }
    final dansCarnet = ab.currentAbPeers.map((p) => p.id).toSet();
    final envoi = <Map<String, dynamic>>[];
    final recents = await _sessionsRecentes();
    for (final p in recents) {
      if (dansCarnet.contains(p.id) || _dejaProposes.contains(p.id)) continue;
      _dejaProposes.add(p.id);
      final ent = premiere ? local.map[p.id] : null;
      envoi.add(_pourCarnet(p.id, p: p, entreprise: ent == null ? null : fsSaasEtiquette(ent)));
    }
    if (premiere) {
      // Appareils rangés localement mais absents des sessions récentes.
      for (final e in local.map.entries) {
        if (dansCarnet.contains(e.key) || _dejaProposes.contains(e.key)) continue;
        _dejaProposes.add(e.key);
        envoi.add(_pourCarnet(e.key, entreprise: fsSaasEtiquette(e.value)));
      }
      // Appareils déjà dans le carnet mais sans entreprise : reprise du rangement local.
      for (final p in ab.currentAbPeers.toList()) {
        final ent = local.map[p.id];
        final tag = ent == null ? null : fsSaasEtiquette(ent);
        if (p.tags.isEmpty && tag != null) await ab.changeTagForPeers([p.id], [tag]);
      }
    }
    String? erreur;
    fsSyncEnAttente.value = envoi.length;
    if (envoi.isNotEmpty) erreur = await ab.addPeersTo(envoi, ab.currentName.value);
    if (premiere && erreur == null) {
      await bind.mainSetCommon(key: drapeau, value: 'Y');
      if (envoi.isNotEmpty || entreprisesAjoutees > 0) {
        BotToast.showText(
            contentColor: MyTheme.accent,
            text: '${envoi.length} appareil${envoi.length > 1 ? 's' : ''} et $entreprisesAjoutees entreprise${entreprisesAjoutees > 1 ? 's' : ''} rangés dans FS Solutions');
      }
    }
    if (erreur != null) {
      debugPrint('fsSaas : envoi au carnet incomplet : $erreur');
      // Ces appareils repartiront au prochain essai.
      for (final m in envoi) {
        _dejaProposes.remove(m['id']);
      }
      _echec(erreur);
    } else {
      fsSyncEnAttente.value = 0;
      fsSyncErreur.value = '';
      // Un ancien échec d'envoi du carnet (renommage, étiquette…) n'est plus d'actualité après un échange réussi.
      ab.current.pushError.value = '';
      fsSyncReussiLe.value = DateTime.now();
      _echecs = 0;
    }
    fsCompanyVersion.value++;
  } catch (e) {
    debugPrint('fsSaasSynchroniser : $e');
    _echec(e.toString());
  } finally {
    _synchroEnCours = false;
    fsSyncEnCours.value = false;
  }
}

/// Après une déconnexion : la prochaine connexion d'un compte refait la comparaison des sessions récentes.
void fsSaasOublierSession() {
  _dejaProposes.clear();
  fsSyncErreur.value = '';
  fsSyncEnAttente.value = 0;
  fsSyncReussiLe.value = null;
}

/// Fenêtre « Se connecter » : FS Connect seulement (le formulaire identifiant / mot de passe de RustDesk est masqué ;
/// le SaaS refuse de toute façon /api/login).
const bool kFsConnectOnly = true;

/// Message quand le serveur n'annonce aucune méthode (connexion FS Connect désactivée ou serveur injoignable).
const String kFsConnectUnavailable = 'Connexion FS Connect indisponible pour le moment. Réessayez plus tard.';
