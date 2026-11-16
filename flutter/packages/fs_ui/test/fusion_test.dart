// Fusion des appareils d'un poste dans le compte : lecture du plan, choix par défaut prudents, corps envoyé.
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_ui/fs_ui.dart';

const planJson = {
  'empreinte': '0123456789abcdef0123456789abcdef',
  'appareilsCompte': 3,
  'nouveaux': [
    {'id': '444444444', 'alias': 'Neuf', 'entreprise': 'Garage Martin'},
    {'id': '666666666', 'alias': '', 'entreprise': ''},
  ],
  'identiques': ['111111111'],
  'completes': [
    {'id': '333333333', 'alias': 'Atelier', 'entreprise': 'Garage Martin', 'champs': ['alias']},
  ],
  'conflits': [
    {
      'id': '222222222',
      'differences': ['alias', 'entreprise'],
      'compte': {'alias': 'Bureau', 'entreprise': 'Société Durand'},
      'poste': {'alias': 'Direction', 'entreprise': ''},
      'completes': [],
    },
  ],
  'retires': [
    {'id': '555555555', 'alias': 'Ancien', 'entreprise': ''},
  ],
  'entreprises': {
    'nouvelles': ['Garage Martin'],
    'fusionnees': [
      {'poste': 'societe durand', 'compte': 'Société Durand'},
    ],
  },
};

void main() {
  test('demande : dédoublonnée par ID, jamais de champ vide ni de mot de passe', () {
    final d = fsFusionDemande([
      const FsFusionAppareil(id: '123456789', alias: 'A'),
      const FsFusionAppareil(id: '123456789', alias: 'B'),
      const FsFusionAppareil(id: ''),
    ], [
      'Durand',
      ' ',
    ]);
    expect(d['appareils'], [
      {'id': '123456789', 'alias': 'A'},
    ]);
    expect(d['entreprises'], ['Durand']);
    expect(d.toString().contains('password'), isFalse);
  });

  test('plan : lu depuis le SaaS', () {
    final p = FsFusionPlan.fromJson(Map<String, dynamic>.from(planJson));
    expect(p.utile, isTrue);
    expect(p.nouveaux.map((n) => n.id), ['444444444', '666666666']);
    expect(p.nouveaux[1].titre, '666666666');
    expect(p.identiques, 1);
    expect(p.conflits.single.cote(poste: false), 'Bureau · Société Durand');
    expect(p.conflits.single.cote(poste: true), 'Direction · Non classé');
    expect(p.entreprisesFusionnees.single, ('societe durand', 'Société Durand'));
  });

  test('plan vide : rien à demander', () {
    final p = FsFusionPlan.fromJson({'empreinte': 'x', 'identiques': ['1']});
    expect(p.utile, isFalse);
  });

  test('choix par défaut : nouveaux ajoutés, compte gardé en cas de conflit, retirés laissés de côté', () {
    final p = FsFusionPlan.fromJson(Map<String, dynamic>.from(planJson));
    final c = FsFusionChoix(p);
    final corps = c.corps(p, {'appareils': []});
    expect(corps['empreinte'], p.empreinte);
    expect(corps['choix'], {'222222222': 'saas'});
    expect(corps['ignorer'], isEmpty);
    expect(corps['ressusciter'], isEmpty);
    expect(c.laissesDeCote(p), ['555555555']);
  });

  test('choix modifiés : un nouveau décoché, conflit pour ce poste, retiré remis', () {
    final p = FsFusionPlan.fromJson(Map<String, dynamic>.from(planJson));
    final c = FsFusionChoix(p)
      ..ajouter.remove('666666666')
      ..garderPoste.add('222222222')
      ..ressusciter.add('555555555');
    final corps = c.corps(p, {});
    expect(corps['choix'], {'222222222': 'poste'});
    expect(corps['ignorer'], ['666666666']);
    expect(corps['ressusciter'], ['555555555']);
    expect(c.laissesDeCote(p), ['666666666']);
  });

  test('bilan lisible', () {
    expect(fsFusionBilan({'ajoutes': 2, 'remplaces': 1, 'entreprises': 1}),
        '2 appareils ajoutés, 1 mis à jour depuis ce PC, 1 entreprise créée.');
    expect(fsFusionBilan({}), 'Rien à changer : vos appareils étaient déjà à jour.');
  });

  test('clé locale par compte : acceptée par les réglages de l\'Atelier', () {
    final valide = RegExp(r'^fs-[A-Za-z0-9-]{1,61}
);
    final k = fsCleCompte('fs-saas-sauvegarde', 'contact@novapilotagency.com');
    expect(valide.hasMatch(k), isTrue, reason: k);
    expect(k.length, lessThanOrEqualTo(64));
    // Stable, insensible à la casse et aux espaces, différente d'un compte à l'autre et d'un usage à l'autre.
    expect(k, fsCleCompte('fs-saas-sauvegarde', '  Contact@NovaPilotAgency.com '));
    expect(k, isNot(fsCleCompte('fs-saas-sauvegarde', 'autre@exemple.fr')));
    expect(k, isNot(fsCleCompte('fs-saas-import', 'contact@novapilotagency.com')));
    // FNV-1a 32 bits de référence : "a" → e40c292c.
    expect(fsCleCompte('fs-x', 'a').substring(5, 13), 'e40c292c');
  });

  test('cause et avertissement local', () {
    expect(fsFusionCause(const FormatException('Unexpected end of input')), startsWith('Détail : FormatException'));
    expect(fsFusionAvertissementLocal(['vos choix', 'la copie locale']),
        'Fusion faite dans votre compte, mais ce PC n\'a pas pu noter vos choix, la copie locale.');
  });
}
