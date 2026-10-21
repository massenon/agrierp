import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_especes_commun.dart';

/// Ticket BS1 — « BANDES & SUJETS » DU POSTE ALIGNÉ SUR SON BLADE (article 5 : le Blade est le maître).
///
/// Maître : `resources/views/livewire/elevage/gestion-bandes.blade.php` et `app/Livewire/Elevage/GestionBandes.php`.
/// Les libellés ci-dessous sont LUS DANS LE BLADE : un renommage au web fait rougir ce test, un libellé absent du poste
/// aussi. ⚠️ Comme `fidelite_libelles_test.dart`, la comparaison porte sur les LITTÉRAUX du code (jamais sur un
/// commentaire qui citerait le libellé).
void main() {
  final blade = bladeDe('gestion-bandes');
  final composant = File('$dossierLaravel/app/Livewire/Elevage/GestionBandes.php');
  const fichiers = [
    'lib/features/elevage/gestion_bandes_screen.dart',
    'lib/features/elevage/bandes_repository.dart',
    'lib/features/elevage/champs_modale_elevage.dart',
  ];
  final saut = blade.existsSync() && composant.existsSync() ? null : 'SAUT : Blade ou composant absent';

  String sansCommentairesBlade(String s) => s.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
  String decoder(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').trim();

  /// Libellé comparable : minuscules, espaces simples (les littéraux sont lus de la même façon).
  String norme(String s) => decoder(s).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test('⚠️ BS1 — chaque libellé du Blade (titres, boutons, champs, aides, colonnes, tiroir) est un littéral du poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final litteraux = litterauxDe(fichiers);

    final attendus = <String>{
      // En-tête et boutons.
      for (final m in RegExp(r'<span class="material-symbols-outlined[^"]*">layers</span>([^<]+)</h2>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-xs text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'</span>(Nouvelle Bande|Exporter PDF|Enregistrer des Sujets)\s*</(?:button|a)>').allMatches(b)) m.group(1)!,
      // Cartes KPI : libellé et légende.
      for (final m in RegExp(r'<x-kpi-card label="([^"]+)"[^>]*caption="([^"]+)"').allMatches(b)) ...[m.group(1)!, m.group(2)!],
      // Recherche, filtre, colonnes.
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<option value="[^"]*">([^<]+)</option>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(b)) m.group(1)!,
      // Modales : titres, étiquettes, aides, pieds.
      for (final m in RegExp(r'<h3 class="font-bold text-lg text-brand-forest">([^<]+)</h3>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-\[10px\] text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-\[10px\] text-outline bg-surface-zebra rounded-lg p-sm">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'class="px-md py-sm rounded-lg[^"]*">([^<]+)</button>').allMatches(b)) m.group(1)!,
      // Tableau : vide, lecture seule, infobulles d'actions.
      'Aucune bande pour le moment. Cliquez sur « Nouvelle Bande » pour commencer.',
      for (final m in RegExp(r'italic">([^<]+)</span>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'title="(Modifier|Archiver|Restaurer)"').allMatches(b)) m.group(1)!,
      // BS-Q7 : l'état vide du filtre des archivées.
      'Aucune bande archivée.',
      // Tiroir.
      for (final m in RegExp(r'<span class="text-outline block">([^<]+)</span>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-xs font-bold text-brand-forest uppercase mb-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      "Délai d'attente en cours",
      "Aucun délai d'attente en cours : vente autorisée.",
      'Provende servie à cette bande',
      'Derniers soins',
    }..removeWhere((s) => s.contains('{{') || s.contains('@'));

    expect(attendus.length, greaterThan(50), reason: 'le relevé du Blade doit être complet : ${attendus.length}');
    final manquants = [for (final a in attendus) if (!litteraux.contains(norme(a).replaceAll(' *', ' *'))) a];
    expect(manquants, isEmpty, reason: 'libellés du Blade absents du poste : $manquants');
  }, skip: saut);

  test('⚠️ BS1 — les neuf colonnes du tableau, dans l ordre du Blade, sont celles de l écran', () {
    final colonnesBlade = [
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(sansCommentairesBlade(blade.readAsStringSync()))) decoder(m.group(1)!),
    ];
    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    final colonnesPoste = [for (final m in RegExp(r"cellule\(\d+, '([^']+)'").allMatches(ecran)) m.group(1)!];

    expect(colonnesBlade, hasLength(9));
    expect(colonnesPoste, colonnesBlade);
  }, skip: saut);

  test('⚠️ BS1 — les champs de « Nouvelle Bande » et de « Modifier la Bande », dans l ordre du Blade, sont ceux des modales', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final creation = b.substring(b.indexOf('name="modal-create-bande"'), b.indexOf('name="modal-edit-bande"'));
    final edition = b.substring(b.indexOf('name="modal-edit-bande"'), b.indexOf(r'@if($this->viewingLot)'));
    List<String> etiquettes(String bloc) => [for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(bloc)) decoder(m.group(1)!)];

    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    final deuxModales = ecran.indexOf('class _ModaleModifierBande');
    List<String> champsPoste(String bloc) => [for (final m in RegExp(r'''(?:libelle|etiquette): (['"])(.+?)\1,\s*(?:erreur|aide|enfant|valeur)''').allMatches(bloc)) m.group(2)!];

    expect(champsPoste(ecran.substring(0, deuxModales).substring(ecran.indexOf('class _ModaleNouvelleBande'))), etiquettes(creation));
    expect(champsPoste(ecran.substring(deuxModales, ecran.indexOf('// Tiroir de détail'))), etiquettes(edition));
  }, skip: saut);

  test('⚠️ BS1 — chaque carte KPI du Blade a son icône et sa couleur au poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    const lisere = {
      'emerald': 'couleurLisere: AgriColors.brandEmerald',
      'blue': 'couleurLisere: AgriColors.infoBlue',
      'maize': 'couleurLisere: AgriColors.accentYellow',
      'red': 'couleurLisere: AgriColors.errorRed',
    };

    final cartes = RegExp(r'<x-kpi-card label="([^"]+)" icon="(\w+)" color="(\w+)"').allMatches(b).toList();
    expect(cartes, hasLength(4));
    for (final m in cartes) {
      final debut = ecran.contains("libelle: '${m.group(1)}'") ? ecran.indexOf("libelle: '${m.group(1)}'") : ecran.indexOf("etiquette: '${m.group(1)}'");
      expect(debut, greaterThan(-1), reason: m.group(1));
      final bloc = ecran.substring(debut, debut + 400);
      expect(bloc, contains('SymbolesAgri.${m.group(2)}'), reason: 'icône de ${m.group(1)}');
      expect(bloc, contains(lisere[m.group(3)]!), reason: 'couleur de ${m.group(1)}');
    }
  }, skip: saut);

  test('⚠️ BS1 — les toasts et les droits du composant web sont ceux du poste', () {
    final php = composant.readAsStringSync();
    final litteraux = litterauxDe(fichiers);

    for (final m in RegExp(r"message: '([^']+)', type: '(\w+)'").allMatches(php)) {
      expect(litteraux, contains(norme(m.group(1)!)), reason: 'toast « ${m.group(1)} »');
    }
    // Les cinq méthodes mutantes du web exigent `manage-elevage` en première ligne.
    // BS-Q7 : `restoreLot` (Restaurer) exige le même droit.
    for (final methode in ['newLot', 'saveLot', 'editLot', 'updateLot', 'archiveLot', 'restoreLot']) {
      expect(
        RegExp('function $methode\\([^)]*\\)[^{]*\\{\\s*\\\$this->authorize\\(\'manage-elevage\'\\)').hasMatch(php),
        isTrue,
        reason: '$methode doit appeler authorize(manage-elevage) en première ligne',
      );
    }
    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    expect(ecran, contains('widget.peutGerer'), reason: 'le poste applique le même droit');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("peutGerer: PermissionsPoste.peut(_role, 'manage-elevage')"));
  }, skip: saut);

  test('⚠️ BS1 — le stade proposé selon l espèce : les libellés de LivestockLot::stadesPourEspece', () {
    final modele = File('$dossierLaravel/app/Models/LivestockLot.php').readAsStringSync();
    final litteraux = litterauxDe(['lib/features/elevage/bandes_repository.dart']);

    for (final m in RegExp(r"'(reproduction|croissance|ponte|engraissement)' => '([^']+)'").allMatches(modele)) {
      expect(litteraux, contains('${m.group(1)}'), reason: m.group(1));
      expect(litteraux, contains(norme(m.group(2)!)), reason: 'libellé de stade « ${m.group(2)} »');
    }
  }, skip: saut);

  test('⚠️ BS-Q3 / BS-Q4 / BS-Q7 — les messages et l info-bulle de SaisieBandeAction (constantes, gabarits) sont des littéraux du poste', () {
    final action = File('$dossierLaravel/app/Actions/SaisieBandeAction.php');
    if (!action.existsSync()) return;
    final php = action.readAsStringSync();
    final litteraux = litterauxDe(['lib/features/elevage/bandes_repository.dart']);

    final constantes = [
      for (final m in RegExp(r'''const (?:MESSAGE_EFFECTIF_PAR_LES_FICHES|INFOBULLE_EFFECTIF_PAR_LES_FICHES) = (?:"([^"]+)"|'([^']+)');''').allMatches(php))
        m.group(1) ?? m.group(2)!,
    ];
    expect(constantes, hasLength(2));
    for (final c in constantes) {
      expect(litteraux, contains(norme(c)), reason: 'constante « $c »');
    }
    // Les deux gabarits (le nombre est inséré) : leurs morceaux fixes sont au poste.
    for (final morceau in [
      'Cette bande compte encore ',
      ' : archivez-la après avoir sorti ou transféré les sujets restants.',
      'Le code « ',
      ' » est déjà utilisé par une bande en cours : cette bande ne peut pas être restaurée.',
    ]) {
      expect(php, contains(morceau), reason: 'gabarit du web « $morceau »');
      expect(litteraux, contains(norme(morceau)), reason: 'gabarit du poste « $morceau »');
    }
  }, skip: saut);

  test('⚠️ BS-Q4 — le Blade grise le champ Effectif Actuel (disabled, info-bulle) quand la bande a des fiches, et le poste le dit', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    expect(b, contains('@if(\$effectifVerrouille)'));
    expect(b, contains('data-effectif-verrouille'));
    expect(b, contains('INFOBULLE_EFFECTIF_PAR_LES_FICHES'));
    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    expect(ecran, contains('BandesRepository.infobulleEffectifParLesFiches'));
  }, skip: saut);
}
