import 'dart:io';

import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'blade_ventes_lecture.dart';

/// Ticket AV1 — « RETOURS ET AVOIRS » DU POSTE ALIGNÉ SUR LE BLADE (le maître, doctrine art. 5, directive de fidélité
/// absolue du 17/10/2026).
///
/// ⚠️⚠️ **LES ATTENDUS SONT LUS DANS LE BLADE, LE COMPOSANT LIVEWIRE ET LE SERVICE DE RETOUR**, jamais recopiés ici : titres,
/// sous-titre, colonnes dans leur ordre, statuts, décisions, cartes (nombre, libellés, icônes), sections et libellés de la
/// modale, état vide, toasts, messages de validation (`lang/fr/validation.php`) et refus du serveur (`AvoirClientService`).
/// Un libellé qui change au web fait rougir ce fichier au lieu de laisser le poste diverger en silence.
///
/// ⚠️ Les ÉCARTS ASSUMÉS (hors ligne) sont listés ici, avec leur raison, et nulle part ailleurs : le numéro « — » d'une
/// demande non reçue, la mention « Non envoyé », le toast du retour (le stock n'est réintégré qu'à la synchronisation).
void main() {
  final saut = sautSansWebVentes();
  final fichiers = [
    'lib/features/ventes/retours_avoirs_onglet.dart',
    'lib/features/ventes/avoirs_repository.dart',
    'lib/features/ventes/elements_ventes.dart',
  ];

  late String vue;
  late String composant;
  late String service;
  late String validation;
  late Set<String> chaines;

  setUpAll(() {
    if (saut != null) return;
    vue = sansCommentaires(blade('retours-avoirs').readAsStringSync());
    composant = livewire('RetoursAvoirs').readAsStringSync();
    service = serviceAvoir().readAsStringSync();
    validation = validationFr().readAsStringSync();
    chaines = litteraux(fichiers);
  });

  test('l\'en-tête : titre, sous-titre, icône et bouton « Nouveau Retour » du Blade', () {
    for (final texte in [
      'Retours et Avoirs',
      'Gestion des retours produits, avoirs clients et inspection sanitaire du cheptel retourné.',
      'Nouveau Retour',
    ]) {
      expect(vue, contains(texte));
      expect(chaines, contains(texte), reason: texte);
    }
    expect(vue, contains('assignment_return'));
    expect(vue, contains('add_circle'));
    final source = codeSeul(fichiers.first);
    expect(source, contains('SymbolesAgri.assignment_return'));
    expect(source, contains('SymbolesAgri.add_circle'));
  }, skip: saut);

  test('⚠️ les neuf colonnes du tableau : celles du Blade, dans son ordre', () {
    final web = entetes(vue);
    expect(web, ['Avoir', 'Facture', 'Client', 'Date', 'Motif', 'Décision', 'Montant', 'Statut', 'Actions']);

    final poste = [
      for (final m in RegExp(r"ColonneTableau\('([^']+)'").allMatches(codeSeul(fichiers.first))) m.group(1)!,
    ];
    expect(poste, web);
  }, skip: saut);

  test('⚠️⚠️ les cartes : le même nombre, les mêmes libellés, les mêmes icônes', () {
    expect(cartes(vue), 4);
    final web = libellesDeCartes(vue);
    expect(web.map((c) => c.$1), ['Retours du mois', 'Montant Avoirs', 'Produits Retournés', 'Taux de Retour']);

    final source = codeSeul(fichiers.first);
    expect(RegExp(r'CarteKpi\(').allMatches(source).length, 4);
    for (final (libelle, icone) in web) {
      expect(chaines, contains(libelle), reason: libelle);
      expect(source, contains('SymbolesAgri.$icone'), reason: 'icône $icone de « $libelle »');
    }
    // Les icônes existent dans la fonte du poste (sinon : un carré vide, sans erreur).
    expect(SymbolesAgri.percent.codePoint, isNonZero);
    expect(SymbolesAgri.payments.codePoint, isNonZero);
  }, skip: saut);

  test('les cartes se calculent comme le composant : mois courant, somme tronquée, taux arrondi à une décimale', () {
    expect(composant, contains("CreditNote::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)"));
    expect(composant, contains("(int) (clone \$monthNotes)->whereNotNull('qty')->sum('qty')"));
    expect(composant, contains('round(((clone \$monthNotes)->count() / \$monthSalesCount) * 100, 1)'));
    expect(composant, contains("Sale::where('status', 'validee')"));
    // La carte « Taux de Retour » : `number_format(taux, 1, ',', ' ')` suivi de « % ».
    expect(vue, contains("number_format(\$this->kpis['taux_retour'], 1, ',', ' ') }}%"));
  }, skip: saut);

  test('statuts et décisions : « Traité » / « En attente », « Réintégré » / « Réforme »', () {
    for (final texte in ['Traité', 'En attente', 'Réintégré', 'Réforme', 'Marquer comme traité']) {
      expect(vue, contains(texte), reason: 'le Blade écrit $texte');
      expect(chaines, contains(texte), reason: texte);
    }
    expect(vue, contains("\$note->status === 'traite'"));
    expect(vue, contains("\$note->status === 'en_attente'"));
    expect(vue, contains('restart_alt'));
    expect(vue, contains('heart_broken'));
    final source = codeSeul(fichiers.first);
    expect(source, contains('SymbolesAgri.restart_alt'));
    expect(source, contains('SymbolesAgri.heart_broken'));
    expect(source, contains('SymbolesAgri.check_circle'));
  }, skip: saut);

  test('états vides et valeurs par défaut du Blade', () {
    expect(vue, contains('Aucun retour pour le moment.'));
    expect(chaines, contains('Aucun retour pour le moment.'));
    expect(vue, contains("?? 'Client Anonyme'"));
    expect(chaines, contains('Client Anonyme'));
    expect(vue, contains('strtoupper(substr(\$note->sale_id, 0, 8))'));
    expect(vue, contains("format('d/m/Y')"));
  }, skip: saut);

  test('⚠️⚠️ la modale « Nouveau Retour » : sections, libellés, invites et aide du Blade', () {
    final libelles = [
      'Nouveau Retour',
      '1. Facture Source',
      '-- Sélectionner une vente --',
      '2. Article Retourné',
      '-- Sélectionner --',
      'Quantité Retournée *',
      "Montant de l'Avoir (FCFA) *",
      '3. Motif du Retour',
      'ex : Produit détérioré, erreur de quantité, mortalité...',
      '4. Inspection Sanitaire (si sujet vivant)',
      'ex : Contrôle visuel effectué, RAS',
      '5. Décision',
      'Réintégrer au stock',
      'Réformer (détruire)',
      "Réintégrer ajoute réellement la quantité au stock du produit. Réformer n'a aucun impact sur le stock (traçabilité seule).",
      'Annuler',
      'Enregistrer le Retour',
    ];
    for (final texte in libelles) {
      expect(vue, contains(texte), reason: 'le Blade écrit « $texte »');
      // Les titres de section sont rendus en capitales (`uppercase`) par `_bloc`.
      expect(chaines.contains(texte) || chaines.contains(texte.toUpperCase()), isTrue, reason: texte);
    }
    // Les quatre sections suivantes n'existent qu'avec une vente choisie (`@if($this->selectedSale)`).
    expect(vue, contains('@if(\$this->selectedSale)'));
    expect(codeSeul(fichiers.first), contains('if (vente != null) ...['));
    // Les valeurs des boutons radio.
    expect(vue, contains('value="reintegre"'));
    expect(vue, contains('value="reforme"'));
    // Le gabarit des champs : `h-11 px-md border rounded-lg text-sm`.
    expect(vue, contains('w-full h-11 px-md border rounded-lg text-sm'));
  }, skip: saut);

  test('la liste des ventes et celle des articles : le texte des options du Blade', () {
    // `{{ ID8 }} — {{ client }} — {{ total }} FCFA` ; `{{ produit }} ({{ qty }} {{ unité }})`.
    expect(vue, contains("{{ strtoupper(substr(\$sale->id, 0, 8)) }} — {{ \$sale->customer?->name ?? 'Client Anonyme' }} — {{ number_format(\$sale->total, 0, ',', ' ') }} FCFA"));
    expect(vue, contains("{{ \$line->product?->name }} ({{ rtrim(rtrim(number_format(\$line->qty, 2, '.', ''), '0'), '.') }} {{ \$line->product?->unit }})"));
    final source = codeSeul(fichiers[0]);
    expect(source, contains(r"'${v.reference} — ${v.client} — ${AvoirsRepository.montantFr(v.vente.total)} FCFA'"));
    expect(source, contains(r"'${a.nom} (${AvoirsRepository.quantiteFr(a.quantite)} ${a.unite})'"));
    expect(composant, contains('->limit(50)'), reason: '`recentSales` : les 50 dernières ventes VALIDÉES');
    expect(composant, contains("Sale::with('customer')->where('status', 'validee')->orderByEffectiveDate()"));
    expect(codeSeul(fichiers[1]), contains('..limit(50)'));
  }, skip: saut);

  test('⚠️⚠️ la saisie : champs obligatoires, messages de lang/fr/validation.php, mot pour mot', () {
    // Les règles du composant.
    for (final regle in [
      "'saleId' => ['required', 'exists:sales,id']",
      "'productId' => ['required', 'exists:products,id']",
      "'qty' => ['required', 'numeric', 'min:0.01']",
      "'amount' => ['required', 'numeric', 'min:0']",
      "'reason' => ['required', 'string', 'max:255']",
      "'decision' => ['required', 'in:reintegre,reforme']",
    ]) {
      expect(composant, contains(regle), reason: regle);
    }

    String requis(String cle) => messageValidation(validation, 'required', attr: attribut(validation, cle));
    expect(AvoirsRepository.messageVenteObligatoire, requis('saleId'));
    expect(AvoirsRepository.messageProduitObligatoire, requis('productId'));
    expect(AvoirsRepository.messageQuantiteObligatoire, requis('qty'));
    expect(AvoirsRepository.messageMontantObligatoire, requis('amount'));
    expect(AvoirsRepository.messageMotifObligatoire, requis('reason'));
    expect(
      AvoirsRepository.messageQuantiteMinimale,
      messageValidation(validation, 'min', type: 'numeric', attr: attribut(validation, 'qty'), params: {'min': '0.01'}),
    );
    expect(
      AvoirsRepository.messageMontantMinimal,
      messageValidation(validation, 'min', type: 'numeric', attr: attribut(validation, 'amount'), params: {'min': '0'}),
    );
    expect(
      AvoirsRepository.messageMotifTropLong,
      messageValidation(validation, 'max', type: 'string', attr: attribut(validation, 'reason'), params: {'max': '255'}),
    );
  }, skip: saut);

  test('⚠️⚠️ les refus du serveur sont reproduits AVANT d\'écrire, mot pour mot (AvoirClientService)', () {
    expect(service, contains("'Cette vente est inconnue.'"));
    expect(service, contains("'Cette vente est annulée : aucun retour n\\'est possible.'"));
    expect(service, contains("'Ce produit ne figure pas sur cette vente.'"));
    expect(service, contains("'Ce produit a déjà été retourné en totalité sur cette vente.'"));
    expect(service, contains("'La quantité retournée dépasse ce qui reste retournable : '"));
    expect(service, contains("' vendu(s), '"));
    expect(service, contains("' déjà retourné(s), '"));
    expect(service, contains("' restant(s).'"));
    expect(service, contains("'Le montant de l\\'avoir dépasse ce qui reste à créditer sur cette ligne : '"));

    expect(AvoirsRepository.messageVenteInconnue, 'Cette vente est inconnue.');
    expect(AvoirsRepository.messageVenteAnnulee, "Cette vente est annulée : aucun retour n'est possible.");
    expect(AvoirsRepository.messageProduitHorsVente, 'Ce produit ne figure pas sur cette vente.');
    expect(AvoirsRepository.messageDejaRetourneEnTotalite, 'Ce produit a déjà été retourné en totalité sur cette vente.');
    expect(
      AvoirsRepository.messageQuantiteAuDela(vendu: 10, retourne: 6, reste: 4),
      'La quantité retournée dépasse ce qui reste retournable : 10 vendu(s), 6 déjà retourné(s), 4 restant(s).',
    );
    expect(
      AvoirsRepository.messageMontantAuDela(9000),
      "Le montant de l'avoir dépasse ce qui reste à créditer sur cette ligne : 9 000 FCFA.",
    );
  }, skip: saut);

  test('⚠️ les toasts du web sont ceux du poste ; l\'écart assumé (hors ligne) ne retire rien d\'essentiel', () {
    expect(composant, contains("'Retour enregistré — produit réintégré au stock.'"));
    expect(composant, contains("'Retour enregistré — produit réformé, aucun impact stock.'"));
    expect(composant, contains("' Avoir comptabilisé (débit 701 / crédit 411).'"));
    expect(composant, contains("'Avoir marqué comme traité.'"));
    expect(composant, contains("'Retour refusé : '"));
    expect(AvoirsRepository.toastReintegre, 'Retour enregistré — produit réintégré au stock.');
    expect(AvoirsRepository.toastReforme, 'Retour enregistré — produit réformé, aucun impact stock.');
    expect(AvoirsRepository.toastComptabilise, ' Avoir comptabilisé (débit 701 / crédit 411).');
    expect(AvoirsRepository.toastTraite, 'Avoir marqué comme traité.');
    // ⚠️ ÉCART ASSUMÉ : « … produit réintégré au stock » dit un effet qui n'a pas encore eu lieu au poste ; le toast du poste
    // garde « Retour enregistré », la décision, et « débit 701 / crédit 411 ».
    final demande = AvoirsRepository.toastDemande('reintegre', montantNul: false);
    expect(demande, startsWith('Retour enregistré'));
    expect(demande, contains('débit 701 / crédit 411'));
    expect(AvoirsRepository.toastDemande('reforme', montantNul: false), contains('produit réformé, aucun impact stock'));
    expect(chaines, contains('Retour refusé : \$motif'));
  }, skip: saut);

  test('les droits : `authorize(\'manage-ventes\')` sur les deux méthodes qui écrivent, comme au web', () {
    expect(RegExp(r"authorize\('manage-ventes'\)").allMatches(composant).length, 2);
    final source = codeSeul(fichiers.first);
    expect(source, contains('widget.peutGerer'));
    expect(chaines, contains('Votre rôle ne permet pas cette action.'));
  }, skip: saut);

  test('aucun dialogue natif, aucune icône Flutter : ModaleAgri et SymbolesAgri', () {
    for (final f in fichiers) {
      final source = codeSeul(f);
      expect(source, isNot(contains('AlertDialog')), reason: f);
      expect(source, isNot(contains('showDialog(')), reason: f);
      expect(RegExp(r'\bIcons\.').hasMatch(source), isFalse, reason: f);
    }
    expect(codeSeul(fichiers.first), contains('ModaleAgri('));
    expect(codeSeul(fichiers.first), contains('afficherModale<'));
  }, skip: saut);

  test('le poste n\'écrit AUCUN effet d\'un avoir : ni ajustement de stock, ni écriture, ni numéro', () {
    for (final f in [fichiers[0], fichiers[1]]) {
      final source = codeSeul(f);
      expect(source, isNot(contains('stockAdjustments')), reason: f);
      expect(source, isNot(contains('accountingEntries')), reason: f);
      expect(source, isNot(contains('stockQty')), reason: f);
    }
  }, skip: saut);

  test('le fichier de l\'onglet existe et le hub ne contient plus l\'ancien module « non embarqué »', () {
    expect(File(fichiers.first).existsSync(), isTrue);
    final hub = File('lib/features/ventes/ventes_devis_screen.dart').readAsStringSync();
    expect(hub, isNot(contains('avoirs-non-embarque')));
    expect(hub, contains('RetoursAvoirsOnglet('));
  });
}
