import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_especes_commun.dart';

/// Ticket BS2 — « ENREGISTRER DES SUJETS » DU POSTE ALIGNÉ SUR SON BLADE (article 5 : le Blade est le maître).
///
/// Maître : `resources/views/livewire/elevage/enregistrer-sujets.blade.php` et `app/Livewire/Elevage/EnregistrerSujets.php`.
/// Les libellés sont LUS DANS LE BLADE ; la comparaison porte sur les LITTÉRAUX du code (jamais sur un commentaire).
void main() {
  final blade = bladeDe('enregistrer-sujets');
  final composant = File('$dossierLaravel/app/Livewire/Elevage/EnregistrerSujets.php');
  const fichiers = [
    'lib/features/elevage/enregistrer_sujets_screen.dart',
    'lib/features/elevage/sujets_entrees_repository.dart',
    'lib/features/elevage/champs_modale_elevage.dart',
  ];
  final saut = blade.existsSync() && composant.existsSync() ? null : 'SAUT : Blade ou composant absent';

  String sansCommentairesBlade(String s) => s.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
  String decoder(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').trim();
  String norme(String s) => decoder(s).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test('⚠️ BS2 — chaque libellé du Blade (titre, boutons, KPI, colonnes, modales, vide) est un littéral du poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final litteraux = litterauxDe(fichiers);

    final attendus = <String>{
      for (final m in RegExp(r'<span class="material-symbols-outlined[^"]*">pets</span>([^<]+)</h2>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-xs lg:text-sm text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'</span>(Nouveau Sujet)\s*</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<option value="[^"]*">([^<]+)</option>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<h3 class="font-bold text-lg text-brand-forest">([^<]+)</h3>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-\[10px\] text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'class="px-md py-sm rounded-lg[^"]*">([^<]+)</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-sm font-semibold text-on-surface">([^<]+)</p>').allMatches(b)) m.group(1)!,
      '+ Nouveau Sujet',
      "Choisir d'abord une espèce",
      for (final m in RegExp(r'italic">([^<]+)</span>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'title="(Modifier|Archiver)"').allMatches(b)) m.group(1)!,
    }..removeWhere((s) => s.contains('{{') || s.contains('@'));

    expect(attendus.length, greaterThan(30), reason: 'le relevé du Blade doit être complet : ${attendus.length}');
    final manquants = [for (final a in attendus) if (!litteraux.contains(norme(a))) a];
    expect(manquants, isEmpty, reason: 'libellés du Blade absents du poste : $manquants');
  }, skip: saut);

  test('⚠️ BS2 — les colonnes du journal, dans l ordre du Blade, sont celles de l écran', () {
    final colonnesBlade = [
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(sansCommentairesBlade(blade.readAsStringSync()))) decoder(m.group(1)!),
    ];
    final ecran = File('lib/features/elevage/enregistrer_sujets_screen.dart').readAsStringSync();
    final colonnesPoste = [for (final m in RegExp(r"cellule\(\d+, '([^']+)'").allMatches(ecran)) m.group(1)!];

    expect(colonnesBlade, ['Date', 'Bande', 'Espèce', 'Origine', 'Quantité', 'Actions']);
    expect(colonnesPoste, colonnesBlade);
  }, skip: saut);

  test('⚠️ BS2 — les champs de « Nouveau Sujet » et de « Modifier le Sujet », dans l ordre du Blade, sont ceux de la modale', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final creation = b.substring(b.indexOf('name="modal-create-sujet"'), b.indexOf('name="modal-edit-sujet"'));
    final edition = b.substring(b.indexOf('name="modal-edit-sujet"'));
    List<String> etiquettes(String bloc) => [for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(bloc)) decoder(m.group(1)!)];

    final ecran = File('lib/features/elevage/enregistrer_sujets_screen.dart').readAsStringSync();
    final champs = [for (final m in RegExp(r'''(?:libelle|etiquette): (['"])(.+?)\1,\s*(?:erreur|aide|enfant|valeur)''').allMatches(ecran)) m.group(2)!];

    // Une seule modale au poste, deux modes : Espèce et « Bande / Lot de destination » à la création seulement,
    // « Bande / Lot » (non modifiable) en modification seulement, puis Origine, Quantité, Date.
    expect([for (final c in champs) if (c != 'Bande / Lot') c], etiquettes(creation));
    expect([for (final c in champs) if (c != 'Espèce *' && c != 'Bande / Lot de destination *') c], etiquettes(edition));
  }, skip: saut);

  test('⚠️ BS2 — les trois cartes KPI du Blade : libellé, icône et couleur au poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final ecran = File('lib/features/elevage/enregistrer_sujets_screen.dart').readAsStringSync();

    final cartes = RegExp(r'<x-kpi-card label="([^"]+)" icon="(\w+)" color="(\w+)"').allMatches(b).toList();
    expect(cartes, hasLength(3));
    for (final m in cartes) {
      expect(m.group(3), 'emerald');
      final debut = ecran.contains("libelle: '${m.group(1)}'") ? ecran.indexOf("libelle: '${m.group(1)}'") : ecran.indexOf("etiquette: '${m.group(1)}'");
      expect(debut, greaterThan(-1), reason: m.group(1));
      final bloc = ecran.substring(debut, debut + 350);
      expect(bloc, contains('SymbolesAgri.${m.group(2)}'), reason: 'icône de ${m.group(1)}');
      expect(bloc, contains('couleurLisere: AgriColors.brandEmerald'), reason: 'couleur de ${m.group(1)}');
    }
  }, skip: saut);

  test('⚠️ BS2 — toasts, droits et origines du composant web sont ceux du poste', () {
    final php = composant.readAsStringSync();
    final litteraux = litterauxDe(fichiers);

    for (final m in RegExp(r"message: '([^']+)', type: '(\w+)'").allMatches(php)) {
      expect(litteraux, contains(norme(m.group(1)!)), reason: 'toast « ${m.group(1)} »');
    }
    for (final methode in ['newEntry', 'saveEntry', 'editEntry', 'updateEntry']) {
      expect(
        RegExp('function $methode\\([^)]*\\)[^{]*\\{\\s*\\\$this->authorize\\(\'manage-elevage\'\\)').hasMatch(php),
        isTrue,
        reason: '$methode doit appeler authorize(manage-elevage) en première ligne',
      );
    }
    expect(
      RegExp('function archiveEntry\\([^)]*\\)[^{]*\\{\\s*\\\$this->authorize\\(\'archive-elevage\'\\)').hasMatch(php),
      isTrue,
      reason: 'archiveEntry exige archive-elevage',
    );

    final action = File('$dossierLaravel/app/Actions/SaisieSujetAction.php').readAsStringSync();
    final colonnes = RegExp(r"public const ORIGINES = \[(.*?)\];", dotAll: true).firstMatch(action)!.group(1)!;
    expect(
      {for (final m in RegExp(r"'(\w+)' => '(\w+)'").allMatches(colonnes)) m.group(1)!: m.group(2)!},
      {'Naissance': 'ne', 'Achat': 'achat', 'Don': 'don'},
      reason: 'les origines du journal et leur colonne',
    );

    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("peutGerer: PermissionsPoste.peut(_role, 'manage-elevage')"));
    expect(main, contains("peutArchiver: PermissionsPoste.peut(_role, 'archive-elevage')"));
  }, skip: saut);

  test('⚠️ BS2 — le message « entrée introuvable » et le refus d effectif négatif sont ceux de SaisieSujetAction', () {
    final action = File('$dossierLaravel/app/Actions/SaisieSujetAction.php').readAsStringSync();
    final litteraux = litterauxDe(['lib/features/elevage/sujets_entrees_repository.dart']);

    final introuvable = RegExp(r'MESSAGE_INTROUVABLE = "([^"]+)"').firstMatch(action)!.group(1)!;
    expect(litteraux, contains(norme(introuvable)));
    expect(litteraux, contains(norme("Saisie refusée : l'effectif de la bande ")));
    expect(action, contains("Saisie refusée : l'effectif de la bande %s deviendrait négatif le %s (%d)."));
    expect(litteraux, contains(norme(' deviendrait négatif le ')));
  }, skip: saut);
}
