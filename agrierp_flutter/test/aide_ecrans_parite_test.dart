import 'dart:io';

import 'package:agrierp/core/aide/aide_ecrans.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/widgets/aide_flottante.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket AIDE-1 — PARITÉ EXÉCUTÉE DES TEXTES D'AIDE : `agrierp_laravel/lang/fr/aide_ecrans.php` (source unique, le maître)
/// est exécuté par le vrai PHP et comparé MOT POUR MOT à `lib/core/aide/aide_ecrans.dart`, par la correspondance
/// « écran du poste ↔ chemin de la route » du châssis (`chassis_web_test.dart`, lue dans son source).
///
/// Un texte modifié d'un seul côté fait rougir ce test ; le poste se régénère par `php outils/generer_aide_ecrans.php`.
void main() {
  final raison = sautSansPhp();
  final fichierAide = File('$dossierLaravel/lang/fr/aide_ecrans.php');
  final saut = raison ?? (fichierAide.existsSync() ? null : 'SAUT : lang/fr/aide_ecrans.php absent ($dossierLaravel)');

  Map<String, dynamic> web() => executerPhp(r'''<?php
echo json_encode(require 'lang/fr/aide_ecrans.php');
''', null) as Map<String, dynamic>;

  List<String> puces(dynamic l) => [for (final p in l as List) p as String];

  test('chaque EcranPoste a une aide, sans panneau vide', () {
    for (final e in EcranPoste.values) {
      final aide = AideEcrans.parEcran[e];
      expect(aide, isNotNull, reason: '${e.name} n\'a pas d\'aide');
      expect(aide!.titre.trim(), isNotEmpty, reason: e.name);
      expect(aide.puces.length, inInclusiveRange(3, 5), reason: e.name);
    }
    // Un écran absent de la table reçoit l'aide par défaut (jamais de panneau vide).
    expect(AideEcrans.parDefaut.puces, isNotEmpty);
  });

  test('l aide de chaque écran est celle du web, mot pour mot', () {
    final ecrans = web()['ecrans'] as Map<String, dynamic>;
    final ecarts = <String>[];
    for (final MapEntry(key: e, value: chemin) in AideEcrans.cheminsWeb.entries) {
      final w = ecrans[chemin] as Map<String, dynamic>?;
      if (w == null) {
        ecarts.add('${e.name} : chemin $chemin absent du web');
        continue;
      }
      final p = AideEcrans.parEcran[e]!;
      if (p.titre != w['titre']) ecarts.add('${e.name} : titre « ${p.titre} » / web « ${w['titre']} »');
      if (p.puces.join('\n') != puces(w['puces']).join('\n')) ecarts.add('${e.name} : puces différentes de $chemin');
    }
    expect(ecarts, isEmpty, reason: 'régénérer : php outils/generer_aide_ecrans.php');
  }, skip: saut);

  test('les écrans sans route web lisent poste_seul ; le défaut, le panneau et la visite sont ceux du web', () {
    final w = web();
    final posteSeul = w['poste_seul'] as Map<String, dynamic>;
    expect(AideEcrans.posteSeul.map((e) => e.name).toSet(), posteSeul.keys.toSet());
    for (final e in AideEcrans.posteSeul) {
      expect(AideEcrans.parEcran[e]!.titre, posteSeul[e.name]['titre']);
      expect(AideEcrans.parEcran[e]!.puces, puces(posteSeul[e.name]['puces']));
      expect(AideEcrans.cheminsWeb.containsKey(e), isFalse);
    }

    expect(AideEcrans.parDefaut.titre, w['defaut']['titre']);
    expect(AideEcrans.parDefaut.puces, puces(w['defaut']['puces']));
    expect(AideEcrans.panneau, (w['panneau'] as Map).cast<String, String>());

    final visite = w['visite'] as Map<String, dynamic>;
    final libelles = {for (final MapEntry(:key, :value) in visite.entries) if (key != 'etapes') key: value as String};
    expect(AideEcrans.libellesVisite, libelles);
    final etapes = visite['etapes'] as List;
    expect(AideEcrans.etapesVisite.length, 4);
    expect(AideEcrans.etapesVisite.length, etapes.length);
    for (var i = 0; i < etapes.length; i++) {
      expect(AideEcrans.etapesVisite[i].titre, etapes[i]['titre']);
      expect(AideEcrans.etapesVisite[i].texte, etapes[i]['texte']);
    }
  }, skip: saut);

  test('la correspondance chemin ↔ EcranPoste reprend celle du châssis (chassis_web_test.dart)', () {
    final chassis = File('test/chassis_web_test.dart').readAsStringSync();
    final paires = RegExp(r"EcranPoste\.(\w+):\s*'(/[^']+)'").allMatches(chassis).toList();
    expect(paires.length, greaterThanOrEqualTo(32));
    for (final m in paires) {
      final e = EcranPoste.values.byName(m.group(1)!);
      expect(AideEcrans.cheminsWeb[e], m.group(2), reason: e.name);
    }
  });

  test('chaque chemin web de la table existe dans routes/web.php', () {
    final routes = File('$dossierLaravel/routes/web.php');
    if (!routes.existsSync()) return;
    final texte = routes.readAsStringSync();
    for (final chemin in AideEcrans.cheminsWeb.values) {
      expect(texte, contains("Route::get('$chemin'"), reason: chemin);
    }
  });

  test('les quatre cibles de la visite sont celles du Blade (data-aide), dans le même ordre', () {
    final composant = File('$dossierLaravel/resources/views/components/aide-flottante.blade.php');
    final layout = File('$dossierLaravel/resources/views/layouts/app.blade.php');
    if (!composant.existsSync() || !layout.existsSync()) return;
    final m = RegExp(r"'cibles' => \[([^\]]+)\]").firstMatch(composant.readAsStringSync())!;
    final web = RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
    expect(web, ['aide', 'topbar', 'contenu', 'menu']);
    expect(CiblesVisite.ordre, web);
    expect(CiblesVisite().parEtape.length, 4);
    final blade = layout.readAsStringSync();
    for (final c in ['topbar', 'contenu', 'menu']) {
      expect(blade, contains('data-aide="$c"'));
    }
  });
}
