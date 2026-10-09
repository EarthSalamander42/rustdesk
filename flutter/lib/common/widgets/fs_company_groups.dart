// FS Support : appareils regroupés par entreprise (sections repliables).
//
// Aucune entreprise n'est créée d'office : un appareil n'appartient à une entreprise que si on l'y a
// rangé à la main (menu ⋮ de l'appareil › « Entreprise… »). Sinon il est dans « Non classés ».
// Les entreprises se gèrent dans « Entreprises… » (barre d'outils) ou depuis l'en-tête de chaque
// groupe : ajouter, renommer (fusionne si le nom existe déjà), supprimer (ses appareils repassent
// dans « Non classés »).
// Entreprises, rattachements et état replié/déplié sont propres à ce poste (options locales).

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
const String kOptionFsCompanyList = 'fs-company-list';
const String kOptionFsCompanyCollapsed = 'fs-company-collapsed';
const String kFsUnclassified = 'Non classés';

/// Vue regroupée par entreprise activée (bouton de la barre d'outils).
final fsGroupByCompany = false.obs;

/// Incrémenté à chaque changement d'entreprise ou de repli : force la reconstruction de la vue.
final fsCompanyVersion = 0.obs;

/// Appareil → entreprise (choix manuels uniquement).
Map<String, String> _companyMap = {};

/// Entreprises déclarées, y compris celles qui n'ont encore aucun appareil.
List<String> _companies = [];
Set<String> _collapsed = {};
bool _loaded = false;

String _key(String name) => name.trim().toLowerCase();

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
    final raw = bind.getLocalFlutterOption(k: kOptionFsCompanyList);
    if (raw.isNotEmpty) {
      _companies = List<String>.from(jsonDecode(raw) as List);
    }
  } catch (_) {
    _companies = [];
  }
  // Reprise : les entreprises choisies avant l'existence de la liste y sont ajoutées.
  for (final c in _companyMap.values) {
    _addToList(c);
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

bool _addToList(String company) {
  final name = company.trim();
  if (name.isEmpty || _key(name) == _key(kFsUnclassified)) return false;
  if (_companies.any((c) => _key(c) == _key(name))) return false;
  _companies.add(name);
  return true;
}

/// Nom déjà déclaré (avec sa casse d'origine), sinon le nom saisi.
String _canonical(String company) {
  final name = company.trim();
  return _companies.firstWhere((c) => _key(c) == _key(name), orElse: () => name);
}

Future<void> _save() async {
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyMap, v: jsonEncode(_companyMap));
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyList, v: jsonEncode(_companies));
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyCollapsed, v: jsonEncode(_collapsed.toList()));
  fsCompanyVersion.value++;
}

/// Entreprise choisie à la main pour cet appareil (vide si aucune).
String fsManualCompany(String peerId) => _companyMap[peerId] ?? '';

Future<void> fsSetManualCompany(String peerId, String company) async {
  final value = company.trim();
  if (value.isEmpty || _key(value) == _key(kFsUnclassified)) {
    _companyMap.remove(peerId);
  } else {
    final name = _canonical(value);
    _addToList(name);
    _companyMap[peerId] = name;
  }
  await _save();
}

String fsCompanyOf(Peer peer) {
  final manual = fsManualCompany(peer.id);
  return manual.isNotEmpty ? manual : kFsUnclassified;
}

/// Entreprises déclarées, triées (sans « Non classés »).
List<String> fsKnownCompanies([List<Peer>? peers]) {
  final list = List<String>.from(_companies)
    ..sort((a, b) => _key(a).compareTo(_key(b)));
  return list;
}

/// Nombre d'appareils rangés dans une entreprise.
int fsCompanyDeviceCount(String company) =>
    _companyMap.values.where((c) => _key(c) == _key(company)).length;

/// Ajoute une entreprise vide. Faux si le nom est vide ou existe déjà.
Future<bool> fsAddCompany(String company) async {
  if (!_addToList(company)) return false;
  await _save();
  return true;
}

/// Renomme une entreprise. Si le nouveau nom existe déjà, les deux sont fusionnées.
Future<void> fsRenameCompany(String from, String to) async {
  final target = to.trim();
  if (target.isEmpty || _key(target) == _key(kFsUnclassified)) return;
  final merge = _companies.any(
      (c) => _key(c) == _key(target) && _key(c) != _key(from));
  final name = merge ? _canonical(target) : target;
  final i = _companies.indexWhere((c) => _key(c) == _key(from));
  if (merge || i < 0) {
    _companies.removeWhere((c) => _key(c) == _key(from));
    _addToList(name);
  } else {
    _companies[i] = name;
  }
  _companyMap.updateAll((_, c) => _key(c) == _key(from) ? name : c);
  if (_collapsed.remove(_key(from))) _collapsed.add(_key(name));
  await _save();
}

/// Supprime une entreprise : ses appareils repassent dans « Non classés ».
Future<void> fsDeleteCompany(String company) async {
  _companies.removeWhere((c) => _key(c) == _key(company));
  _companyMap.removeWhere((_, c) => _key(c) == _key(company));
  _collapsed.remove(_key(company));
  await _save();
}

Future<void> _toggleCollapsed(String company) async {
  final key = _key(company);
  if (_collapsed.contains(key)) {
    _collapsed.remove(key);
  } else {
    _collapsed.add(key);
  }
  await bind.setLocalFlutterOption(
      k: kOptionFsCompanyCollapsed, v: jsonEncode(_collapsed.toList()));
  fsCompanyVersion.value++;
}

