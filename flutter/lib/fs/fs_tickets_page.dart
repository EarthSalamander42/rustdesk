// FS Support : page « Tickets FS » (14/10/2026), réservée aux superadmins FS Solutions.
//
// Les demandes reçues par FS Solutions (AppTickets du SaaS), au premier rang les demandes d'intervention sur site
// envoyées depuis FS Support : liste filtrable, détail, changement de statut, fil de discussion, et « Prendre la main »
// quand la demande porte l'ID FS Support du poste.
//
// L'onglet n'apparaît que si `currentUser` dit superadmin (`is_admin`), mais c'est le SaaS qui décide : chaque route
// /api/tickets* (→ /fss/api/tickets* sur le SaaS) relit le rôle du compte et répond 403 sinon.
// Appels : jeton d'appareil FS Support (`getHttpHeaders`), module HTTP de RustDesk (`utils/http_service.dart`).

import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;

class FsTicketsPage extends StatefulWidget {
  const FsTicketsPage({super.key});

  @override
  State<FsTicketsPage> createState() => _FsTicketsPageState();
}

class _FsTicketsPageState extends State<FsTicketsPage> {
  String _categorie = 'onsite_request';
  bool _archivees = false;
  bool _chargement = false;
  String _erreur = '';
  List<Map<String, dynamic>> _tickets = [];
  int? _choisi;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _messages = [];
  bool _envoi = false;
  final _reponse = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _reponse.dispose();
    super.dispose();
  }

  Future<Uri> _uri(String chemin, [Map<String, String>? params]) async {
    final base = Uri.parse('${await bind.mainGetApiServer()}/api/$chemin');
    return params == null || params.isEmpty ? base : base.replace(queryParameters: params);
  }

  Map<String, String> _entetes() => {...getHttpHeaders(), 'Content-Type': 'application/json'};

  /// Corps JSON d'une réponse, ou exception lisible (message du SaaS si présent).
  Map<String, dynamic> _lire(dynamic resp) {
    final texte = decode_http_response(resp);
    Map<String, dynamic>? corps;
    try {
      final d = jsonDecode(texte);
      if (d is Map<String, dynamic>) corps = d;
    } catch (_) {}
    final code = resp.statusCode as int;
    if (code == 403) throw FsStrings.ticketsDenied;
    if (code == 401) throw 'Session FS Support expirée : reconnectez-vous avec FS Connect.';
    if (corps == null) throw 'Réponse illisible du serveur (HTTP $code).';
    if (code != 200 && code != 201) throw (corps['error'] ?? 'HTTP $code').toString();
    return corps;
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    try {
      final params = <String, String>{
        if (_categorie.isNotEmpty) 'category': _categorie,
        if (_archivees) 'archived': '1',
      };
      final resp = await http.get(await _uri('tickets', params), headers: _entetes());
      final corps = _lire(resp);
      final liste = (corps['tickets'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      if (!mounted) return;
      setState(() {
        _tickets = liste;
        if (_choisi != null && !liste.any((t) => t['id'] == _choisi)) {
          _choisi = null;
          _detail = null;
          _messages = [];
        }
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _ouvrir(int id) async {
    setState(() {
      _choisi = id;
      _detail = null;
      _messages = [];
    });
    try {
      final resp = await http.get(await _uri('tickets/$id'), headers: _entetes());
      final corps = _lire(resp);
      if (!mounted || _choisi != id) return;
      setState(() {
        _detail = corps['ticket'] as Map<String, dynamic>?;
        _messages = (corps['messages'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      _toast(e.toString(), erreur: true);
    }
  }

  Future<void> _changerStatut(int id, String statut) async {
    try {
      final resp = await http.put(await _uri('tickets/$id'), headers: _entetes(), body: jsonEncode({'status': statut}));
      final corps = _lire(resp);
      final ticket = corps['ticket'] as Map<String, dynamic>?;
      if (!mounted || ticket == null) return;
      setState(() {
        _detail = {...?_detail, ...ticket};
        _tickets = _tickets.map((t) => t['id'] == id ? {...t, 'statut': ticket['statut']} : t).toList();
      });
      _toast('${FsStrings.status} : ${FsStrings.ticketStatus[statut] ?? statut}');
    } catch (e) {
      _toast(e.toString(), erreur: true);
    }
  }

  Future<void> _repondre(int id) async {
    final texte = _reponse.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      final resp = await http.post(await _uri('tickets/$id/messages'), headers: _entetes(), body: jsonEncode({'body': texte}));
      final corps = _lire(resp);
      if (!mounted) return;
      _reponse.clear();
      setState(() => _messages = (corps['messages'] as List? ?? []).whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      _toast(e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _toast(String texte, {bool erreur = false}) {
    if (!mounted) return;
    BotToast.showText(text: texte, contentColor: erreur ? Colors.red : MyTheme.accent);
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    String n(int x) => x.toString().padLeft(2, '0');
    return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
  }

  // ---- rendu ---------------------------------------------------------------

  Widget _filtres() => Row(children: [
        FsChip(label: FsStrings.ticketsOnsite, icon: Icons.home_repair_service_rounded, on: _categorie == 'onsite_request', onPressed: () {
          setState(() => _categorie = 'onsite_request');
          _charger();
        }),
        const SizedBox(width: 6),
        FsChip(label: FsStrings.ticketsAll, on: _categorie.isEmpty, onPressed: () {
          setState(() => _categorie = '');
          _charger();
        }),
        const SizedBox(width: 12),
        FsChip(label: _archivees ? FsStrings.ticketsArchived : FsStrings.ticketsOpen, icon: Icons.archive_outlined, on: _archivees, onPressed: () {
          setState(() => _archivees = !_archivees);
          _charger();
        }),
        const SizedBox(width: 6),
        FsIconButton(icon: Icons.refresh_rounded, tooltip: FsStrings.refresh, spinOnPress: true, onPressed: _charger),
      ]);

  Widget _pastille(BuildContext context, String statut) {
    final t = FsTokens.of(context);
    final couleur = switch (statut) {
      'new' => t.acc,
      'waiting_customer' => Colors.orange.shade700,
      'planned' => t.on,
      'done' => t.muted,
      'cancelled' => t.danger,
      _ => t.ink,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: couleur)),
      child: FsText(FsStrings.ticketStatus[statut] ?? statut, style: FsType.sans(11.5, FontWeight.w700, color: couleur)),
    );
  }

  Widget _liste(BuildContext context) {
    final t = FsTokens.of(context);
    if (_chargement && _tickets.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_erreur.isNotEmpty) {
      return Align(alignment: Alignment.topLeft, child: FsEmptyState(title: 'Demandes indisponibles', text: _erreur));
    }
    if (_tickets.isEmpty) return Align(alignment: Alignment.topLeft, child: FsEmptyState(title: FsStrings.ticketsEmpty, text: FsStrings.ticketsSub));
    return ListView.separated(
      itemCount: _tickets.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: t.line),
      itemBuilder: (context, i) {
        final tk = _tickets[i];
        final id = tk['id'] as int?;
        final choisi = id != null && id == _choisi;
        final sousTitre = [
          FsStrings.ticketCategory[tk['categorie']] ?? (tk['categorie'] ?? '').toString(),
          (tk['demandeur'] ?? '').toString(),
          (tk['entreprise'] ?? '').toString(),
          _date(tk['cree_le']),
        ].where((x) => x.isNotEmpty).join(' · ');
        return InkWell(
          onTap: id == null ? null : () => _ouvrir(id),
          child: Container(
            color: choisi ? t.sel : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FsText('#$id  ${tk['titre'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(14, FontWeight.w700, color: t.ink)),
                  const SizedBox(height: 2),
                  FsText(sousTitre, maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
                ]),
              ),
              if ((tk['fs_support_id'] ?? '').toString().isNotEmpty) ...[
                Icon(Icons.desktop_windows_outlined, size: 16, color: t.muted),
                const SizedBox(width: 8),
              ],
              _pastille(context, (tk['statut'] ?? 'new').toString()),
            ]),
          ),
        );
      },
    );
  }

  Widget _champ(BuildContext context, String libelle, String valeur, {bool mono = false}) {
    if (valeur.trim().isEmpty) return const SizedBox.shrink();
    final t = FsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FsEyebrow(libelle, color: t.muted),
        const SizedBox(height: 3),
        SelectableText(valeur, style: mono ? FsType.mono(13, FontWeight.w500, color: t.ink) : FsType.sans(13.5, FontWeight.w400, color: t.ink)),
      ]),
    );
  }

  Widget _volet(BuildContext context) {
    final t = FsTokens.of(context);
    final d = _detail;
    if (_choisi == null) return Center(child: FsText(FsStrings.ticketsPick, style: FsType.sans(13, FontWeight.w400, color: t.muted)));
    if (d == null) return const Center(child: CircularProgressIndicator());
    final id = d['id'] as int;
    final fsId = (d['fs_support_id'] ?? '').toString();
    final statut = (d['statut'] ?? 'new').toString();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 8, 20), children: [
      FsText((d['titre'] ?? '').toString(), style: FsType.sans(18, FontWeight.w800, color: t.ink)),
      const SizedBox(height: 6),
      FsText('#$id · ${FsStrings.ticketCategory[d['categorie']] ?? d['categorie'] ?? ''} · ${_date(d['cree_le'])}',
          style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
      const SizedBox(height: 14),
      Row(children: [
        FsEyebrow(FsStrings.status, color: t.muted),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: FsStrings.status,
          onSelected: (v) => _changerStatut(id, v),
          itemBuilder: (_) => FsStrings.ticketStatus.entries
              .map((e) => PopupMenuItem<String>(value: e.key, child: Text(e.value + (e.key == statut ? '  ✓' : ''))))
              .toList(),
          child: Row(mainAxisSize: MainAxisSize.min, children: [_pastille(context, statut), Icon(Icons.arrow_drop_down_rounded, color: t.muted)]),
        ),
        const Spacer(),
        if (fsId.isNotEmpty)
          FsButton(
            label: FsStrings.takeControl,
            leading: Icons.screen_share_outlined,
            height: 38,
            fontSize: 13.5,
            iconSize: 17,
            hPadding: 14,
            onPressed: () => connect(context, fsId.replaceAll(' ', '')),
          ),
      ]),
      const SizedBox(height: 16),
      _champ(context, FsStrings.fsSupportId, fsId.isEmpty ? '' : '${fsFormatId(fsId)}${(d['poste'] ?? '').toString().isNotEmpty ? ' · ${d['poste']}' : ''}', mono: true),
      _champ(context, FsStrings.requester, [d['demandeur'], d['entreprise']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ')),
      _champ(context, FsStrings.phone, (d['telephone'] ?? '').toString(), mono: true),
      _champ(context, FsStrings.email, (d['email'] ?? '').toString()),
      _champ(context, FsStrings.slots, (d['creneaux'] ?? '').toString()),
      _champ(context, FsStrings.address, (d['adresse'] ?? '').toString()),
      _champ(context, 'Demande', (d['description'] ?? '').toString()),
      Divider(color: t.line, height: 24),
      for (final m in _messages)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: m['auteur'] == 'staff' ? t.hov : null, border: Border.all(color: t.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FsText('${m['auteur'] == 'staff' ? 'FS Solutions' : 'Demandeur'} · ${_date(m['le'])}', style: FsType.sans(11.5, FontWeight.w700, color: t.muted)),
            const SizedBox(height: 4),
            SelectableText((m['texte'] ?? '').toString(), style: FsType.sans(13.5, FontWeight.w400, color: t.ink)),
          ]),
        ),
      TextField(
        controller: _reponse,
        minLines: 2,
        maxLines: 6,
        maxLength: 4000,
        decoration: const InputDecoration(hintText: FsStrings.replyHint, border: OutlineInputBorder()),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FsButton(label: FsStrings.reply, trailing: Icons.send_rounded, height: 38, fontSize: 13.5, iconSize: 17, onPressed: _envoi ? null : () => _repondre(id)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FsPanelHead(title: FsStrings.ticketsFs, sub: FsStrings.ticketsSub, tools: [_filtres()]),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 5, child: _liste(context)),
          VerticalDivider(width: 1, color: t.line),
          Expanded(flex: 4, child: _volet(context)),
        ]),
      ),
    ]);
  }
}
