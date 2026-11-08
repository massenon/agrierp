import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket RELEVES-1 — FIDÉLITÉ AU BLADE : les libellés de l'onglet « Relevés de terrain » (champs, colonnes, boutons,
/// sous-onglets, modales, messages) sont LUS dans les vues du web (`parametres-elevage.blade.php`,
/// `_releve-champs.blade.php`, `dashboard-elevage.blade.php`) et doivent figurer dans l'écran du poste. Un libellé
/// changé au web d'un seul côté fait rougir ce test. Sans le dépôt Laravel, les tests se SAUTENT avec leur raison.
String _lire(String chemin) {
  final f = File('$dossierLaravel/$chemin');
  return f.existsSync() ? f.readAsStringSync() : '';
}

List<String> _tous(String source, String motif) => [for (final m in RegExp(motif, dotAll: true).allMatches(source)) m.group(1)!];

void main() {
  final blade = _lire('resources/views/livewire/elevage/parametres-elevage.blade.php');
  final champs = _lire('resources/views/livewire/elevage/_releve-champs.blade.php');
  final dashboard = _lire('resources/views/livewire/elevage/dashboard-elevage.blade.php');
  final service = _lire('app/Services/Elevage/ReleveTerrainService.php');
  final saut = (blade.isEmpty || champs.isEmpty || dashboard.isEmpty || service.isEmpty) ? 'SAUT : dépôt Laravel absent ($dossierLaravel)' : null;
  final ecran = File('lib/features/elevage/parametres_elevage_screen.dart').readAsStringSync();
  final regles = File('lib/features/elevage/releve_terrain.dart').readAsStringSync();
  final ecranDashboard = File('lib/features/elevage/dashboard_elevage_screen.dart').readAsStringSync();

  /// Le texte figure dans une chaîne de [source] (apostrophe échappée ou non, selon le littéral).
  void present(String source, String texte) {
    final variantes = {texte, texte.replaceAll("'", r"\'")};
    expect(variantes.any(source.contains), isTrue, reason: "absent du poste : « $texte »");
  }

  test('le cinquième onglet, ses sous-onglets et ses boutons sont ceux du Blade', () {
    final onglets = _tous(blade, r"'label' => '([^']+)'");
    expect(onglets.last, 'Relevés de terrain');
    present(ecran, 'Relevés de terrain');
    final familles = _tous(blade, r"'(?:incubation|provende|technicien)' => \['([^']+)'");
    expect(familles, ['Incubation', 'Délais fournisseur de provende', 'Technicien — poissons-chats']);
    for (final f in familles) {
      present(ecran, f);
    }
    final ajouts = _tous(blade, r"'(?:incubation_regle|incubation_lot|poisson_bareme)' => '([^']+)'");
    expect(ajouts, ['Ajouter une règle', 'Ajouter un relevé de lot', 'Ajouter une classe de poids']);
    for (final a in ajouts) {
      present(ecran, a);
    }
  }, skip: saut);

  test('colonnes du tableau, tableau des délais, statuts et bouton « Valider » du Blade', () {
    final enTetes = _tous(blade, r':headers="\[([^\]]+)\]"');
    final listes = [for (final c in enTetes) _tous(c, r"'([^']+)'")];
    final jointes = [for (final l in listes) l.join(' | ')];
    expect(jointes, contains('Type | Libellé / espèce | Valeurs | Statut | Validé par / le | Actions'));
    expect(jointes, contains('Fournisseur | Bons retenus | Délais constatés (jours) | Critique proposé'));
    for (final l in listes) {
      for (final c in l) {
        present(ecran, c);
      }
    }
    expect(blade.contains('Valider</button>'), isTrue);
    for (final t in ['Valider', 'À valider', 'Validé', 'Aucun relevé dans cette famille.', 'Aucun bon de commande de provende reçu.', '— (moins de 5 bons)', 'Délais constatés par fournisseur (5 derniers bons de commande de provende reçus)']) {
      expect(blade.contains(t), isTrue, reason: 'absent du Blade : $t');
      present(ecran, t);
    }
  }, skip: saut);

  test('chaque champ des modales (libellés du partiel du Blade) est porté par l écran', () {
    final libelles = <String>{
      ..._tous(champs, r'<label class="\{\{ \$etiquette \}\}">([^<{]+)</label>').map((t) => t.trim()),
      'Code du lot *',
      'Libellé *',
    };
    expect(champs.contains("'Code du lot *' : 'Libellé *'"), isTrue);
    expect(libelles.length, greaterThan(25));
    for (final l in libelles) {
      present(ecran, l);
    }
    // Les modes d'incubation, de délai et les libellés de type viennent du service du web.
    for (final m in _tous(service, r"'(?:couveuse_artificielle|couvaison_naturelle|constate|manuel)' => '([^']+)'")) {
      present(regles, m);
    }
    for (final t in _tous(service, r"self::[A-Z_]+ => '([^']+)',")) {
      present(regles, t);
    }
  }, skip: saut);

  test('titres des deux modales et textes d aide du Blade', () {
    for (final t in ['Saisir un relevé', 'Modifier le relevé', 'Valider le relevé']) {
      expect(blade.contains(t), isTrue, reason: t);
      present(ecran, t);
    }
    expect(blade.contains('modal-releve'), isTrue);
    expect(blade.contains('modal-valider-releve'), isTrue);
    for (final t in ['Relisez les valeurs proposées, corrigez-les si besoin, puis validez.', 'Enregistrer fait passer la ligne à « Validé ».']) {
      expect(blade.contains(t), isTrue, reason: t);
      present(ecran, t);
    }
  }, skip: saut);

  test('les cinq cartes du Dashboard Élevage sont celles du Blade', () {
    final cartes = _tous(dashboard, r'<x-kpi-card label="([^"]+)"');
    for (final l in ['Référentiels à valider', 'Fertilité moyenne', 'Éclosion moyenne', 'Incubation observée', 'Délai fournisseur']) {
      expect(cartes, contains(l));
      present(ecranDashboard, l);
    }
    for (final t in ['Aucun lot relevé', 'Éclos ÷ fertiles', 'Propositions en attente de validation']) {
      expect(dashboard.contains(t), isTrue, reason: t);
      present(ecranDashboard, t);
    }
  }, skip: saut);
}
