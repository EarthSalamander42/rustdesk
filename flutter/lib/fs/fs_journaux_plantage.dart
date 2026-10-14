// FS Support : « Journaux » de la page Tickets FS (14/10/2026), réservés aux superadmins FS Solutions.
//
// Journaux de plantage envoyés par les postes FS Support (Android : FsCrashJournal.kt), reçus par le SaaS
// (/fss/api/journal-plantage) : liste (poste, raison, appareil, version) et rapport complet (trace, fin de logcat,
// fin du journal Rust), copiable. Comme les Tickets FS, c'est le SaaS qui décide : chaque route
// /api/journaux-plantage* (→ /fss/api/journaux-plantage* sur le SaaS) relit le rôle du compte et répond 403 sinon.

import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;

class FsJournauxPlantage extends StatefulWidget {
  const FsJournauxPlantage({super.key, required this.uri, required this.entetes, required this.lire});

  /// Adresse d'une route de l'api-server (`/api/<chemin>`), comme la page Tickets FS.
  final Future<Uri> Function(String chemin, [Map<String, String>? params]) uri;
  final Map<String, String> Function() entetes;

  /// Corps JSON d'une réponse, ou exception lisible.
  final Map<String, dynamic> Function(dynamic resp) lire;

  @override
  State<FsJournauxPlantage> createState() => _FsJournauxPlantageState();
}

