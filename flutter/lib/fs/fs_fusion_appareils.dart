// FS Support : fusion validée des appareils d'un poste dans le compte FS Solutions (09/11/2026).
//
// Le même compte FS Connect peut se connecter sur plusieurs PC qui ont déjà chacun leurs appareils et leurs
// entreprises. À la première connexion du compte sur ce poste, rien ne part tout seul : le SaaS compare ce poste et le
// compte (`/api/ab/fusion/plan`) et l'écran « Fusionner vos appareils » montre les nouveaux appareils, ceux qui sont
// identiques, les conflits (même appareil, nom ou entreprise différents : choix par ligne, le compte est gardé par
// défaut) et les appareils retirés du compte (remis seulement si la case est cochée). Trois sorties :
//   - « Fusionner » : copie de ce poste gardée localement, puis envoi des choix avec l'empreinte du carnet ; si un autre
//     poste a modifié le compte entre-temps, le SaaS refuse et l'écran se met à jour (rien n'est perdu). Le SaaS garde
//     une copie du carnet d'avant : « Annuler la fusion » le remet tel quel ;
//   - « Ne rien envoyer » : le poste reste sur le compte, sans rien y verser, et n'y versera rien tout seul ensuite ;
//   - « Annuler » : déconnexion, ce poste reste exactement comme avant.
// Aucun mot de passe n'est envoyé. Plan, choix et textes : `fusion.dart` de fs_ui (testé).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/widgets/fs_company_groups.dart';
import '../models/ab_model.dart';
import '../models/peer_model.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;

/// Réglages de l'Atelier (`ATELIER_OPTION_PREFIX` de `src/fs_support.rs`), par compte.
String fsFusionCleDecision(String compte) => 'fs-atelier:fs-saas-import:$compte';
String fsFusionCleEcartes(String compte) => 'fs-atelier:fs-saas-ecartes:$compte';
String _cleSauvegarde(String compte) => 'fs-atelier:fs-saas-sauvegarde:$compte';

/// Décision prise sur ce poste pour ce compte : 'Y' fusionné, 'N' rien envoyé, '' pas encore décidé.
String fsFusionDecision(String compte) => bind.mainGetCommonSync(key: fsFusionCleDecision(compte));

/// Appareils de ce poste à ne jamais verser tout seuls dans le compte (décochés ou retirés non remis lors de la fusion).
Set<String> fsFusionEcartes(String compte) {
  try {
    final brut = bind.mainGetCommonSync(key: fsFusionCleEcartes(compte));
    if (brut.isEmpty) return {};
    return (jsonDecode(brut) as List).map((e) => '$e').toSet();
  } catch (_) {
    return {};
  }
}

class _RefusFusion implements Exception {
  _RefusFusion(this.message, {this.code = ''});
  final String message;
  final String code;
  @override
  String toString() => message;
}

String? _guidPersonnel() {
  final c = gFFI.abModel.current;
  return c is Ab && c.personal ? c.profile.guid : null;
}

Future<Map<String, dynamic>> _appel(String action, Map<String, dynamic> corps) async {
  final guid = _guidPersonnel();
  if (guid == null) throw _RefusFusion('Carnet du compte pas encore chargé.');
  final api = await bind.mainGetApiServer();
  final resp = await http.post(Uri.parse('$api/api/ab/fusion/$action/$guid'),
      headers: {...getHttpHeaders(), 'Content-Type': 'application/json'}, body: jsonEncode(corps));
  Map<String, dynamic> d = {};
  try {
    final lu = jsonDecode(decode_http_response(resp));
    if (lu is Map<String, dynamic>) d = lu;
  } catch (_) {}
  if (resp.statusCode == 401) throw _RefusFusion('Session FS Support expirée : reconnectez-vous avec FS Connect.');
  if (resp.statusCode != 200) {
    throw _RefusFusion((d['error'] ?? 'Comparaison impossible (HTTP ${resp.statusCode}).').toString(), code: '${d['code'] ?? ''}');
  }
  return d;
}

/// Appareils et entreprises de ce poste : sessions récentes + rangement local par entreprise.
Future<Map<String, dynamic>> _demandeDuPoste(List<Peer> recents) async {
  final local = fsLocalCompanySnapshot();
  final appareils = <FsFusionAppareil>[
    for (final p in recents)
      FsFusionAppareil(
          id: p.id, alias: p.alias, username: p.username, hostname: p.hostname, platform: p.platform, entreprise: local.map[p.id] ?? ''),
    for (final e in local.map.entries) FsFusionAppareil(id: e.key, entreprise: e.value),
  ];
  return fsFusionDemande(appareils, local.companies);
}

/// Ce poste a-t-il quelque chose à proposer au compte ?
bool fsFusionPosteAVerser(List<Peer> recents) {
  final local = fsLocalCompanySnapshot();
  return recents.isNotEmpty || local.map.isNotEmpty || local.companies.isNotEmpty;
}

bool _ouvert = false;

