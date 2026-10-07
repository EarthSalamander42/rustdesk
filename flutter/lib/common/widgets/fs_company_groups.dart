// FS Support : appareils regroupés par entreprise (sections repliables).
//
// L'entreprise d'un appareil vient, dans l'ordre :
//   1. du choix fait à la main (menu ⋮ de l'appareil › « Entreprise… »), enregistré localement ;
//   2. du nom de l'appareil : ce qui précède « - » (« GalloBTP - Elisa » → GalloBTP), sinon le premier mot quand le nom
//      en compte plusieurs (« ETS Mathilde » → ETS), sinon la partie avant le premier tiret (« AB2J-HV » → AB2J) ;
//   3. sinon « Non classés » (appareils sans nom, affichés par leur identifiant).
// Les regroupements et l'état replié/déplié sont propres à ce poste (options locales).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../fs/fs_peer_row.dart';
import 'package:fs_ui/fs_ui.dart';
import 'peer_card.dart' show peerCardUiType, PeerUiType;

const String kOptionFsGroupByCompany = 'fs-group-by-company';
const String kOptionFsCompanyMap = 'fs-company-map';
const String kOptionFsCompanyCollapsed = 'fs-company-collapsed';
const String kFsUnclassified = 'Non classés';

/// Vue regroupée par entreprise activée (bouton de la barre d'outils).
final fsGroupByCompany = false.obs;

/// Incrémenté à chaque changement d'entreprise ou de repli : force la reconstruction de la vue.
final fsCompanyVersion = 0.obs;

Map<String, String> _companyMap = {};
Set<String> _collapsed = {};
bool _loaded = false;

void fsLoadCompanyOptions() {
  if (_loaded) return;
  _loaded = true;
  // Atelier : regroupement par entreprise actif tant qu'il n'a pas été coupé à la main.
  fsGroupByCompany.value =
      bind.getLocalFlutterOption(k: kOptionFsGroupByCompany) != 'N';
  try {
    final raw = bind.getLocalFlutterOption(k: kOptionFsCompanyMap);
    if (raw.isNotEmpty) {
      _companyMap = Map<String, String>.from(jsonDecode(raw) as Map);
    }
  } catch (_) {
    _companyMap = {};
  }
  try {
    final raw = bind.getLocalFlutterOption(k: kOptionFsCompanyCollapsed);
    if (raw.isNotEmpty) {
      _collapsed = Set<String>.from(jsonDecode(raw) as List);
    }
  } catch (_) {
    _collapsed = {};
  }
}

Future<void> fsSetGroupByCompany(bool value) async {
  fsGroupByCompany.value = value;
  await bind.setLocalFlutterOption(
      k: kOptionFsGroupByCompany, v: value ? 'Y' : 'N');
}

/// Entreprise choisie à la main pour cet appareil (vide si aucune).
String fsManualCompany(String peerId) => _companyMap[peerId] ?? '';

Future<void> fsSetManualCompany(String peerId, String company) async {
  final value = company.trim();
  if (value.isEmpty) {
    _companyMap.remove(peerId);
  } else {
    _companyMap[peerId] = value;
  }
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyMap, v: jsonEncode(_companyMap));
  fsCompanyVersion.value++;
}

String _guessCompany(Peer peer) {
  final name = peer.alias.trim();
  if (name.isEmpty) return kFsUnclassified;
  final dash = name.indexOf(' - ');
  if (dash > 0) return name.substring(0, dash).trim();
  final words = name.split(RegExp(r'\s+'));
  if (words.length > 1 && words.first.length > 1) return words.first;
  final hyphen = name.indexOf('-');
  if (hyphen > 1) return name.substring(0, hyphen);
  return kFsUnclassified;
}

String fsCompanyOf(Peer peer) {
  final manual = fsManualCompany(peer.id);
  return manual.isNotEmpty ? manual : _guessCompany(peer);
}

/// Entreprises connues (choix manuels + déduites), pour proposer les noms existants.
List<String> fsKnownCompanies(List<Peer> peers) {
  final names = <String, String>{};
  for (final p in peers) {
    final c = fsCompanyOf(p);
    if (c != kFsUnclassified) names[c.toLowerCase()] = c;
  }
  for (final c in _companyMap.values) {
    names[c.toLowerCase()] = c;
  }
  final list = names.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

Future<void> _toggleCollapsed(String company) async {
  final key = company.toLowerCase();
  if (_collapsed.contains(key)) {
    _collapsed.remove(key);
  } else {
    _collapsed.add(key);
  }
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyCollapsed, v: jsonEncode(_collapsed.toList()));
  fsCompanyVersion.value++;
}

