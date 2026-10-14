// FS Support : « Demander une intervention sur site » (14/10/2026, validé par Jason).
//
// Le client, depuis FS Support et SANS compte, envoie une demande courte (motif, créneaux souhaités, adresse et
// téléphone facultatifs) à FS Solutions. L'ID FS Support du poste est joint automatiquement. Le SaaS en fait une
// demande « Assistance sur site » (`onsite_request`), réservée aux superadmins : centre de notifications staff, Ops,
// et page Tickets FS de FS Support.
// Appel : POST <api-server>/api/assistance-sur-site (→ /fss/api/assistance-sur-site). Garde-fous côté SaaS : taille
// bornée, 5 demandes / heure / adresse, 3 / 24 h / poste.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;

/// Carte du rail : « Besoin d'un technicien sur place ? » + bouton. Masquée sans serveur d'API.
class FsOnsiteCard extends StatelessWidget {
  const FsOnsiteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return FutureBuilder<String>(
      future: bind.mainGetApiServer(),
      builder: (context, snap) {
        if ((snap.data ?? '').trim().isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: t.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FsText(FsStrings.onsiteTitle, style: FsType.sans(13, FontWeight.w700, color: t.ink)),
            const SizedBox(height: 4),
            FsText(FsStrings.onsiteText, style: FsType.sans(12, FontWeight.w400, color: t.muted)),
            const SizedBox(height: 10),
            FsButton(
              label: FsStrings.onsiteButton,
              kind: FsButtonKind.ghost,
              height: 36,
              fontSize: 12.5,
              iconSize: 16,
              hPadding: 10,
              expand: true,
              leading: Icons.home_repair_service_outlined,
              onPressed: fsOnsiteRequestDialog,
            ),
          ]),
        );
      },
    );
  }
}

/// Formulaire de demande d'intervention sur site.
void fsOnsiteRequestDialog() {
  final motif = TextEditingController();
  final creneaux = TextEditingController();
  final adresse = TextEditingController();
  final telephone = TextEditingController();
  final nom = TextEditingController();
  final email = TextEditingController();
  var envoi = false;
  String? erreur;
  String? reference;

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> envoyer() async {
      if (envoi) return;
      if (reference != null) {
        close();
        return;
      }
      if (motif.text.trim().length < 10) {
        setState(() => erreur = FsStrings.onsiteReasonMissing);
        return;
      }
      setState(() {
        envoi = true;
        erreur = null;
      });
      try {
        final api = await bind.mainGetApiServer();
        final corps = jsonEncode({
          'id': await bind.mainGetMyId(),
          'uuid': await bind.mainGetUuid(),
          'version': await bind.mainGetVersion(),
          'motif': motif.text.trim(),
          'creneaux': creneaux.text.trim(),
          'adresse': adresse.text.trim(),
          'telephone': telephone.text.trim(),
          'nom': nom.text.trim(),
          'email': email.text.trim(),
        });
        final resp = await http.post(Uri.parse('$api/api/assistance-sur-site'), headers: {'Content-Type': 'application/json'}, body: corps);
        Map<String, dynamic> d = {};
        try {
          final lu = jsonDecode(decode_http_response(resp));
          if (lu is Map<String, dynamic>) d = lu;
        } catch (_) {}
        if (resp.statusCode == 201 && d['ok'] == true) {
          setState(() => reference = '${d['reference'] ?? ''} — ${d['message'] ?? ''}');
        } else {
          setState(() => erreur = (d['error'] ?? 'Envoi impossible (HTTP ${resp.statusCode}) : réessayez ou appelez FS Solutions.').toString());
        }
      } catch (e) {
        setState(() => erreur = 'Envoi impossible : vérifiez la connexion Internet, ou appelez FS Solutions.');
      } finally {
        setState(() => envoi = false);
      }
    }

    InputDecoration champ(String libelle, {String? aide}) => InputDecoration(labelText: libelle, hintText: aide, counterText: '');

    final contenu = reference != null
        ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(FsStrings.onsiteSent, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(reference!),
          ])
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: motif,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: champ(FsStrings.onsiteReason, aide: FsStrings.onsiteReasonHint),
            ),
            TextField(controller: creneaux, maxLength: 500, decoration: champ(FsStrings.onsiteSlots, aide: FsStrings.onsiteSlotsHint)),
            TextField(controller: adresse, maxLength: 300, decoration: champ(FsStrings.onsiteAddress)),
            Row(children: [
              Expanded(child: TextField(controller: telephone, maxLength: 30, keyboardType: TextInputType.phone, decoration: champ(FsStrings.onsitePhone))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: nom, maxLength: 120, decoration: champ(FsStrings.onsiteName))),
            ]),
            TextField(controller: email, maxLength: 254, keyboardType: TextInputType.emailAddress, decoration: champ(FsStrings.onsiteEmail)),
            const SizedBox(height: 8),
            Text(FsStrings.onsiteNote, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            if (erreur != null) ...[
              const SizedBox(height: 8),
              Text(erreur!, style: const TextStyle(color: Colors.red)),
            ],
            if (envoi) const LinearProgressIndicator().marginOnly(top: 8),
          ]);

    return CustomAlertDialog(
      title: Row(children: [
        Icon(Icons.home_repair_service_outlined, color: MyTheme.accent),
        const SizedBox(width: 10),
        const Text(FsStrings.onsiteDialog),
      ]),
      content: SizedBox(width: 460, child: contenu),
      actions: reference != null
          ? [dialogButton('Close', icon: const Icon(Icons.done_rounded), onPressed: close)]
          : [
              dialogButton('Cancel', icon: const Icon(Icons.close_rounded), onPressed: close, isOutline: true),
              dialogButton(FsStrings.onsiteSend, icon: const Icon(Icons.send_rounded), onPressed: envoi ? null : envoyer),
            ],
      onSubmit: reference != null ? close : null,
      onCancel: close,
    );
  });
}