/// Compte dont l'écran a été fermé sans décision : pas reproposé avant la prochaine connexion (ou le prochain lancement).
String? _reporte;

/// Après une déconnexion : la prochaine connexion repose la question si rien n'a été décidé.
void fsFusionOublier() => _reporte = null;

/// Première connexion du compte sur ce poste : compare et, s'il y a quelque chose à fusionner, ouvre l'écran.
/// Ne verse rien sans validation. Retourne vrai si la décision est prise (rien à fusionner = décidé).
Future<bool> fsFusionProposer(List<Peer> recents, {required Future<void> Function() recharger}) async {
  final compte = gFFI.userModel.userName.value;
  if (compte.isEmpty || _ouvert || _reporte == compte) return false;
  if (!fsFusionPosteAVerser(recents)) {
    await bind.mainSetCommon(key: fsFusionCleDecision(compte), value: 'Y');
    return true;
  }
  final demande = await _demandeDuPoste(recents);
  final plan = FsFusionPlan.fromJson(await _appel('plan', demande));
  if (!plan.utile) {
    await bind.mainSetCommon(key: fsFusionCleDecision(compte), value: 'Y');
    return true;
  }
  _ouvert = true;
  _ecran(compte, plan, demande, recharger);
  return false;
}

void _ecran(String compte, FsFusionPlan planDepart, Map<String, dynamic> demande, Future<void> Function() recharger) {
  var plan = planDepart;
  var choix = FsFusionChoix(plan);
  var envoi = false;
  String? message;
  Map<String, dynamic>? bilan;
  var annulee = false;

  gFFI.dialogManager.show((setState, close, context) {
    var decide = false;
    void fermer() {
      _ouvert = false;
      if (!decide && bilan == null && !annulee) _reporte = compte;
      close();
    }

    Future<void> fusionner() async {
      if (envoi) return;
      setState(() {
        envoi = true;
        message = null;
      });
      try {
        // Copie locale de ce que ce poste avait, avant toute écriture dans le compte.
        final local = fsLocalCompanySnapshot();
        await bind.mainSetCommon(
            key: _cleSauvegarde(compte),
            value: jsonEncode({
              'le': DateTime.now().toIso8601String(),
              'entreprises': local.companies,
              'rangement': local.map,
              'demande': demande,
            }));
        final r = await _appel('appliquer', choix.corps(plan, demande));
        final ecartes = {...fsFusionEcartes(compte), ...choix.laissesDeCote(plan)};
        await bind.mainSetCommon(key: fsFusionCleEcartes(compte), value: jsonEncode(ecartes.toList()));
        await bind.mainSetCommon(key: fsFusionCleDecision(compte), value: 'Y');
        if (r['sauvegarde'] != null) {
          final s = jsonDecode(bind.mainGetCommonSync(key: _cleSauvegarde(compte))) as Map<String, dynamic>;
          s['sauvegardeCompte'] = r['sauvegarde'];
          await bind.mainSetCommon(key: _cleSauvegarde(compte), value: jsonEncode(s));
        }
        await recharger();
        setState(() => bilan = r);
      } on _RefusFusion catch (e) {
        if (e.code == 'carnet_modifie') {
          // Un autre poste a modifié le compte : nouvelle comparaison, l'utilisateur revalide.
          try {
            plan = FsFusionPlan.fromJson(await _appel('plan', demande));
            choix = FsFusionChoix(plan);
            setState(() => message = 'Vos appareils ont changé sur un autre PC entre-temps. La comparaison est à jour : vérifiez puis validez.');
          } catch (e2) {
            setState(() => message = e2.toString());
          }
        } else {
          setState(() => message = e.toString());
        }
      } catch (e) {
        setState(() => message = 'Fusion impossible : vérifiez la connexion Internet. Rien n\'a été modifié.');
      } finally {
        setState(() => envoi = false);
      }
    }

    Future<void> annulerFusion() async {
      final id = bilan?['sauvegarde'];
      if (id == null || envoi) return;
      setState(() => envoi = true);
      try {
        await _appel('restaurer', {'sauvegarde': id});
        await bind.mainSetCommon(key: fsFusionCleDecision(compte), value: 'N');
        await recharger();
        setState(() => annulee = true);
      } catch (e) {
        setState(() => message = 'Annulation impossible : $e');
      } finally {
        setState(() => envoi = false);
      }
    }

    Future<void> rienEnvoyer() async {
      await bind.mainSetCommon(key: fsFusionCleDecision(compte), value: 'N');
      decide = true;
      fermer();
    }

    Future<void> deconnecter() async {
      fermer();
      await gFFI.userModel.logOut();
    }

    final theme = Theme.of(context);
    Widget titre(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)));
    Widget aide(String t) => Text(t, style: TextStyle(fontSize: 12, color: theme.hintColor));

    final Widget contenu;
    if (annulee) {
      contenu = const Text('Fusion annulée : votre compte est revenu exactement à son état d\'avant. Les appareils de ce PC n\'ont pas bougé.');
    } else if (bilan != null) {
      contenu = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fsFusionBilan(bilan!)),
        const SizedBox(height: 8),
        aide('Une copie de votre compte d\'avant la fusion est gardée : « Annuler la fusion » le remet tel quel.'),
      ]);
    } else {
      contenu = SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ce PC a déjà des appareils, et votre compte en a ${plan.appareilsCompte}. Choisissez ce qui rejoint votre compte : '
              'rien n\'est envoyé avant que vous validiez.'),
          if (plan.identiques > 0) aide('${plan.identiques} appareil${plan.identiques > 1 ? 's sont' : ' est'} déjà identique${plan.identiques > 1 ? 's' : ''} : rien à faire.').marginOnly(top: 6),
          if (plan.nouveaux.isNotEmpty) ...[
            titre('Nouveaux appareils (${plan.nouveaux.length})'),
            for (final n in plan.nouveaux)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: choix.ajouter.contains(n.id),
                onChanged: envoi ? null : (v) => setState(() => v == true ? choix.ajouter.add(n.id) : choix.ajouter.remove(n.id)),
                title: Text(n.titre),
                subtitle: Text(n.entreprise.isEmpty ? 'Non classé' : n.entreprise),
              ),
          ],
          if (plan.conflits.isNotEmpty) ...[
            titre('Différents sur ce PC et dans le compte (${plan.conflits.length})'),
            aide('Par défaut, la version du compte est gardée.'),
            for (final c in plan.conflits)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    groupValue: choix.garderPoste.contains(c.id),
                    onChanged: envoi ? null : (_) => setState(() => choix.garderPoste.remove(c.id)),
                    title: Text('Garder le compte : ${c.cote(poste: false)}'),
                  ),
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    groupValue: choix.garderPoste.contains(c.id),
                    onChanged: envoi ? null : (_) => setState(() => choix.garderPoste.add(c.id)),
                    title: Text('Garder ce PC : ${c.cote(poste: true)}'),
                  ),
                ]),
              ),
          ],
          if (plan.completes.isNotEmpty) ...[
            titre('Informations complétées (${plan.completes.length})'),
            aide('Ces appareils sont déjà dans le compte : seuls leurs champs vides seront remplis depuis ce PC.'),
          ],
          if (plan.retires.isNotEmpty) ...[
            titre('Retirés de votre compte (${plan.retires.length})'),
            aide('Vous les aviez retirés de votre compte. Cochez seulement ceux à remettre.'),
            for (final r in plan.retires)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: choix.ressusciter.contains(r.id),
                onChanged: envoi ? null : (v) => setState(() => v == true ? choix.ressusciter.add(r.id) : choix.ressusciter.remove(r.id)),
                title: Text(r.titre),
              ),
          ],
          if (plan.entreprisesNouvelles.isNotEmpty || plan.entreprisesFusionnees.isNotEmpty) ...[
            titre('Entreprises'),
            if (plan.entreprisesNouvelles.isNotEmpty) aide('Ajoutées : ${plan.entreprisesNouvelles.join(', ')}.'),
            for (final f in plan.entreprisesFusionnees) aide('« ${f.$1} » rejoint « ${f.$2} » (même entreprise).'),
          ],
        ]),
      );
    }

    final List<Widget> actions;
    if (annulee) {
      actions = [dialogButton('Close', icon: const Icon(Icons.done_rounded), onPressed: fermer)];
    } else if (bilan != null) {
      actions = [
        if (bilan!['sauvegarde'] != null)
          dialogButton('Annuler la fusion', icon: const Icon(Icons.undo_rounded), onPressed: envoi ? null : annulerFusion, isOutline: true),
        dialogButton('OK', icon: const Icon(Icons.done_rounded), onPressed: envoi ? null : fermer),
      ];
    } else {
      actions = [
        dialogButton('Annuler', icon: const Icon(Icons.logout_rounded), onPressed: envoi ? null : deconnecter, isOutline: true),
        dialogButton('Ne rien envoyer', icon: const Icon(Icons.block_rounded), onPressed: envoi ? null : rienEnvoyer, isOutline: true),
        dialogButton('Fusionner', icon: const Icon(Icons.merge_rounded), onPressed: envoi ? null : fusionner),
      ];
    }

    return CustomAlertDialog(
      title: Row(children: [
        Icon(Icons.merge_rounded, color: MyTheme.accent),
        const SizedBox(width: 10),
        const Text('Fusionner vos appareils'),
      ]),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Flexible(child: contenu),
            if (message != null) Text(message!, style: const TextStyle(color: Colors.red)).marginOnly(top: 8),
            if (envoi) const LinearProgressIndicator().marginOnly(top: 8),
          ]),
        ),
      ),
      actions: actions,
      // Fermer la fenêtre sans choisir = ne rien décider : rien n'est envoyé, la question reviendra.
      onCancel: envoi ? null : fermer,
    );
  });
}
