import 'dart:io';

import 'package:agrierp/features/elevage/rappels_du_jour_modale.dart';
import 'package:agrierp/features/elevage/rappels_du_jour_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket POP4 — PARITÉ BLADE ↔ DART DES LIBELLÉS de la fenêtre « Rappels du jour » (le Blade fait foi, Doctrine art. 5).
///
/// Rien n'est recopié : les libellés sont LUS dans `rappels-du-jour.blade.php` (titre, intitulé, colonnes, groupes, pied)
/// et dans `RappelsDuJourService.php` (libellés de type, formules d'échéance), puis cherchés dans la fenêtre RENDUE.
void main() {
  final cheminBlade = '$dossierLaravel/resources/views/livewire/shared/rappels-du-jour.blade.php';
  final cheminService = '$dossierLaravel/app/Services/RappelsDuJourService.php';
  final saut = File(cheminBlade).existsSync() && File(cheminService).existsSync()
      ? null
      : 'SAUT : Blade ou service introuvable ($cheminBlade) — comparaison au maître impossible';

  String blade() => File(cheminBlade).readAsStringSync();
  String service() => File(cheminService).readAsStringSync();
  String decode(String s) => s.replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();

  LigneRappel ligne(UrgenceRappel u, TypeRappel t, int jours) => LigneRappel(
    urgence: u,
    type: t,
    bande: 'LAP-A',
    espece: 'Lapins',
    libelle: 'Soin ${t.name} $jours',
    produit: '—',
    date: DateTime(2026, 10, 14 + jours),
    jours: jours,
    echeance: jours < 0 ? 'En retard de ${-jours} jours' : (jours == 0 ? "Aujourd'hui" : 'Dans $jours jours'),
  );

  Future<void> monter(WidgetTester tester, RappelsDuJour donnees) async {
    tester.view.physicalSize = const Size(1200, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => montrerRappelsDuJour(context, donnees: donnees, surMasquer: () {}),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  final donnees = RappelsDuJour(
    joursRappel: 3,
    lignes: [
      ligne(UrgenceRappel.retard, TypeRappel.soin, -2),
      ligne(UrgenceRappel.aujourdhui, TypeRappel.prophylaxie, 0),
      ligne(UrgenceRappel.avenir, TypeRappel.remanence, 3),
    ],
  );

  testWidgets('titre, intitulé, colonnes et pied lus dans le Blade', (tester) async {
    final b = blade();
    final titre = decode(RegExp(r'<h3[^>]*>.*?</span>([^<]+)</h3>').firstMatch(b)!.group(1)!);
    final intitule = decode(RegExp(r'tracking-wider text-outline">([^<]+)</p>').firstMatch(b)!.group(1)!);
    final colonnes = [for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(b)) decode(m.group(1)!)];
    final lien = decode(RegExp(r'<a (?:wire:navigate )?href="/soins-vaccins-hub"[^>]*>([^<]+)<span').firstMatch(b)!.group(1)!);
    final boutons = [
      for (final m in RegExp(r'<button type="button"[^>]*(?:masquer\(\)|wire:click="fermer" class="px-md)[^>]*>([^<]+)</button>').allMatches(b)) decode(m.group(1)!),
    ];

    expect(titre, 'Rappels du jour');
    expect(colonnes, ['Bande', 'Rappel', 'Produit', 'Date prévue', 'Échéance']);
    expect(boutons, ["Ne plus afficher aujourd'hui", 'Plus tard']);

    await monter(tester, donnees);
    expect(find.text(titre), findsOneWidget);
    expect(find.text(intitule), findsOneWidget);
    for (final c in colonnes) {
      expect(find.text(c), findsNWidgets(3), reason: 'colonne « $c » : une par groupe, comme le Blade');
    }
    expect(find.text(lien), findsOneWidget);
    for (final t in boutons) {
      expect(find.text(t), findsOneWidget, reason: 'bouton « $t »');
    }
  }, skip: saut != null);

  testWidgets('groupes d\'urgence lus dans le Blade', (tester) async {
    final b = blade();
    final titres = [for (final m in RegExp(r"'titre' => ([^,]+),").allMatches(b)) m.group(1)!.trim()];
    expect(titres, hasLength(3));
    expect(titres[0], "'En retard'");
    expect(titres[1], '"Aujourd\'hui"');
    expect(titres[2], startsWith("'À venir (sous '.\$joursRappel.' jour'"));

    await monter(tester, donnees);
    expect(find.text('En retard (1)'), findsOneWidget);
    expect(find.text("Aujourd'hui (1)"), findsOneWidget);
    expect(find.text('À venir (sous 3 jours) (1)'), findsOneWidget);
    // Le Blade accorde « jour » au pluriel dès 2 : « sous 1 jour ».
    expect(b, contains("(\$joursRappel > 1 ? 's' : '')"));
  }, skip: saut != null);

  testWidgets('libellés de type et formules d\'échéance lus dans le service', (tester) async {
    final s = service();
    for (final libelle in ['Soin planifié', 'Barème prophylactique', "Délai d'attente", "Fin du délai d'attente", 'En retard de ', 'Dans ']) {
      expect(s, contains(libelle), reason: 'le serveur n\'écrit plus « $libelle » : le poste doit suivre');
    }
    expect(s, contains('"Aujourd\'hui"'));

    await monter(tester, donnees);
    for (final libelle in ['Soin planifié', 'Barème prophylactique', "Délai d'attente"]) {
      expect(find.textContaining(libelle), findsOneWidget);
    }
    expect(find.text('En retard de 2 jours'), findsOneWidget);
    expect(find.text('Dans 3 jours'), findsOneWidget);
  }, skip: saut != null);
}
