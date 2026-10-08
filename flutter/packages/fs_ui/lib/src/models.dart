// Données de présentation : de simples valeurs, sans rien du moteur RustDesk.
// Les adaptateurs du client (flutter/lib/fs/) les remplissent à partir des vrais pairs.
import 'package:flutter/widgets.dart';

enum FsOs { windows, android, mac, linux, other }

/// Un appareil tel que l'affiche la liste filetée.
@immutable
class FsDevice {
  const FsDevice({
    required this.id,
    required this.name,
    this.user = '',
    this.os = FsOs.windows,
    this.online = false,
    this.lastSession = '',
    this.payload,
  });

  /// Identifiant RustDesk brut (sans espaces).
  final String id;

  /// Nom affiché (alias) ; vide = on affiche l'ID.
  final String name;

  /// Ligne secondaire : `utilisateur@machine`.
  final String user;
  final FsOs os;
  final bool online;

  /// Libellé déjà formaté (« Il y a 2 h », « Hier », « 12 sept. »).
  final String lastSession;

  /// Objet d'origine (le `Peer` du client), rendu tel quel aux rappels.
  final Object? payload;

  String get label => name.isNotEmpty ? name : fsFormatId(id);
}

/// Une entreprise et ses appareils.
@immutable
class FsCompany {
  const FsCompany({required this.name, required this.devices, this.unclassified = false});
  final String name;
  final List<FsDevice> devices;

  /// Groupe « Non classés » : replié par défaut, toujours en dernier.
  final bool unclassified;

  int get onlineCount => devices.where((d) => d.online).length;
}

/// Entrée du rail de navigation.
@immutable
class FsNavItem {
  const FsNavItem({required this.key, required this.icon, required this.label, this.count, this.soon = false});
  final String key;
  final IconData icon;
  final String label;

  /// Nombre affiché à droite (`em`), ou rien.
  final int? count;

  /// Emplacement prévu (« Bientôt »).
  final bool soon;
}

/// « 284553907 » → « 284 553 907 » (groupes de trois, comme RustDesk).
String fsFormatId(String id) {
  final s = id.replaceAll(' ', '');
  if (s.isEmpty || int.tryParse(s) == null) return id;
  final b = StringBuffer();
  final head = s.length % 3;
  if (head > 0) b.write(s.substring(0, head));
  for (var i = head; i < s.length; i += 3) {
    if (b.isNotEmpty) b.write(' ');
    b.write(s.substring(i, i + 3));
  }
  return b.toString();
}
