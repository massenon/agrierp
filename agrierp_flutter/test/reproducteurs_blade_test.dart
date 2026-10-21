import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_especes_commun.dart';

/// Ticket BS3 — « REGISTRE DES REPRODUCTEURS » DU POSTE ALIGNÉ SUR SON BLADE (article 5 : le Blade est le maître).
///
/// Maître : `resources/views/livewire/elevage/registre-reproducteurs.blade.php` et
/// `app/Livewire/Elevage/RegistreReproducteurs.php`. Les libellés ci-dessous sont LUS DANS LE BLADE : un renommage au web
/// fait rougir ce test, un libellé absent du poste aussi. ⚠️ La comparaison porte sur les LITTÉRAUX du code (jamais sur
/// un commentaire qui citerait le libellé).
void main() {
  final blade = bladeDe('registre-reproducteurs');
  final composant = File('$dossierLaravel/app/Livewire/Elevage/RegistreReproducteurs.php');
  const fichiers = [
    'lib/features/elevage/registre_reproducteurs_screen.dart',
    'lib/features/elevage/reproducteurs_repository.dart',
    'lib/features/elevage/champs_modale_elevage.dart',
  ];
  final saut = blade.existsSync() && composant.existsSync() ? null : 'SAUT : Blade ou composant absent';

  String sansCommentairesBlade(String s) => s.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
  String decoder(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').trim();
  String norme(String s) => decoder(s).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test('⚠️ BS3 — chaque libellé du Blade (titres, boutons, champs, colonnes, modales, info-bulles) est un littéral du poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final litteraux = litterauxDe(fichiers);

    final attendus = <String>{
      for (final m in RegExp(r'<span class="material-symbols-outlined[^"]*">pets</span>([^<]+)</h2>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-xs lg:text-sm text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'</span>(Enregistrer un Reproducteur)\s*</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<option value="[^"]*">([^<]+)</option>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'class="px-md py-sm rounded-lg[^"]*">([^<]+)</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'title="(Consulter la fiche|Modifier|Enregistrer une sortie)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<h3 class="font-bold text-lg text-brand-forest">\{\{ \$editingId \? \x27([^\x27]+)\x27 : \x27([^\x27]+)\x27 \}\}</h3>').allMatches(b)) ...[m.group(1)!, m.group(2)!],
      for (final m in RegExp(r'<h3 class="font-bold text-lg text-brand-forest">([^<{]+)</h3>').allMatches(b)) m.group(1)!,
      'Aucun reproducteur enregistré pour ces critères.',
      // Bandeau d'information : ses morceaux de texte, lus entre les balises.
      for (final m in RegExp(r'<p class="text-on-surface">(.*?)</p>', dotAll: true).allMatches(b))
        ...m.group(1)!.replaceAll(RegExp(r'<a [^>]*>.*?</a>', dotAll: true), '<br>').split(RegExp(r'<[^>]+>')).map((x) => x.trim()).where((x) => x.length > 2),
      'Enregistrer des Sujets',
      // Modale de sortie : le paragraphe d'explication.
      for (final m in RegExp(r'<p class="text-xs text-outline mb-md">(.*?)</p>', dotAll: true).allMatches(b))
        ...m.group(1)!.split(RegExp(r'<[^>]+>')).map((x) => x.trim()).where((x) => x.length > 2),
    }..removeWhere((s) => s.contains('{{') || s.contains('@'));

    expect(attendus.length, greaterThan(45), reason: 'le relevé du Blade doit être complet : ${attendus.length}');
    final manquants = [for (final a in attendus) if (!litteraux.contains(norme(a))) a];
    expect(manquants, isEmpty, reason: 'libellés du Blade absents du poste : $manquants');
  }, skip: saut);

  test('⚠️ BS3 — les huit colonnes du tableau, dans l ordre du Blade, sont celles de l écran', () {
    final colonnesBlade = [
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(sansCommentairesBlade(blade.readAsStringSync()))) decoder(m.group(1)!),
    ];
    final ecran = File('lib/features/elevage/registre_reproducteurs_screen.dart').readAsStringSync();
    final colonnesPoste = [for (final m in RegExp(r"cellule\(\d+, '([^']+)'").allMatches(ecran)) m.group(1)!];

    expect(colonnesBlade, hasLength(8));
    expect(colonnesPoste, colonnesBlade);
  }, skip: saut);

  test('⚠️ BS3 — les champs des deux modales, dans l ordre du Blade, sont ceux de l écran', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final fiche = b.substring(b.indexOf('name="modal-reproducteur"'), b.indexOf('name="modal-sortie-reproducteur"'));
    final sortie = b.substring(b.indexOf('name="modal-sortie-reproducteur"'));
    List<String> etiquettes(String bloc) => [for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(bloc)) decoder(m.group(1)!)];

    final ecran = File('lib/features/elevage/registre_reproducteurs_screen.dart').readAsStringSync();
    final deuxiemeModale = ecran.indexOf('class _ModaleSortie');
    List<String> champsPoste(String bloc) => [for (final m in RegExp(r'''(?:libelle|etiquette): (['"])(.+?)\1,\s*(?:erreur|aide|enfant|valeur)''').allMatches(bloc)) m.group(2)!];

    expect(champsPoste(ecran.substring(ecran.indexOf('class _ModaleReproducteur '), deuxiemeModale)), etiquettes(fiche));
    expect(champsPoste(ecran.substring(deuxiemeModale)), etiquettes(sortie));
  }, skip: saut);

  test('⚠️ BS3 — chaque carte KPI du Blade a son icône et sa couleur au poste', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    final ecran = File('lib/features/elevage/registre_reproducteurs_screen.dart').readAsStringSync();
    const lisere = {
      'emerald': 'couleurLisere: AgriColors.brandEmerald',
      'blue': 'couleurLisere: AgriColors.infoBlue',
      'maize': 'couleurLisere: AgriColors.accentYellow',
      'forest': 'couleurLisere: AgriColors.brandForest',
    };

    final cartes = RegExp(r'<x-kpi-card label="([^"]+)" icon="(\w+)" color="(\w+)"').allMatches(b).toList();
    expect(cartes, hasLength(4));
    for (final m in cartes) {
      final debut = ecran.indexOf("libelle: '${m.group(1)}'");
      expect(debut, greaterThan(-1), reason: m.group(1));
      final bloc = ecran.substring(debut, debut + 400);
      expect(bloc, contains('SymbolesAgri.${m.group(2)}'), reason: 'icône de ${m.group(1)}');
      expect(bloc, contains(lisere[m.group(3)]!), reason: 'couleur de ${m.group(1)}');
    }
  }, skip: saut);

  test('⚠️ BS3 — les toasts et les droits du composant web sont ceux du poste', () {
    final php = composant.readAsStringSync();
    final litteraux = litterauxDe(fichiers);

    // Toasts : littéraux du composant (guillemets simples ou doubles, échappements compris).
    final guillemet = String.fromCharCode(34);
    final apostrophe = String.fromCharCode(39);
    final toast = RegExp('message: (?:$guillemet([^$guillemet]+)$guillemet|$apostrophe((?:[^$apostrophe\\\\]|\\\\.)+)$apostrophe), type: $apostrophe(\\w+)$apostrophe');
    for (final m in toast.allMatches(php)) {
      final message = (m.group(1) ?? m.group(2)!).replaceAll('\\$apostrophe', apostrophe);
      expect(litteraux, contains(norme(message)), reason: 'toast « $message »');
    }
    for (final m in RegExp(r"\$message = '((?:[^'\\]|\\.)+)';").allMatches(php)) {
      final message = m.group(1)!.replaceAll(r"\'", "'");
      expect(litteraux, contains(norme(message)), reason: 'message « $message »');
    }
    // Les cinq méthodes mutantes du web exigent `manage-elevage` en première ligne.
    for (final methode in ['newAnimal', 'editAnimal', 'saveAnimal', 'openExit', 'confirmExit']) {
      expect(
        RegExp('function $methode\\([^)]*\\)[^{]*\\{\\s*\\\$this->authorize\\(\'manage-elevage\'\\)').hasMatch(php),
        isTrue,
        reason: '$methode doit appeler authorize(manage-elevage) en première ligne',
      );
    }
    final ecran = File('lib/features/elevage/registre_reproducteurs_screen.dart').readAsStringSync();
    expect(ecran, contains('widget.peutGerer'), reason: 'le poste applique le même droit');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("peutGerer: PermissionsPoste.peut(_role, 'manage-elevage')"));
  }, skip: saut);

  test('⚠️ BS3 — la règle de Blade : le bouton de sortie n est offert qu à un sujet PRÉSENT, la modification à tous', () {
    final b = sansCommentairesBlade(blade.readAsStringSync());
    expect(b, contains(r'@if($animal->isPresent())'));
    final ecran = File('lib/features/elevage/registre_reproducteurs_screen.dart').readAsStringSync();
    expect(ecran, contains('if (present)'));
  }, skip: saut);

  test('⚠️ BS3 — « Bandes & Sujets » offre le bouton « Registre des Reproducteurs », au web comme au poste', () {
    final bandes = bladeDe('gestion-bandes').readAsStringSync();
    expect(bandes, contains("route('elevage.reproducteurs')"));
    expect(bandes, contains('Registre des Reproducteurs'));
    final ecran = File('lib/features/elevage/gestion_bandes_screen.dart').readAsStringSync();
    expect(ecran, contains("'Registre des Reproducteurs'"));
    expect(File('lib/main.dart').readAsStringSync(), contains('EcranPoste.registreReproducteurs'));
  }, skip: saut);
}
