// Fusion des appareils d'un poste dans le compte FS Solutions (09/11/2026).
//
// Cas : le même compte FS Connect sur plusieurs postes qui ont déjà chacun leurs appareils. Le SaaS calcule le plan
// (`/api/ab/fusion/plan`), le poste l'affiche, l'utilisateur tranche, puis le poste envoie ses choix
// (`/api/ab/fusion/appliquer`) avec l'empreinte du carnet : si un autre poste l'a modifié entre-temps, le SaaS refuse et
// le poste refait la comparaison. Logique pure, sans moteur RustDesk : testée par test/fusion_test.dart.

/// Un appareil tel que le poste le connaît, envoyé au plan (jamais de mot de passe).
class FsFusionAppareil {
  const FsFusionAppareil({
    required this.id,
    this.alias = '',
    this.username = '',
    this.hostname = '',
    this.platform = '',
    this.entreprise = '',
  });

  final String id;
  final String alias;
  final String username;
  final String hostname;
  final String platform;
  final String entreprise;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (alias.isNotEmpty) 'alias': alias,
        if (username.isNotEmpty) 'username': username,
        if (hostname.isNotEmpty) 'hostname': hostname,
        if (platform.isNotEmpty) 'platform': platform,
        if (entreprise.isNotEmpty) 'entreprise': entreprise,
      };
}

/// Corps de la demande de plan : appareils et entreprises de ce poste, dédoublonnés par ID.
Map<String, dynamic> fsFusionDemande(List<FsFusionAppareil> appareils, List<String> entreprises) {
  final parId = <String, FsFusionAppareil>{};
  for (final a in appareils) {
    if (a.id.isEmpty) continue;
    parId.putIfAbsent(a.id, () => a);
  }
  return {
    'appareils': parId.values.map((a) => a.toJson()).toList(),
    'entreprises': entreprises.where((e) => e.trim().isNotEmpty).toList(),
  };
}

/// Ligne simple du plan (appareil nouveau, complété ou retiré du compte).
class FsFusionLigne {
  const FsFusionLigne({required this.id, this.alias = '', this.entreprise = ''});

  final String id;
  final String alias;
  final String entreprise;

  String get titre => alias.isEmpty ? id : '$alias ($id)';

  static FsFusionLigne fromJson(Map<String, dynamic> m) => FsFusionLigne(
        id: '${m['id'] ?? ''}',
        alias: '${m['alias'] ?? ''}',
        entreprise: '${m['entreprise'] ?? ''}',
      );
}

/// Même appareil, valeurs différentes sur ce poste et dans le compte.
class FsFusionConflit {
  const FsFusionConflit({
    required this.id,
    required this.differences,
    required this.aliasCompte,
    required this.entrepriseCompte,
    required this.aliasPoste,
    required this.entreprisePoste,
  });

  final String id;
  final List<String> differences;
  final String aliasCompte;
  final String entrepriseCompte;
  final String aliasPoste;
  final String entreprisePoste;

  /// Résumé d'un côté : « Bureau · Société Durand ».
  String cote({required bool poste}) {
    final alias = poste ? aliasPoste : aliasCompte;
    final ent = poste ? entreprisePoste : entrepriseCompte;
    return [alias.isEmpty ? id : alias, ent.isEmpty ? 'Non classé' : ent].join(' · ');
  }

  static FsFusionConflit fromJson(Map<String, dynamic> m) {
    final compte = (m['compte'] as Map?) ?? const {};
    final poste = (m['poste'] as Map?) ?? const {};
    return FsFusionConflit(
      id: '${m['id'] ?? ''}',
      differences: ((m['differences'] as List?) ?? const []).map((e) => '$e').toList(),
      aliasCompte: '${compte['alias'] ?? ''}',
      entrepriseCompte: '${compte['entreprise'] ?? ''}',
      aliasPoste: '${poste['alias'] ?? ''}',
      entreprisePoste: '${poste['entreprise'] ?? ''}',
    );
  }
}

/// Plan renvoyé par le SaaS.
class FsFusionPlan {
  const FsFusionPlan({
    required this.empreinte,
    required this.appareilsCompte,
    required this.nouveaux,
    required this.identiques,
    required this.completes,
    required this.conflits,
    required this.retires,
    required this.entreprisesNouvelles,
    required this.entreprisesFusionnees,
  });

