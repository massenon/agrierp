import 'dart:io';

import 'package:agrierp/features/parametres/corbeille_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket ARC4 — PARITÉ BLADE ↔ DART de la Corbeille (Doctrine, article 5 : la vue Blade est le maître).
///
/// ⚠️⚠️ **LU DANS LE CODE DES DEUX CÔTÉS, RIEN N'EST RECOPIÉ** : `corbeille.blade.php`, `Livewire\Parametres\Corbeille`,
/// `CorbeilleService` (registre, messages, motifs) d'un côté ; `corbeille_repository.dart` et `onglet_corbeille.dart` de l'autre.
/// Un libellé, une colonne, une action, une icône, un message ou un type changé au web fait rougir ce fichier.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/parametres/corbeille.blade.php');
  final composant = File('$dossierLaravel/app/Livewire/Parametres/Corbeille.php');
  final service = File('$dossierLaravel/app/Services/CorbeilleService.php');
  final saut = blade.existsSync() && composant.existsSync() && service.existsSync()
      ? null
      : 'SAUT : dépôt Laravel absent ($dossierLaravel) — rien à comparer';

  final onglet = File('lib/features/parametres/onglet_corbeille.dart').readAsStringSync();
  final depot = File('lib/features/parametres/corbeille_repository.dart').readAsStringSync();
  final php = saut == null ? service.readAsStringSync() : '';
  final vue = saut == null ? blade.readAsStringSync() : '';

  String sansBalises(String s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Ce que Dart écrit entre guillemets simples ou doubles (apostrophes échappées rendues).
  bool dartContient(String texte) {
    final t = texte.replaceAll("'", r"\'");
    return onglet.contains(texte) || onglet.contains(t) || depot.contains(texte) || depot.contains(t);
  }

  test('⚠️ le registre du serveur : mêmes clés, libellés et modules, dans le même ordre', () {
    final registre = php.split('public static function registre()')[1].split('public function elements(')[0];
    final entrees = RegExp(r"^\s*'(\w+)' => \['modele' => [\w\\]+::class, 'libelle' => '([^']+)'", multiLine: true).allMatches(registre).toList();
    final entreesLibelleAvant = RegExp(r"'(\w+)' => \['modele' => [\w\\]+::class, 'libelle' => '([^']+)'(?:, 'titre' => '\w+')?, 'module' => '(\w+)'|'(\w+)' => \['modele' => [\w\\]+::class, 'libelle' => '([^']+)', 'module' => '(\w+)'")
        .allMatches(registre)
        .toList();
    expect(entrees.map((m) => m.group(1)), TypesCorbeille.tous.map((t) => t.cle), reason: 'clés et ordre');
    expect(entrees.map((m) => m.group(2)), TypesCorbeille.tous.map((t) => t.libelle), reason: 'libellés');
    expect(entreesLibelleAvant, isNotEmpty);
    // Les modules : lus dans le bloc de chaque type.
    for (final t in TypesCorbeille.tous) {
      final bloc = registre.split("'${t.cle}' => [")[1].split(RegExp(r"\n            '\w+' => \["))[0];
      expect(bloc, contains("'module' => '${t.module}'"), reason: 'module de ${t.cle}');
    }
  }, skip: saut);

  test('les règles par type : restauration interdite et suppression admise', () {
    final registre = php.split('public static function registre()')[1].split('public function elements(')[0];
    for (final t in TypesCorbeille.tous) {
      final bloc = registre.split("'${t.cle}' => [")[1].split(RegExp(r"\n            '\w+' => \["))[0];
      expect(bloc.contains("'restauration' => 'interdite'"), t.restaurationInterdite, reason: 'restauration de ${t.cle}');
      final admise = bloc.contains("'suppression' => 'si_non_reference'") || bloc.contains("'suppression' => 'sans_reference'");
      expect(admise, t.suppressionAdmise, reason: 'suppression de ${t.cle}');
    }
  }, skip: saut);

  test('⚠️⚠️ les refus et les motifs sont ceux du serveur, MOT POUR MOT', () {
    String constante(String nom) {
      final m = RegExp("public const $nom = '((?:[^'\\\\]|\\\\.)*)';").firstMatch(php)!;
      return m.group(1)!.replaceAll(r"\'", "'");
    }

    expect(CorbeilleRepository.refusDepense, constante('REFUS_DEPENSE'));
    expect(CorbeilleRepository.refusVente, constante('REFUS_VENTE'));
    expect(CorbeilleRepository.refusTransfert, constante('REFUS_TRANSFERT'));
    expect(CorbeilleRepository.messageConfirmation, constante('MESSAGE_CONFIRMATION'));
    expect(CorbeilleRepository.messageIntrouvable, constante('MESSAGE_SUPPRESSION_INTROUVABLE'));
    expect(CorbeilleRepository.motConfirmation, constante('MOT_CONFIRMATION'));

    final bloc = php.split('public const MOTIFS_SUPPRESSION = [')[1].split('];')[0];
    final serveur = {
      for (final m in RegExp(r"'(\w+)' => '((?:[^'\\]|\\.)*)',").allMatches(bloc)) m.group(1)!: m.group(2)!.replaceAll(r"\'", "'"),
    };
    expect(CorbeilleRepository.motifsSuppression, serveur);
    // Un type qui ne se supprime jamais a son motif, un type admis n'en a pas.
    for (final t in TypesCorbeille.tous) {
      expect(serveur.containsKey(t.cle), !t.suppressionAdmise, reason: t.cle);
    }
  }, skip: saut);

  test('⚠️ les libellés du Blade sont dans le Dart : en-tête, cartes, filtres, colonnes, actions, modale, états vides', () {
    for (final texte in [
      'Corbeille',
      "Rien n'est effacé par erreur : tout enregistrement retiré d'un module est archivé ici.",
      "Restaurez-le, ou supprimez-le définitivement quand il n'a aucune conséquence.",
      'Éléments archivés',
      'Restaurables',
      'Suppression définitive possible',
      'Recherche',
      'Rechercher un élément archivé…',
      'Tous les types',
      'Archivé du',
      'Réinitialiser',
      'Restaurer',
      'Supprimer définitivement',
      'Supprimer définitivement ?',
      'Pour confirmer, saisissez le mot SUPPRIMER',
      'La corbeille est vide — aucun élément archivé.',
      'Aucun élément archivé ne correspond à cette recherche.',
      'Non restaurable :',
      'Suppression définitive impossible :',
      'Annuler',
    ]) {
      expect(vue.contains(texte) || sansBalises(vue).contains(texte), isTrue, reason: 'absent du Blade : $texte');
      expect(dartContient(texte), isTrue, reason: 'absent du Dart : $texte');
    }
    // « Au » : étiquette du second champ de date.
    expect(vue, contains('>Au</label>'));
    expect(onglet, contains("etiquette: 'Au'"));
  }, skip: saut);

  test('⚠️ les sept colonnes du Blade, dans l\'ordre (dont « Archivé par », ARC-Q2)', () {
    final blade7 = [for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(vue)) m.group(1)!.trim()];
    expect(blade7, ['Type', 'Élément', 'Détail', 'Module', 'Archivé le', 'Archivé par', 'Actions']);
    final dart = [for (final m in RegExp(r"ColonneTableau\('([^']+)'").allMatches(onglet)) m.group(1)!];
    expect(dart, blade7);
    // L'auteur inconnu s'écrit « — » aux deux endroits.
    expect(vue, contains("\$element['archive_par'] ?? '—'"));
    expect(onglet, contains("l.archivePar ?? '—'"));
  }, skip: saut);

  test('les icônes du Blade sont celles du Dart', () {
    final icones = {for (final m in RegExp(r'material-symbols-outlined[^>]*>([a-z_0-9]+)<').allMatches(vue)) m.group(1)!};
    expect(icones, containsAll(['restore_from_trash', 'restore', 'delete', 'info', 'search', 'block', 'lock', 'warning']));
    // Les icônes des cartes passent par la propriété `icon` du composant `x-kpi-card`.
    for (final m in RegExp(r'<x-kpi-card[^>]*icon="([a-z_0-9]+)"').allMatches(vue)) {
      expect(onglet.contains('SymbolesAgri.${m.group(1)}'), isTrue, reason: 'icône de carte ${m.group(1)}');
    }
    for (final i in icones) {
      if (i == 'chevron_left' || i == 'chevron_right') continue;
      expect(onglet.contains('SymbolesAgri.$i'), isTrue, reason: 'icône $i absente du Dart');
    }
  }, skip: saut);

  test('l\'encadré : les mêmes phrases et les mêmes mots en gras', () {
    final texte = sansBalises(vue.split('bg-info-blue/10')[1].split('</div>')[0]).replaceAll(RegExp(r'^[^L]*Les'), 'Les');
    final gras = [for (final m in RegExp(r'<strong>([^<]+)</strong>').allMatches(vue.split('bg-info-blue/10')[1].split('</div>')[0])) m.group(1)!];
    expect(gras, ['écritures comptables', 'comptes utilisateurs', 'dépense', 'vente annulée', 'transfert annulé']);
    for (final g in gras) {
      expect(onglet, contains("TextSpan(text: '$g', style: gras)"));
    }
    expect(texte, contains('une écriture ne se supprime pas, elle se contre-passe'));
    expect(onglet, contains('une écriture ne se supprime pas, elle se contre-passe'));
    expect(onglet, contains('se consulte ici mais ne se restaure pas : sa contre-passation ou son mouvement ne seraient pas rejoués.'));
  }, skip: saut);

  test('les messages du composant web sont ceux du poste (restauration, suppression, refus)', () {
    final src = composant.readAsStringSync();
    expect(src, contains('CorbeilleService::MESSAGE_SUPPRESSION_INTROUVABLE'));
    expect(php, contains("MESSAGE_RESTAUREE = 'Élément restauré — il réapparaît dans son module.'"));
    expect(php, contains("MESSAGE_SUPPRIMEE = 'Élément supprimé définitivement.'"));
    expect(php, contains("MESSAGE_RESTAURATION_INTROUVABLE = 'Restauration impossible : élément introuvable ou déjà restauré.'"));
    // La pagination : 25 par page, comme `PAR_PAGE`.
    expect(composant.readAsStringSync(), contains('PAR_PAGE = 25'));
    expect(onglet, contains('parPage = 25'));
    expect(vue, contains("{{ \$page->total() }} {{ \$page->total() > 1 ? 'éléments' : 'élément' }} — page"));
    expect(onglet, contains("\"\$total \${total > 1 ? 'éléments' : 'élément'} — page \$page sur \$pages\""));
  }, skip: saut);
}
