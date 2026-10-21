import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/ventes/devis_onglet.dart';
import 'package:agrierp/features/ventes/devis_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_especes_commun.dart';

/// Ticket DEV — GARDE-FOU : « DEVIS & PROFORMA » DU POSTE CONFRONTÉ À SON BLADE MAÎTRE (article 5 de la doctrine).
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE.** Titre, sous-titre, boutons, cartes, filtres, colonnes, statuts, icônes d'action, modale,
/// champs, messages de validation, toasts, règles de statut et colonnes du PDF sont LUS dans `devis.blade.php`,
/// `Devis.php`, `SaisieDevisAction.php`, `Quote.php`, `ventes-devis-hub.blade.php`, `exports/devis.blade.php` et
/// `lang/fr/validation.php`, jamais recopiés ici : une retouche du web fait rougir le poste au lieu de diverger en
/// silence. Comme `fidelite_libelles_test.dart`, la comparaison porte sur les LITTÉRAUX du code (jamais sur un commentaire
/// qui citerait le libellé).
String? _lire(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lire('resources/views/livewire/ventes/devis.blade.php');
final String? _composant = _lire('app/Livewire/Ventes/Devis.php');
final String? _action = _lire('app/Actions/SaisieDevisAction.php');
final String? _modele = _lire('app/Models/Quote.php');
final String? _hub = _lire('resources/views/livewire/ventes/ventes-devis-hub.blade.php');
final String? _export = _lire('resources/views/exports/devis.blade.php');
final String? _validation = _lire('lang/fr/validation.php');

const _fichiers = [
  'lib/features/ventes/devis_onglet.dart',
  'lib/features/ventes/devis_repository.dart',
  'lib/features/ventes/ventes_devis_screen.dart',
];

String _norme(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

String _sansCommentairesBlade(String s) => s.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');

void main() {
  final absent = _blade == null ||
          _composant == null ||
          _action == null ||
          _modele == null ||
          _hub == null ||
          _export == null ||
          _validation == null
      ? 'SAUT : dépôt Laravel absent ($dossierLaravel) — comparaison au web impossible'
      : null;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('⚠️⚠️ chaque libellé du Blade (titre, boutons, cartes, filtres, colonnes, modale, champs, aides, état vide) est un littéral du poste', () {
    final b = _sansCommentairesBlade(_blade!);
    final litteraux = litterauxDe(_fichiers);

    final attendus = <String>{
      for (final m in RegExp(r'</span>([^<]+)\n?\s*</h2>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<p class="text-xs text-outline mt-xs">([^<]+)</p>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'</span>(Exporter|Nouveau Devis)\s*</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<option value="[^"]*">([^<]+)</option>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'title="([^"]+)"').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'class="px-md py-sm rounded-lg[^"]*">([^<]+)</button>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r"'(Modifier le Devis|Nouveau Devis)'").allMatches(b)) m.group(1)!,
      for (final m in RegExp(r'text-center text-outline">([^<]+)</td>').allMatches(b)) m.group(1)!,
      for (final m in RegExp(r"\$statusLabels = \[(.*?)\];", dotAll: true).allMatches(b))
        for (final e in RegExp(r"=> '([^']+)'").allMatches(m.group(1)!)) e.group(1)!,
    }..removeWhere((s) => s.contains('{{') || s.contains('@'));

    expect(attendus.length, greaterThan(35), reason: 'le relevé du Blade doit être complet : ${attendus.length}');
    // Exemptions, chacune justifiée : l'accordéon des cartes n'existe qu'en dessous de `md` (`md:hidden`), le poste est un
    // écran de bureau dont les cartes sont toujours déployées ; les deux taux du `<select>` sont rendus depuis
    // `DevisRepository.tauxTva` (vérifié par le test de la modale).
    const exemptions = {'Indicateurs de performance', '0 %', '18 %'};
    final manquants = [for (final a in attendus) if (!exemptions.contains(a) && !litteraux.contains(_norme(a))) a];
    expect(manquants, isEmpty, reason: 'libellés du Blade absents du poste : $manquants');
  }, skip: absent);

  test('⚠️ les sept colonnes du tableau, dans l ordre du Blade, sont celles de l écran', () {
    final colonnesBlade = [
      for (final m in RegExp(r'<th [^>]*>([^<]+)</th>').allMatches(_sansCommentairesBlade(_blade!))) m.group(1)!.trim(),
    ];
    final ecran = File('lib/features/ventes/devis_onglet.dart').readAsStringSync();
    final colonnesPoste = [
      for (final m in RegExp(r"Text\(\s*'([^']+)',[^)]*style: _enteteColonne").allMatches(ecran)) m.group(1)!,
    ];

    expect(colonnesBlade, hasLength(7));
    expect(colonnesPoste, [for (final c in colonnesBlade) c.toUpperCase()]);
  }, skip: absent);

  test('⚠️ les statuts, leurs libellés et l ordre du filtre sont ceux du Blade, du modèle et du composant', () {
    final b = _blade!;
    final libellesBlade = {
      for (final m in RegExp(r"'(\w+)' => '([^']+)'").allMatches(RegExp(r"\$statusLabels = \[(.*?)\];", dotAll: true).firstMatch(b)!.group(1)!))
        m.group(1)!: m.group(2)!,
    };
    final libellesModele = {
      for (final m in RegExp(r"'(\w+)' => '([^']+)'").allMatches(RegExp(r'STATUTS = \[(.*?)\];', dotAll: true).firstMatch(_modele!)!.group(1)!))
        m.group(1)!: m.group(2)!,
    };
    final filtre = [
      for (final m in RegExp(r'<option value="(\w+)">([^<]+)</option>').allMatches(b.substring(b.indexOf('statusFilter'), b.indexOf('clientFilter'))))
        (m.group(1)!, m.group(2)!),
    ];

    expect(libellesBlade, hasLength(5));
    expect(DevisRepository.statuts, libellesBlade);
    expect(DevisRepository.statuts, libellesModele);
    // L'ordre : « Statut : Tous » puis les cinq statuts (clés et libellés), comme le `<select>`.
    expect(filtre, [for (final e in libellesBlade.entries) (e.key, e.value)]);
  }, skip: absent);

  test('⚠️ le cycle de vie du poste est celui de `SaisieDevisAction` (pas autorisés et messages)', () {
    final bloc = RegExp(r'TRANSITIONS = \[(.*?)\];', dotAll: true).firstMatch(_action!)!.group(1)!;
    final web = {
      for (final m in RegExp(r"'(\w+)' => \[([^\]]*)\]").allMatches(bloc))
        m.group(1)!: [for (final s in RegExp(r"'(\w+)'").allMatches(m.group(2)!)) s.group(1)!],
    };
    expect(DevisRepository.transitions, web);

    String constante(String nom) => RegExp("$nom = '((?:[^'\\\\]|\\\\.)*)';").firstMatch(_action!)!.group(1)!.replaceAll(r"\'", "'");
    expect(DevisRepository.messageArchive, constante('MESSAGE_ARCHIVE'));
    expect(DevisRepository.messageFacture, constante('MESSAGE_FACTURE'));
    // `Changement de statut interdit : un devis « X » ne peut pas passer à « Y ».`
    expect(
      DevisRepository.messageStatutInterdit('accepte', 'brouillon'),
      'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Brouillon ».',
    );
    expect(_action, contains("'Changement de statut interdit : un devis « '"));
    expect(_action, contains("' » ne peut pas passer à « '"));
  }, skip: absent);

  test('⚠️ les toasts sont ceux du composant web, mot pour mot', () {
    // `message: '…'` des `dispatch('toast')`, et les messages passés à `changerStatut($id, $statut, '…', $type)`.
    final messages = {
      for (final m in RegExp(r'''message: (['"])(.*?)\1''').allMatches(_composant!)) m.group(2)!,
      for (final m in RegExp(r"'(Devis marqué comme [^']*\.)'").allMatches(_composant!)) m.group(1)!,
    }.toList();
    expect(messages, containsAll(['Devis marqué comme envoyé.', 'Devis marqué comme accepté.', 'Devis marqué comme refusé.']));
    final poste = litterauxDe(_fichiers);
    for (final message in messages) {
      expect(poste, contains(_norme(message.replaceAll(r"\'", "'"))), reason: 'message du web : « $message »');
    }
    // Les trois messages de succès de `saveQuote()` / `archiveQuote()`.
    final composant = _composant!;
    expect(composant, contains("'Devis créé avec succès.'"));
    expect(composant, contains("'Devis modifié avec succès.'"));
    expect(composant, contains("'Devis archivé avec succès.'"));
    expect(DevisRepository.toastCree, 'Devis créé avec succès.');
    expect(DevisRepository.toastModifie, 'Devis modifié avec succès.');
    expect(DevisRepository.toastArchive, 'Devis archivé avec succès.');
    expect(DevisRepository.toastConversion, contains('La conversion en facture réelle arrive avec le module Facturation'));
  }, skip: absent);

  test('⚠️⚠️ les règles et les messages de validation sont ceux du web (`saveQuote()` et `lang/fr/validation.php`)', () {
    final bloc = RegExp(r'\$this->validate\(\[(.*?)\]\);', dotAll: true).firstMatch(_composant!)!.group(1)!;
    final regles = {
      for (final m in RegExp(r"'(\w+)' => \[([^\]]*)\]").allMatches(bloc))
        m.group(1)!: [for (final r in RegExp(r"'([^']+)'").allMatches(m.group(2)!)) r.group(1)!],
    };
    // Les règles que `DevisRepository.valider` applique : un changement du web les fait rougir ici.
    expect(regles, {
      'customerId': ['required', 'exists:customers,id'],
      'articlesDescription': ['required', 'string', 'max:2000'],
      'amount': ['required', 'numeric', 'min:0'],
      'tvaRate': ['required', 'numeric', 'min:0', 'max:100'],
      'validityDays': ['required', 'integer', 'min:1'],
      'quoteDate': ['required', 'date'],
    });

    // Les messages : `lang/fr/validation.php`, avec le nom de champ de son tableau `attributes`.
    final v = _validation!;
    String modele(String cle) => RegExp("^    '$cle' => '((?:[^'\\\\]|\\\\.)*)',", multiLine: true).firstMatch(v)!.group(1)!.replaceAll(r"\'", "'");
    String sousCle(String cle, String type) {
      final bloc = RegExp("^    '$cle' => \\[(.*?)\\],", multiLine: true, dotAll: true).firstMatch(v)!.group(1)!;
      return RegExp("'$type' => '((?:[^'\\\\]|\\\\.)*)'").firstMatch(bloc)!.group(1)!.replaceAll(r"\'", "'");
    }

    String attribut(String champ) => RegExp("^        '$champ' => '((?:[^'\\\\]|\\\\.)*)',", multiLine: true).firstMatch(v)!.group(1)!.replaceAll(r"\'", "'");
    String rendre(String texte, String champ, {String? min, String? max}) =>
        texte.replaceAll(':attribute', attribut(champ)).replaceAll(':min', min ?? '').replaceAll(':max', max ?? '');

    final erreurs = DevisRepository.valider(
      clientId: null, articles: '', montant: '', tva: '', validite: '', date: null,
    );
    expect(erreurs['client'], rendre(modele('required'), 'customerId'));
    expect(erreurs['articles'], rendre(modele('required'), 'articlesDescription'));
    expect(erreurs['montant'], rendre(modele('required'), 'amount'));
    expect(erreurs['tva'], rendre(modele('required'), 'tvaRate'));
    expect(erreurs['validite'], rendre(modele('required'), 'validityDays'));
    expect(erreurs['date'], rendre(modele('required'), 'quoteDate'));

    Map<String, String> avec({String clientId = 'c', String articles = 'x', String montant = '1', String tva = '0', String validite = '1', bool clientConnu = true}) =>
        DevisRepository.valider(
          clientId: clientId, articles: articles, montant: montant, tva: tva, validite: validite, date: DateTime(2026), clientConnu: clientConnu,
        );
    expect(avec(clientConnu: false)['client'], rendre(modele('exists'), 'customerId'));
    expect(avec(articles: 'x' * 2001)['articles'], rendre(sousCle('max', 'string'), 'articlesDescription', max: '2000'));
    expect(avec(montant: 'abc')['montant'], rendre(modele('numeric'), 'amount'));
    expect(avec(montant: '-1')['montant'], rendre(sousCle('min', 'numeric'), 'amount', min: '0'));
    expect(avec(tva: '101')['tva'], rendre(sousCle('max', 'numeric'), 'tvaRate', max: '100'));
    expect(avec(validite: '1.5')['validite'], rendre(modele('integer'), 'validityDays'));
    expect(avec(validite: '0')['validite'], rendre(sousCle('min', 'numeric'), 'validityDays', min: '1'));
  }, skip: absent);

  test('⚠️ les icônes d action : même infobulle, même icône, mêmes conditions de statut que le Blade', () {
    final b = _sansCommentairesBlade(_blade!);
    final ecran = File('lib/features/ventes/devis_onglet.dart').readAsStringSync();

    final actions = [
      for (final m in RegExp(
        r'''<button type="button" (?:wire:click|x-on:click)="[^"]*"[^>]*title="([^"]+)"><span class="material-symbols-outlined[^"]*">(\w+)</span>''',
      ).allMatches(b))
        (m.group(1)!, m.group(2)!),
    ];
    expect(actions.map((a) => a.$1), [
      'Marquer comme envoyé', 'Marquer comme accepté', 'Marquer comme refusé', 'Convertir en Facture', 'Modifier', 'Archiver',
    ]);
    for (final (titre, icone) in actions) {
      expect(
        RegExp("infobulle: '$titre',\\s*icone: SymbolesAgri\\.$icone,").hasMatch(ecran),
        isTrue,
        reason: '« $titre » doit porter l icône « $icone » comme le Blade',
      );
    }

    // Les conditions : `@if($quote->status === '…')` autour de chaque action, comme le poste (`d.status == '…'`).
    expect(b, contains("@if(\$quote->status === 'brouillon')"));
    expect(b, contains("@if(\$quote->status === 'envoye')"));
    expect(b, contains("@if(\$quote->status === 'accepte')"));
    expect(ecran, contains("d.status == 'brouillon'"));
    expect(ecran, contains("d.status == 'envoye'"));
    expect(ecran, contains("d.status == 'accepte'"));
  }, skip: absent);

  test('⚠️ le hub place « Devis Prestations » en deuxième onglet, avec son icône', () {
    final onglets = [
      for (final m in RegExp(r"\['key' => '(\w+)', 'label' => '([^']+)', 'icon' => '(\w+)'\]").allMatches(_hub!)) (m.group(2)!, m.group(3)!),
    ];
    expect(onglets[1], ('Devis Prestations', 'description'));
    expect(_hub, contains('<livewire:ventes.devis />'));

    final poste = File('lib/features/ventes/ventes_devis_screen.dart').readAsStringSync();
    expect(poste, contains("('Devis Prestations', SymbolesAgri.description)"));
    expect(poste, contains("'Devis Prestations' => DevisOnglet("));
    expect(poste, isNot(contains("'devis-non-embarque'")), reason: 'l onglet n est plus « non embarqué »');
  }, skip: absent);

  test('⚠️ les droits : manage-ventes pour écrire, export-ventes pour exporter, comme le composant et le câblage du poste', () {
    final composant = _composant!;
    for (final methode in ['saveQuote', 'markAsSent', 'markAsAccepted', 'markAsRefused', 'archiveQuote']) {
      final corps = RegExp('public function $methode\\([^)]*\\): void\\s*\\{\\s*([^\\n]*)').firstMatch(composant)!.group(1)!;
      expect(corps, contains("authorize('manage-ventes')"), reason: '$methode : première ligne');
    }
    expect(composant, contains("authorize('export-ventes')"));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("peutGererDevis: PermissionsPoste.peut(_role, 'manage-ventes')"));
    expect(main, contains("peutExporterDevis: PermissionsPoste.peut(_role, 'export-ventes')"));
  }, skip: absent);

  test('⚠️ le PDF « Exporter » : mêmes colonnes, titre, sous-titre, nom de fichier et état vide que `exports/devis.blade.php`', () {
    final colonnes = [for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(_export!)) m.group(1)!];
    final doc = DevisRepository.documentPdf(const [], DateTime(2026, 10, 21));

    expect(colonnes, doc.entetes);
    expect(_export, contains('Aucun devis ne correspond aux filtres actifs.'));
    expect((doc.lignes.single as dynamic).cellules.first, 'Aucun devis ne correspond aux filtres actifs.');
    expect(_composant, contains("'Devis & Proforma',"));
    expect(_composant, contains("'État au '.now()->format('d/m/Y')"));
    expect(doc.titre, 'Devis & Proforma');
    expect(doc.sousTitre, 'État au 21/10/2026');
    expect(_composant, contains("'devis-'.now()->format('Y-m-d').'.pdf'"));
    expect(doc.fichier, 'devis-{jour}.pdf');
  }, skip: absent);

  test('⚠️ la modale : champs, valeurs par défaut (TVA 18 %, validité 15 j) et taux du `<select>` « TVA (%) »', () {
    final b = _blade!;
    final taux = [for (final m in RegExp(r'<option value="(\d+)">\d+ %</option>').allMatches(b)) int.parse(m.group(1)!)];
    expect(taux, DevisRepository.tauxTva);
    expect(_composant, contains('public float \$tvaRate = 18;'));
    expect(_composant, contains('public int \$validityDays = 15;'));
    expect(DevisRepository.tvaParDefaut, 18);
    expect(DevisRepository.validiteParDefaut, 15);
    expect(b, contains('max-width="md"'));
    for (final champ in ['customerId', 'articlesDescription', 'amount', 'tvaRate', 'validityDays', 'quoteDate', 'note']) {
      expect(b, contains('wire:model="$champ"'), reason: champ);
    }
  }, skip: absent);

  test('⚠️ les quatre KPI : formules du composant (statuts actifs, mois, taux arrondi, relance) — lues, puis exécutées par devis_poste_test', () {
    final bloc = RegExp(r'function getKpisProperty\(\): array\s*\{(.*?)\n    \}', dotAll: true).firstMatch(_composant!)!.group(1)!;
    expect(bloc, contains("whereIn('status', ['brouillon', 'envoye', 'accepte'])"));
    expect(bloc, contains("where('status', 'accepte')"));
    expect(bloc, contains("whereIn('status', ['accepte', 'refuse'])"));
    expect(bloc, contains("round((\$accepted / \$refusedOrAccepted) * 100)"));
    expect(bloc, contains("where('status', 'envoye')"));
    expect(bloc, contains("sum('amount')"), reason: 'la valeur totale est le montant HT');
    expect(bloc, contains('whereMonth(\'quote_date\', now()->month)'));
  }, skip: absent);

  testWidgets('⚠️ les cartes : libellé, icône et couleur de chaque `x-kpi-card` du Blade, dans son ordre', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevisOnglet(depot: DevisRepository(database: db, deviceId: 'poste-test'))),
      ),
    );
    await tester.pumpAndSettle();

    final web = [
      for (final m in RegExp(r'<x-kpi-card label="([^"]+)" icon="(\w+)" color="(\w+)"').allMatches(_sansCommentairesBlade(_blade!)))
        (m.group(1)!, m.group(2)!, m.group(3)!),
    ];
    expect(web, hasLength(4));

    const couleurs = <String, Color>{
      'emerald': AgriColors.brandEmerald,
      'blue': AgriColors.infoBlue,
      'maize': AgriColors.accentYellow,
      'red': AgriColors.errorRed,
    };
    const icones = <String, IconData>{
      'request_quote': SymbolesAgri.request_quote,
      'payments': SymbolesAgri.payments,
      'trending_up': SymbolesAgri.trending_up,
      'pending_actions': SymbolesAgri.pending_actions,
    };
    final cartes = tester.widgetList<CarteKpi>(find.byType(CarteKpi)).toList();
    expect([for (final c in cartes) c.libelle], [for (final w in web) w.$1]);
    for (final (i, w) in web.indexed) {
      expect(cartes[i].couleurLisere, couleurs[w.$3], reason: '${w.$1} : couleur ${w.$3}');
      expect(cartes[i].icone, icones[w.$2], reason: '${w.$1} : icône ${w.$2}');
    }
  }, skip: absent != null);
}