  final String empreinte;
  final int appareilsCompte;
  final List<FsFusionLigne> nouveaux;
  final int identiques;
  final List<FsFusionLigne> completes;
  final List<FsFusionConflit> conflits;
  final List<FsFusionLigne> retires;
  final List<String> entreprisesNouvelles;

  /// « nom sur ce poste → nom gardé dans le compte ».
  final List<(String, String)> entreprisesFusionnees;

  /// Quelque chose à montrer ? Sinon le poste est déjà à jour et rien n'est demandé.
  bool get utile =>
      nouveaux.isNotEmpty || completes.isNotEmpty || conflits.isNotEmpty || retires.isNotEmpty || entreprisesNouvelles.isNotEmpty;

  static FsFusionPlan fromJson(Map<String, dynamic> m) {
    List<FsFusionLigne> lignes(String k) =>
        ((m[k] as List?) ?? const []).whereType<Map>().map((e) => FsFusionLigne.fromJson(Map<String, dynamic>.from(e))).toList();
    final ent = (m['entreprises'] as Map?) ?? const {};
    return FsFusionPlan(
      empreinte: '${m['empreinte'] ?? ''}',
      appareilsCompte: (m['appareilsCompte'] as num?)?.toInt() ?? 0,
      nouveaux: lignes('nouveaux'),
      identiques: ((m['identiques'] as List?) ?? const []).length,
      completes: lignes('completes'),
      conflits: ((m['conflits'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => FsFusionConflit.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      retires: lignes('retires'),
      entreprisesNouvelles: ((ent['nouvelles'] as List?) ?? const []).map((e) => '$e').toList(),
      entreprisesFusionnees: ((ent['fusionnees'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ('${e['poste'] ?? ''}', '${e['compte'] ?? ''}'))
          .toList(),
    );
  }
}

/// Choix de l'utilisateur sur l'écran de fusion. Par défaut, le plus prudent : nouveaux appareils ajoutés, conflits
/// tranchés pour le COMPTE (rien n'y est écrasé), appareils retirés du compte laissés de côté.
class FsFusionChoix {
  FsFusionChoix(FsFusionPlan plan)
      : ajouter = {for (final n in plan.nouveaux) n.id},
        garderPoste = {},
        ressusciter = {};

  /// Nouveaux appareils cochés (à ajouter au compte).
  final Set<String> ajouter;

  /// Conflits tranchés pour « ce poste » (sinon le compte est gardé).
  final Set<String> garderPoste;

  /// Appareils retirés du compte que l'utilisateur veut y remettre.
  final Set<String> ressusciter;

  /// Corps de `/api/ab/fusion/appliquer`.
  Map<String, dynamic> corps(FsFusionPlan plan, Map<String, dynamic> demande) => {
        ...demande,
        'empreinte': plan.empreinte,
        'choix': {for (final c in plan.conflits) c.id: garderPoste.contains(c.id) ? 'poste' : 'saas'},
        'ignorer': plan.nouveaux.where((n) => !ajouter.contains(n.id)).map((n) => n.id).toList(),
        'ressusciter': plan.retires.where((r) => ressusciter.contains(r.id)).map((r) => r.id).toList(),
      };

  /// Appareils de ce poste qui ne doivent pas partir seuls plus tard (décochés ou retirés non remis).
  List<String> laissesDeCote(FsFusionPlan plan) => [
        ...plan.nouveaux.where((n) => !ajouter.contains(n.id)).map((n) => n.id),
        ...plan.retires.where((r) => !ressusciter.contains(r.id)).map((r) => r.id),
      ];
}

/// Bilan lisible d'une fusion appliquée.
String fsFusionBilan(Map<String, dynamic> r) {
  int n(String k) => (r[k] as num?)?.toInt() ?? 0;
  final morceaux = <String>[
    if (n('ajoutes') > 0) '${n('ajoutes')} appareil${n('ajoutes') > 1 ? 's' : ''} ajouté${n('ajoutes') > 1 ? 's' : ''}',
    if (n('completes') > 0) '${n('completes')} complété${n('completes') > 1 ? 's' : ''}',
    if (n('remplaces') > 0) '${n('remplaces')} mis à jour depuis ce PC',
    if (n('entreprises') > 0) '${n('entreprises')} entreprise${n('entreprises') > 1 ? 's' : ''} créée${n('entreprises') > 1 ? 's' : ''}',
  ];
  return morceaux.isEmpty ? 'Rien à changer : vos appareils étaient déjà à jour.' : '${morceaux.join(', ')}.';
}