class _FsJournauxPlantageState extends State<FsJournauxPlantage> {
  bool _chargement = false;
  String _erreur = '';
  List<Map<String, dynamic>> _journaux = [];
  int? _choisi;
  Map<String, dynamic>? _detail;
  final _filtreId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _filtreId.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    try {
      final id = _filtreId.text.replaceAll(' ', '').trim();
      final resp = await http.get(await widget.uri('journaux-plantage', {if (id.isNotEmpty) 'fs_support_id': id}), headers: widget.entetes());
      final corps = widget.lire(resp);
      final liste = (corps['journaux'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      if (!mounted) return;
      setState(() {
        _journaux = liste;
        if (_choisi != null && !liste.any((j) => j['id'] == _choisi)) {
          _choisi = null;
          _detail = null;
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
    });
    try {
      final resp = await http.get(await widget.uri('journaux-plantage/$id'), headers: widget.entetes());
      final corps = widget.lire(resp);
      if (!mounted || _choisi != id) return;
      setState(() {
        _detail = corps['journal'] as Map<String, dynamic>?;
        _journaux = _journaux.map((j) => j['id'] == id ? {...j, 'lu': true} : j).toList();
      });
    } catch (e) {
      BotToast.showText(text: e.toString(), contentColor: Colors.red);
    }
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    String n(int x) => x.toString().padLeft(2, '0');
    return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
  }

  Widget _outils(BuildContext context) => Row(children: [
        SizedBox(
          width: 170,
          height: 34,
          child: TextField(
            controller: _filtreId,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'ID FS Support',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: (_) => _charger(),
          ),
        ),
        const SizedBox(width: 6),
        FsIconButton(icon: Icons.refresh_rounded, tooltip: FsStrings.refresh, spinOnPress: true, onPressed: _charger),
      ]);

  Widget _liste(BuildContext context) {
    final t = FsTokens.of(context);
    if (_chargement && _journaux.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_erreur.isNotEmpty) {
      return Align(alignment: Alignment.topLeft, child: FsEmptyState(title: 'Journaux indisponibles', text: _erreur));
    }
    if (_journaux.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: FsEmptyState(title: 'Aucun journal', text: 'Les plantages des postes FS Support et les envois manuels arrivent ici.'),
      );
    }
    return ListView.separated(
      itemCount: _journaux.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: t.line),
      itemBuilder: (context, i) {
        final j = _journaux[i];
        final id = j['id'] as int?;
        final choisi = id != null && id == _choisi;
        final fsId = (j['fs_support_id'] ?? '').toString();
        final poste = (j['poste'] ?? '').toString();
        final titre = [poste.isNotEmpty ? poste : (fsId.isNotEmpty ? fsFormatId(fsId) : 'Poste inconnu'), (j['raison_libelle'] ?? j['raison'] ?? '').toString()].join(' · ');
        final sousTitre = [
          (j['modele'] ?? '').toString(),
          (j['systeme'] ?? '').toString(),
          (j['version'] ?? '').toString().isEmpty ? '' : 'FS Support ${j['version']}',
          j['ecran_client'] == true ? 'Écran client' : '',
          _date(j['survenu_le'] ?? j['recu_le']),
        ].where((x) => x.isNotEmpty).join(' · ');
        final manuel = j['raison'] == 'manuel';
        return InkWell(
          onTap: id == null ? null : () => _ouvrir(id),
          child: Container(
            color: choisi ? t.sel : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              Icon(manuel ? Icons.description_outlined : Icons.report_problem_outlined, size: 18, color: manuel ? t.muted : t.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FsText('#$id  $titre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FsType.sans(14, j['lu'] == true ? FontWeight.w500 : FontWeight.w800, color: t.ink)),
                  const SizedBox(height: 2),
                  FsText(sousTitre, maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _bloc(BuildContext context, String libelle, String texte) {
    if (texte.trim().isEmpty) return const SizedBox.shrink();
    final t = FsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          FsEyebrow(libelle, color: t.muted),
          const Spacer(),
          FsIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copier',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: texte));
              BotToast.showText(text: '$libelle copié', contentColor: MyTheme.accent);
            },
          ),
        ]),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 360),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: t.hov, border: Border.all(color: t.line)),
          child: SingleChildScrollView(
            child: SelectableText(texte, style: FsType.mono(12, FontWeight.w400, color: t.ink)),
          ),
        ),
      ]),
    );
  }

  Widget _volet(BuildContext context) {
    final t = FsTokens.of(context);
    final d = _detail;
    if (_choisi == null) return Center(child: FsText('Choisissez un journal', style: FsType.sans(13, FontWeight.w400, color: t.muted)));
    if (d == null) return const Center(child: CircularProgressIndicator());
    final fsId = (d['fs_support_id'] ?? '').toString();
    final details = d['details'] is Map ? (d['details'] as Map) : const {};
    final infos = [
      (d['modele'] ?? '').toString(),
      (d['systeme'] ?? '').toString(),
      (d['type_rom'] ?? '').toString().isEmpty ? '' : 'ROM ${d['type_rom']}',
      (d['version'] ?? '').toString().isEmpty ? '' : 'FS Support ${d['version']}',
      d['ecran_client'] == true ? 'mode Écran client' : '',
    ].where((x) => x.isNotEmpty).join(' · ');
    final memoire = [
      if (details['pss_ko'] != null) 'PSS ${((details['pss_ko'] as num) / 1024).round()} Mo',
      if (details['rss_ko'] != null) 'RSS ${((details['rss_ko'] as num) / 1024).round()} Mo',
      if (details['statut'] != null) 'statut ${details['statut']}',
    ].join(' · ');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 8, 20), children: [
      FsText('${(d['raison_libelle'] ?? d['raison'] ?? '').toString()} · ${(d['poste'] ?? '').toString().isNotEmpty ? d['poste'] : fsFormatId(fsId)}',
          style: FsType.sans(18, FontWeight.w800, color: t.ink)),
      const SizedBox(height: 6),
      FsText('#${d['id']} · survenu ${_date(d['survenu_le'])} · reçu ${_date(d['recu_le'])}', style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: FsText(infos, style: FsType.sans(13, FontWeight.w500, color: t.ink))),
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
      if (memoire.isNotEmpty) ...[
        const SizedBox(height: 4),
        FsText('Mémoire à la sortie : $memoire', style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
      ],
      const SizedBox(height: 14),
      _bloc(context, 'Description', (d['description'] ?? '').toString()),
      _bloc(context, 'Trace', (d['trace'] ?? '').toString()),
      _bloc(context, 'Logcat (fin)', (d['logcat'] ?? '').toString()),
      _bloc(context, 'Journal Rust (fin)', (d['journal_rust'] ?? '').toString()),
      if (details.isNotEmpty) _bloc(context, 'Détails', const JsonEncoder.withIndent('  ').convert(details)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: Align(alignment: Alignment.centerRight, child: _outils(context))),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 5, child: _liste(context)),
          VerticalDivider(width: 1, color: t.line),
          Expanded(flex: 5, child: _volet(context)),
        ]),
      ),
    ]);
  }
}