Widget _dialogTitle(IconData icon, String text) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: MyTheme.accent),
        Text(text).paddingOnly(left: 10),
      ],
    );

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
      title: _dialogTitle(Icons.business_rounded, 'Entreprise'),
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
                helperText: 'Vide = Non classés',
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

/// Dialogue « Renommer l'entreprise ».
Future<void> fsRenameCompanyDialog(String company) async {
  final controller = TextEditingController(text: company);
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: company.length);
  await gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      await fsRenameCompany(company, controller.text);
      close();
    }

    return CustomAlertDialog(
      title: _dialogTitle(Icons.edit_rounded, 'Renommer l\'entreprise'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nouveau nom',
            helperText: 'Un nom déjà utilisé fusionne les deux entreprises',
          ),
          onSubmitted: (_) => submit(),
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

/// Confirmation de suppression d'une entreprise.
Future<void> fsDeleteCompanyDialog(String company) async {
  final n = fsCompanyDeviceCount(company);
  await gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      await fsDeleteCompany(company);
      close();
    }

    return CustomAlertDialog(
      title: _dialogTitle(Icons.delete_outline_rounded, 'Supprimer l\'entreprise'),
      content: SizedBox(
        width: 360,
        child: Text(n == 0
            ? 'Supprimer « $company » ?'
            : 'Supprimer « $company » ? ${n == 1 ? 'Son appareil repassera' : 'Ses $n appareils repasseront'} dans « $kFsUnclassified ». Aucun appareil n\'est supprimé.'),
      ),
      actions: [
        dialogButton('Cancel',
            icon: const Icon(Icons.close_rounded),
            onPressed: close,
            isOutline: true),
        dialogButton('Supprimer',
            icon: const Icon(Icons.delete_outline_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Dialogue « Entreprises » : liste, ajout, renommage, suppression.
void fsManageCompaniesDialog() {
  final controller = TextEditingController();
  gFFI.dialogManager.show((setState, close, context) {
    add() async {
      if (await fsAddCompany(controller.text)) controller.clear();
      setState(() {});
    }

    final companies = fsKnownCompanies();
    return CustomAlertDialog(
      title: _dialogTitle(Icons.corporate_fare_rounded, 'Entreprises'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nouvelle entreprise',
                  ),
                  onSubmitted: (_) => add(),
                ),
              ),
              IconButton(
                tooltip: 'Ajouter',
                icon: Icon(Icons.add_rounded, color: MyTheme.accent),
                onPressed: add,
              ),
            ]),
            const SizedBox(height: 12),
            if (companies.isEmpty)
              Text(
                'Aucune entreprise. Ajoutez-en une ici, ou rangez un appareil depuis son menu › « Entreprise… ».',
                style: TextStyle(color: Theme.of(context).hintColor),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in companies)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(c),
                        subtitle: Text(FsStrings.nDevices(fsCompanyDeviceCount(c))),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Renommer',
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            onPressed: () async {
                              await fsRenameCompanyDialog(c);
                              setState(() {});
                            },
                          ),
                          IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            onPressed: () async {
                              await fsDeleteCompanyDialog(c);
                              setState(() {});
                            },
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        dialogButton('Close',
            icon: const Icon(Icons.done_rounded), onPressed: close),
      ],
      onCancel: close,
    );
  });
}

/// Menu ⋮ de l'en-tête d'une entreprise : renommer, supprimer.
Widget fsCompanyHeaderMenu(FsCompany c) {
  if (c.unclassified) return const SizedBox.shrink();
  return PopupMenuButton<String>(
    tooltip: 'Gérer l\'entreprise',
    icon: const Icon(Icons.more_vert_rounded, size: 18),
    padding: EdgeInsets.zero,
    splashRadius: 16,
    onSelected: (v) {
      if (v == 'rename') fsRenameCompanyDialog(c.name);
      if (v == 'delete') fsDeleteCompanyDialog(c.name);
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'rename', child: Text('Renommer…')),
      PopupMenuItem(value: 'delete', child: Text('Supprimer l\'entreprise')),
    ],
  );
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
        final key = _key(company);
        labels.putIfAbsent(key, () => company);
        groups.putIfAbsent(key, () => []).add(p);
      }
      final keys = groups.keys.toList()
        ..sort((a, b) {
          final ua = a == _key(kFsUnclassified);
          final ub = b == _key(kFsUnclassified);
          if (ua != ub) return ua ? 1 : -1;
          return a.compareTo(b);
        });
      final companies = [
        for (final k in keys)
          FsCompany(
            name: labels[k]!,
            unclassified: k == _key(kFsUnclassified),
            devices: groups[k]!.map(fsDeviceOf).toList(),
          )
      ];
      return FsGroupedDeviceList(
        controller: controller,
        companies: companies,
        isOpen: (c) => !_collapsed.contains(_key(c.name)),
        onToggle: (c, open) => _toggleCollapsed(c.name),
        headerTrailing: fsCompanyHeaderMenu,
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

/// Boutons de la barre d'outils : bascule la vue « par entreprise » et, quand elle est active,
/// ouvre la gestion des entreprises.
class FsGroupByCompanyToggle extends StatelessWidget {
  const FsGroupByCompanyToggle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.titleLarge?.color;
    return Obx(() => Row(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(
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
          ),
          if (fsGroupByCompany.value)
            Tooltip(
              message: 'Gérer les entreprises',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: fsManageCompaniesDialog,
                child: Icon(Icons.edit_note_rounded, size: 18, color: color)
                    .paddingAll(4),
              ),
            ),
        ]));
  }
}
