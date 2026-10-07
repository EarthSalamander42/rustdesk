// FS Support — rendu « ligne filetée » des appareils (Atelier), branché sur les vrais pairs RustDesk.
//
// Accroches :
//   - peer_card.dart (`_PeerCardState._buildLandscape`) : en mode liste, la carte RustDesk cède la place à [fsPeerRow] ;
//     menus, double-clic, sélection et état en ligne restent ceux de RustDesk ;
//   - peers_view.dart : hauteur de ligne [fsListRowHeight], lignes jointives, et [FsGroupingScope] qui permet à
//     l'accueil d'afficher la même source (sessions récentes) groupée (« Appareils ») ou à plat (« Récents »).
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

import '../common/widgets/fs_company_groups.dart';
import 'package:get/get.dart';

import '../models/peer_model.dart';
import '../models/peer_tab_model.dart';

/// Appareil sélectionné d'un clic (hors multi-sélection) : surligné, bouton « Contrôler » visible.
final fsSelectedPeerId = ''.obs;

/// Hauteur d'une ligne d'appareil en mode liste.
const double fsListRowHeight = FsDims.row;

/// Autorise (ou interdit) le regroupement par entreprise des vues d'appareils placées dessous.
class FsGroupingScope extends InheritedWidget {
  const FsGroupingScope({super.key, required this.enabled, required super.child});
  final bool enabled;

  static bool allowed(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FsGroupingScope>()?.enabled ?? true;

  @override
  bool updateShouldNotify(FsGroupingScope oldWidget) => oldWidget.enabled != enabled;
}

FsOs fsOsOf(Peer p) {
  final s = p.platform.toLowerCase();
  if (s.contains('android')) return FsOs.android;
  if (s.contains('mac') || s.contains('ios')) return FsOs.mac;
  if (s.contains('linux')) return FsOs.linux;
  if (s.contains('windows')) return FsOs.windows;
  return FsOs.other;
}

/// Libellé du système, affiché dans la 4e colonne (RustDesk ne conserve pas la date de dernière session).
String fsPlatformLabel(Peer p) {
  switch (fsOsOf(p)) {
    case FsOs.windows:
      return 'Windows';
    case FsOs.android:
      return 'Android';
    case FsOs.mac:
      return p.platform.toLowerCase().contains('ios') ? 'iOS' : 'macOS';
    case FsOs.linux:
      return 'Linux';
    case FsOs.other:
      return p.platform;
  }
}

FsDevice fsDeviceOf(Peer p) {
  final user = '${p.username}${p.username.isNotEmpty && p.hostname.isNotEmpty ? '@' : ''}${p.hostname}';
  return FsDevice(
    id: p.id,
    name: p.alias,
    user: user,
    os: fsOsOf(p),
    online: p.online,
    lastSession: fsPlatformLabel(p),
    payload: p,
  );
}

/// Ligne d'appareil de l'Atelier pour un pair RustDesk.
Widget fsPeerRow(
  BuildContext context,
  Peer peer, {
  required PeerTabModel tabModel,
  required VoidCallback onConnect,
  required void Function(Offset globalPosition) onMore,
}) {
  final grouped = fsGroupByCompany.value && FsGroupingScope.allowed(context);
  final multi = tabModel.multiSelectionMode;
  final selected = multi ? tabModel.isPeerSelected(peer.id) : fsSelectedPeerId.value == peer.id;
  return FsDeviceRow(
    device: fsDeviceOf(peer),
    selected: selected,
    flat: !grouped,
    allowOffline: true,
    actions: FsDeviceActions(
      onSelect: (_) {
        if (multi) {
          tabModel.select(peer);
        } else {
          fsSelectedPeerId.value = peer.id;
        }
      },
      onConnect: (_) => onConnect(),
      onMore: (_, pos) => onMore(pos),
    ),
  );
}