/// Dialogue « Entreprise… » : saisie libre avec les entreprises existantes en suggestions.
void fsCompanyDialog(String peerId, List<String> suggestions,
    {VoidCallback? onSaved}) {
  final controller = TextEditingController(text: fsManualCompany(peerId));
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      await fsSetManualCompany(peerId, controller.text);
      close();
      onSaved?.call();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_rounded, color: MyTheme.accent),
          const Text('Entreprise').paddingOnly(left: 10),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'entreprise',
                helperText: 'Vide = regroupement automatique d\'après le nom',
              ),
              onSubmitted: (_) => submit(),
            ),
            if (suggestions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestions
                    .map((s) => ActionChip(
                          label: Text(s),
                          onPressed: () {
                            controller.text = s;
                            controller.selection = TextSelection.collapsed(
                                offset: controller.text.length);
                          },
                        ))
                    .toList(),
              ).paddingOnly(top: 12),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel',
            icon: const Icon(Icons.close_rounded),
            onPressed: close,
            isOutline: true),
        dialogButton('OK',
            icon: const Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Liste des entreprises, chacune repliable, avec ses appareils dessous (habillage de l'Atelier :
/// en-tête filé, compteur « N en ligne », dépliage animé à la hauteur réelle).
class FsCompanyGroupedView extends StatelessWidget {
  final List<Peer> peers;
  final Widget Function(Peer peer) cardBuilder;
  final ScrollController? controller;
  final double space;

  const FsCompanyGroupedView({
    Key? key,
    required this.peers,
    required this.cardBuilder,
    this.controller,
    this.space = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Reconstruction à chaque changement d'entreprise ou de repli.
      fsCompanyVersion.value;
      final list = peerCardUiType.value == PeerUiType.list;
      final groups = <String, List<Peer>>{};
      final labels = <String, String>{};
      for (final p in peers) {
        final company = fsCompanyOf(p);
        final key = company.toLowerCase();
        labels.putIfAbsent(key, () => company);
        groups.putIfAbsent(key, () => []).add(p);
      }
      final keys = groups.keys.toList()
        ..sort((a, b) {
          final ua = a == kFsUnclassified.toLowerCase();
          final ub = b == kFsUnclassified.toLowerCase();
          if (ua != ub) return ua ? 1 : -1;
          return a.compareTo(b);
        });
      final companies = [
        for (final k in keys)
          FsCompany(
            name: labels[k]!,
            unclassified: k == kFsUnclassified.toLowerCase(),
            devices: groups[k]!.map(fsDeviceOf).toList(),
          )
      ];
      return FsGroupedDeviceList(
        controller: controller,
        companies: companies,
        isOpen: (c) => !_collapsed.contains(c.name.toLowerCase()),
        onToggle: (c, open) => _toggleCollapsed(c.name),
        rowBuilder: (d) => cardBuilder(d.payload as Peer),
        bodyBuilder: list
            ? null
            : (devices) => Wrap(
                  spacing: space,
                  runSpacing: space / 2,
                  children: devices.map((d) => cardBuilder(d.payload as Peer)).toList(),
                ).paddingOnly(left: 10, right: 10, top: 4, bottom: 12),
      );
    });
  }
}

/// Bouton de la barre d'outils : bascule la vue « par entreprise ».
class FsGroupByCompanyToggle extends StatelessWidget {
  const FsGroupByCompanyToggle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.titleLarge?.color;
    return Obx(() => Tooltip(
          message: fsGroupByCompany.value
              ? 'Afficher tous les appareils'
              : 'Regrouper par entreprise',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => fsSetGroupByCompany(!fsGroupByCompany.value),
            child: Icon(
              fsGroupByCompany.value
                  ? Icons.business_rounded
                  : Icons.business_outlined,
              size: 18,
              color: fsGroupByCompany.value ? MyTheme.accent : color,
            ).paddingAll(4),
          ),
        ));
  }
}
