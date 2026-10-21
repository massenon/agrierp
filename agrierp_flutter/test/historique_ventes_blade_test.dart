import 'dart:io';

import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/historique_ventes_onglet.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'blade_ventes_lecture.dart';
import 'chemins_depot.dart';

/// Ticket AV2 — « HISTORIQUE DES VENTES » DU POSTE ALIGNÉ SUR LE BLADE (le maître, doctrine art. 5). Audit ligne à ligne
/// Blade ↔ Dart dans `docs/AUDIT_FIDELITE_ECRANS.md` § 11.
///
/// ⚠️⚠️ **LES ATTENDUS SONT LUS DANS LE BLADE ET DANS LE COMPOSANT LIVEWIRE**, jamais recopiés ici : titre, sous-titre, bouton,
/// cartes (nombre, libellés, icônes, couleurs), filtres et leurs options, colonnes dans leur ordre, statuts, règles de filtre
/// et de calcul (lues dans le PHP), modale d'annulation, tiroir de détail, toasts, droits. Avant ce ticket l'écran avait été
/// porté depuis la MAQUETTE (`historique-ventes.html`), et ses garde-fous comparaient à la maquette : onze écarts au Blade
/// s'y étaient installés (voir l'audit).
void main() {
  final saut = sautSansWebVentes();
  final fichiers = [
    'lib/features/ventes/historique_ventes_onglet.dart',
    'lib/features/ventes/historique_ventes_repository.dart',
    'lib/features/ventes/elements_ventes.dart',
  ];

  late String vue;
  late String composant;
  late Set<String> chaines;
  late String ecran;

  setUpAll(() {
    if (saut != null) return;
    vue = sansCommentaires(blade('historique-ventes').readAsStringSync());
    composant = livewire('HistoriqueVentes').readAsStringSync();
    chaines = litteraux(fichiers);
    ecran = codeSeul(fichiers.first);
  });

  test('l\'en-tête : titre, sous-titre, icône, bouton « Nouvelle Vente » du Blade', () {
    for (final texte in ['Historique des Ventes', "Toutes les ventes enregistrées de l'entreprise.", 'Nouvelle Vente']) {
      expect(vue, contains(texte));
      expect(chaines, contains(texte), reason: texte);
    }
    expect(vue, contains('receipt_long'));
    expect(ecran, contains('SymbolesAgri.receipt_long'));
    // `<a href="route('ventes.devis-hub')">` : le hub, sur son premier onglet.
    expect(vue, contains("route('ventes.devis-hub')"));
    expect(ecran, contains('onNouvelleVente'));
    // L'ancienne phrase du poste (« Ventes encaissées sur ce poste ») était FAUSSE depuis que `sales` descend au poste.
    expect(chaines.any((c) => c.contains('Ventes encaissées sur ce poste')), isFalse);
  }, skip: saut);

  test('⚠️⚠️ la période : deux champs Date `px-sm py-1.5 text-xs`, bornés à l\'exercice, dans la boîte `p-sm w-fit`', () {
    expect(vue, contains('flex items-center gap-xs bg-white border border-outline-variant rounded-lg p-sm w-fit'));
    expect(vue, contains('wire:model.live="dateFrom" type="date"'));
    expect(vue, contains('wire:model.live="dateTo" type="date"'));
    expect(vue, contains('text-xs border border-outline-variant rounded-lg px-sm py-1.5'));
    expect(vue, contains('calendar_month'));
    expect(vue, contains('>au</span>'));
    // Le poste : le champ partagé `ChampDateFiltre` en gabarit compact (py-1.5 → 30 px), jamais un champ dessiné à la main.
    expect(ecran, contains('ChampDateFiltre('));
    expect(RegExp(r'ChampDateFiltre\(\s*cle: const Key\([^)]*\),\s*valeur: [^,]+,\s*compact: true').allMatches(ecran).length, 2);
    expect(ecran, contains('SymbolesAgri.calendar_month'));
    expect(chaines, contains('au'));
    // `min` / `max` du web = l'exercice affiché ; une date hors exercice est ramenée à sa borne (`bornerPeriode`).
    expect(vue, contains('ExerciceChoisi::bornes()'));
    expect(composant, contains('ExerciceChoisi::periodeParDefaut('));
    expect(composant, contains('ExerciceChoisi::bornerPeriode('));
    expect(ecran, contains('periodeParDefaut('));
    expect(ecran, contains('bornerPeriode('));
    expect(ecran, contains('firstDate: etat?.bornes.debut'));
    expect(ecran, contains('lastDate: etat?.bornes.fin'));
  }, skip: saut);

  test('⚠️⚠️ les cartes : quatre, mêmes libellés, mêmes icônes, mêmes couleurs de liseré', () {
    expect(cartes(vue), 4);
    final web = libellesDeCartes(vue);
    expect(web.map((c) => c.$1), ["Chiffre d'Affaires", 'Transactions', 'Panier Moyen', 'Encours Créances']);
    expect(RegExp(r'CarteKpi\(').allMatches(ecran).length, 4);
    for (final (libelle, icone) in web) {
      expect(chaines, contains(libelle), reason: libelle);
      expect(ecran, contains('SymbolesAgri.$icone'), reason: 'icône $icone de « $libelle »');
    }
    // Liserés : `border-l-<couleur>` du Blade → couleur du poste.
    final listereWeb = [for (final m in RegExp(r'(?:border-l-4|kpi-card)[^"]*?border-l-([a-z-]+)').allMatches(vue)) m.group(1)!];
    expect(listereWeb, ['brand-emerald', 'info-blue', 'accent-yellow', 'error-red']);
    for (final couleur in ['brandEmerald', 'infoBlue', 'accentYellow', 'errorRed']) {
      expect(ecran, contains('couleurLisere: AgriColors.$couleur'), reason: couleur);
    }
    // Quatre colonnes dès `md:` (768 px), jamais `lg:` : `GrilleKpi`, partagée.
    expect(vue, contains('grid grid-cols-2 md:grid-cols-4 gap-md'));
    expect(ecran, contains('GrilleKpiAdaptative('));
    expect(File('lib/core/widgets/grille_kpi.dart').readAsStringSync(), contains('AgriBreakpoints.moyen(context) ? 4 : 2'));
  }, skip: saut);

  test('⚠️⚠️ les cartes se calculent comme le composant : ventes validées de la PÉRIODE, panier arrondi (0 sans vente), encours des créances ouvertes', () {
    expect(composant, contains("Sale::soldBetween(\$this->dateFrom, \$this->dateTo)->get()"));
    expect(composant, contains("\$this->salesInRange->where('status', 'validee')"));
    expect(composant, contains("'panier_moyen' => \$count > 0 ? round(\$validSales->sum('total') / \$count) : 0"));
    expect(composant, contains("Receivable::where('status', '!=', 'soldee')->sum('amount')"));
    expect(composant, contains("Receivable::where('status', '!=', 'soldee')->sum('amount_paid')"));
    // Le poste : « 0 FCFA » (jamais « — ») sans vente — c'est un calcul du web, pas une donnée inconnue.
    final depot = codeSeul(fichiers[1]);
    expect(depot, contains('valides.isEmpty ? 0 : (total / valides.length).roundToDouble()'));
    expect(depot, contains("v.status == 'validee'"));
    expect(depot, contains("c.status != 'soldee'"));
  }, skip: saut);

  test('⚠️⚠️ les filtres : placeholder, listes, options et « Réinitialiser » du Blade', () {
    for (final texte in [
      'Facture, client...',
      'Statut : Toutes',
      'Payée',
      'En attente',
      'Annulée',
      'Mode : Tous',
      'Espèces',
      'Mobile Money',
      'Virement',
      'Crédit client',
      'Avance',
      'Client : Tous',
      'Réinitialiser',
    ]) {
      expect(vue, contains(texte), reason: 'le Blade écrit « $texte »');
      expect(chaines, contains(texte), reason: texte);
    }
    expect(vue, contains('wire:model.live.debounce.300ms="search"'));
    expect(HistoriqueVentesOnglet.delaiRecherche, const Duration(milliseconds: 300));
    // Les valeurs et libellés des options de « Mode » : ceux de `$modeLabels` du Blade.
    final modes = <String, String>{
      for (final m in RegExp(r"'(\w+)' => '([^']+)'").allMatches(RegExp(r'\$modeLabels = \[[^\]]*\]').firstMatch(vue)!.group(0)!))
        m.group(1)!: m.group(2)!,
    };
    expect(modes, {'especes': 'Espèces', 'mobile_money': 'Mobile Money', 'virement': 'Virement', 'credit': 'Crédit client', 'avance': 'Avance'});
    expect(HistoriqueVentesRepository.libellesModes, modes);
    expect(HistoriqueVentesRepository.statuts, [('payee', 'Payée'), ('attente', 'En attente'), ('annulee', 'Annulée')]);
    for (final valeur in ['payee', 'attente', 'annulee']) {
      expect(vue, contains('<option value="$valeur">'), reason: valeur);
    }
    // `resetFilters()` : la recherche et les trois listes, jamais la période.
    expect(composant, contains("\$this->reset(['search', 'statusFilter', 'modeFilter', 'customerFilter'])"));
    // `Customer::where('is_active', true)->orderBy('name')`.
    expect(composant, contains("Customer::where('is_active', true)->orderBy('name')->get()"));
    // Le poste n'a plus de filtre « inerte » ni de boutons « Excel » / « PDF » que le web n'a pas.
    expect(ecran, isNot(contains('_boutonInerte')));
    expect(chaines.contains('Excel (.xlsx)') || chaines.contains('PDF'), isFalse);
  }, skip: saut);

  test('⚠️⚠️ les règles de filtre du composant : recherche, statut (jugé sur le MODE), mode, client, tri', () {
    // La recherche : l'identifiant COMPLET ou le nom du client (jamais « Client Anonyme »).
    expect(composant, contains("->where('id', 'like', '%'.\$this->search.'%')"));
    expect(composant, contains("->orWhereHas('customer', fn (\$q3) => \$q3->where('name', 'like', '%'.\$this->search.'%'))"));
    // Le statut : « En attente » = validée À CRÉDIT ; « Payée » = validée hors crédit.
    expect(composant, contains("\$this->statusFilter === 'annulee', fn (\$q) => \$q->where('status', 'annulee')"));
    expect(composant, contains("\$this->statusFilter === 'payee', fn (\$q) => \$q->where('status', 'validee')->where('payment_mode', '!=', 'credit')"));
    expect(composant, contains("\$this->statusFilter === 'attente', fn (\$q) => \$q->where('status', 'validee')->where('payment_mode', 'credit')"));
    expect(composant, contains("->when(\$this->modeFilter, fn (\$q) => \$q->where('payment_mode', \$this->modeFilter))"));
    expect(composant, contains("->when(\$this->customerFilter, fn (\$q) => \$q->where('customer_id', \$this->customerFilter))"));
    expect(composant, contains('->orderByEffectiveDate()'));
    expect(composant, contains("->orderByDesc('id')"));
    // Un filtre qui change ramène à la page 1.
    expect(composant, contains("in_array(\$propriete, ['search', 'statusFilter', 'modeFilter', 'customerFilter'], true)"));
    // Le poste.
    final depot = codeSeul(fichiers[1]);
    expect(depot, contains("'annulee' => v.status == 'annulee'"));
    expect(depot, contains("'payee' => v.status == 'validee' && v.paymentMode != 'credit'"));
    expect(depot, contains("'attente' => v.status == 'validee' && v.paymentMode == 'credit'"));
    expect(depot, contains('v.id.toLowerCase().contains(cherche)'));
    expect(depot, contains('b.soldAt.compareTo(a.soldAt)'));
    expect(depot, contains('b.id.compareTo(a.id)'));
  }, skip: saut);

  test('⚠️⚠️ les onze colonnes du tableau : celles du Blade, dans son ordre', () {
    final web = entetes(vue);
    expect(web, ['Facture', 'Client', 'Date', 'Articles', 'Remise', 'Total TTC', 'Payé', 'Reste', 'Mode', 'Statut', 'Actions']);

    final poste = [for (final m in RegExp(r"ColonneTableau\('([^']+)'").allMatches(ecran)) m.group(1)!];
    expect(poste, web);
    // Les colonnes alignées à droite au Blade (`text-right`) le sont au poste.
    final droite = [for (final m in RegExp(r'<th class="[^"]*text-right[^"]*[^>]*>([^<]+)</th>').allMatches(vue)) m.group(1)!.trim()];
    expect(droite, ['Articles', 'Remise', 'Total TTC', 'Payé', 'Reste', 'Actions']);
    expect(
      [for (final m in RegExp(r"ColonneTableau\('([^']+)', \d+, droite: true\)").allMatches(ecran)) m.group(1)!],
      droite,
    );
  }, skip: saut);

  test('⚠️⚠️ le contenu des cellules : facture, client, date, mode, payé, reste, statut — les expressions du Blade', () {
    expect(vue, contains('strtoupper(substr(\$sale->id, 0, 8))'));
    expect(vue, contains("\$sale->customer?->name ?? 'Client Anonyme'"));
    expect(vue, contains("\$sale->date_effective->format('d/m/Y H:i')"));
    expect(vue, contains("\$sale->lines->count()"));
    expect(vue, contains("number_format(\$sale->discount, 0, ',', ' ')"));
    expect(vue, contains("number_format(\$sale->total, 0, ',', ' ') }} FCFA"));
    expect(vue, contains("\$reste = \$sale->status === 'annulee' ? 0 : (\$sale->receivable?->balance ?? 0);"));
    expect(vue, contains("\$paye = \$sale->status === 'annulee' ? 0 : \$sale->total - \$reste;"));
    expect(vue, contains("\$reste > 0 ? 'text-error-deep font-bold' : ''"));
    expect(vue, contains("\$sale->status === 'annulee' ? 'opacity-50' : ''"));
    expect(vue, contains("@elseif(\$reste > 0)"));
    // Les pastilles.
    for (final texte in ['Annulée', 'En attente', 'Payée']) {
      expect(vue, contains(texte));
      expect(chaines, contains(texte), reason: texte);
    }
    final depot = codeSeul(fichiers[1]);
    expect(depot, contains("String get statut => annulee ? 'Annulée' : (reste > 0 ? 'En attente' : 'Payée');"));
    expect(depot, contains('double get paye => annulee ? 0 : vente.total - reste;'));
    expect(depot, contains("if (v.status == 'annulee')"));
    expect(ecran, contains('opaciteLigne'));
    expect(ecran, contains("'\${AvoirsRepository.montantFr(v.total)} FCFA'"));
    expect(chaines, contains('Client Anonyme'));
    expect(AvoirsRepository.nomDuClient(null, const {}), 'Client Anonyme');
    // « Payée / En attente » : couleurs des pastilles du Blade.
    expect(vue, contains('bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30'));
    expect(vue, contains('bg-accent-yellow/20 text-brand-forest border-accent-yellow'));
    expect(vue, contains('bg-error-bg text-error-deep border-error-deep/30'));
    expect(File(fichiers[2]).readAsStringSync(), contains('0x1A065F46'));
    expect(File(fichiers[2]).readAsStringSync(), contains('0x33FFD55F'));
    expect(File(fichiers[2]).readAsStringSync(), contains('0x4DBA1A1A'));
  }, skip: saut);

  test('les actions de ligne : « Voir » toujours, « Annuler » sauf vente annulée (et grisé en lecture seule)', () {
    expect(vue, contains('title="Voir"'));
    expect(vue, contains('title="Annuler"'));
    expect(vue, contains("@if(\$sale->status !== 'annulee')"));
    expect(vue, contains('<button @lectureSeule type="button" wire:click="confirmCancel('));
    for (final icone in ['visibility', 'delete']) {
      expect(vue, contains(icone));
      expect(ecran, contains('SymbolesAgri.$icone'), reason: icone);
    }
    expect(ecran, contains('if (!l.annulee)'));
    expect(ecran, contains('LectureSeule.motif(context)'));
    expect(ecran, contains('LectureSeule.infobulle('));
    expect(chaines, contains('Voir'));
    expect(chaines, contains('Annuler'));
    // La facture ouvre aussi le détail (`wire:click="view(...)"`).
    expect(vue, contains('<button type="button" wire:click="view(\'{{ \$sale->id }}\')" class="text-brand-emerald hover:underline font-bold font-mono">'));
    expect(ecran, contains("Key('vente-ref-"));
  }, skip: saut);

  test('états vides, pagination dans l\'exercice (25 par page) et clés de page', () {
    expect(vue, contains('Aucune vente pour le moment.'));
    expect(chaines, contains('Aucune vente pour le moment.'));
    expect(vue, contains('<x-pagination :paginator="\$this->sales" />'));
    expect(composant, contains('ExerciceChoisi::PAR_PAGE'));
    expect(composant, contains("pageName: 'pageVentes'"));
    expect(composant, contains('[\$debut, \$fin] = ExerciceChoisi::bornes();'));
    expect(ecran, contains('PaginationAgri('));
    expect(ecran, contains('PaginationAgri.tranche('));
    expect(ecran, contains('etat?.contient'));
    expect(ecran, contains("nom: 'ventes'"));
  }, skip: saut);

  test('⚠️⚠️ la modale « Annuler cette vente ? » et ses mots, ceux du Blade', () {
    for (final texte in [
      'Annuler cette vente ?',
      'Le stock des produits vendus sera automatiquement réintégré. Cette action est réversible uniquement en recréant une nouvelle vente.',
      'Annuler',
      'Oui, Annuler la Vente',
    ]) {
      expect(vue, contains(texte), reason: 'le Blade écrit « $texte »');
    }
    expect(chaines, contains('Annuler cette vente ?'));
    expect(chaines, contains('Oui, Annuler la Vente'));
    expect(
      chaines.any((c) => c == 'Le stock des produits vendus sera automatiquement réintégré. ' || c.contains('Le stock des produits vendus sera automatiquement réintégré.')),
      isTrue,
    );
    expect(chaines, contains('Cette action est réversible uniquement en recréant une nouvelle vente.'));
    expect(vue, contains('<x-modal name="modal-cancel-sale" max-width="sm">'));
    expect(vue, contains('<button @lectureSeule type="button" wire:click="cancelSale"'));
    expect(vue, contains('warning'));
    expect(ecran, contains('SymbolesAgri.warning'));
    expect(ecran, contains('LargeurModale.sm'));
    expect(ecran, isNot(contains('AlertDialog')));
    expect(ecran, isNot(contains('showDialog(')));
    expect(ecran, contains('afficherModale<bool>'));
  }, skip: saut);

  test('⚠️⚠️ le toast d\'annulation : celui du web, et l\'écart assumé (le stock est réintégré à la synchronisation)', () {
    expect(composant, contains("'Vente annulée — stock réintégré.', type: 'warning'"));
    expect(HistoriqueVentesOnglet.toastAnnulee, 'Vente annulée — stock réintégré.');
    expect(ecran, contains('type: TypeToast.avertissement'));
    expect(HistoriqueVentesOnglet.toastAnnuleeAuPoste, startsWith('Vente annulée — '));
    expect(composant, contains("\$this->authorize('manage-ventes');"));
    expect(chaines, contains('Votre rôle ne permet pas cette action.'));
    // Le composant passe par `AnnulerVenteAction`, le MÊME point de passage que l'envoi du poste.
    expect(composant, contains('app(AnnulerVenteAction::class)->execute(\$sale)'));
  }, skip: saut);

  test('⚠️⚠️ le tiroir de détail : référence, client, date, articles, sous-total, remise, total, « Télécharger PDF », « Fermer »', () {
    for (final texte in ['Client', 'Date', 'Articles', 'Sous-total', 'Remise', 'Total', 'Télécharger PDF', 'Fermer']) {
      expect(vue, contains(texte), reason: 'le Blade écrit « $texte »');
    }
    expect(chaines, contains('Client'));
    expect(chaines, contains('Date'));
    expect(chaines, contains('ARTICLES'));
    expect(chaines, contains('Sous-total'));
    expect(chaines, contains('Remise'));
    expect(chaines, contains('Total'));
    expect(chaines, contains('Télécharger PDF'));
    expect(chaines, contains('Fermer'));
    expect(vue, contains('fixed top-0 right-0 h-full w-full sm:w-96 bg-white'));
    expect(vue, contains('fixed inset-0 bg-black/40'));
    expect(vue, contains('x-on:keydown.escape.window="\$wire.closeDrawer()"'));
    expect(vue, contains("{{ \$line->product?->name }} × {{ rtrim(rtrim(number_format(\$line->qty, 2, '.', ''), '0'), '.') }}"));
    expect(vue, contains("number_format(\$line->manual_total_amount, 0, ',', ' ') }} FCFA"));
    expect(vue, contains("number_format(\$this->viewingSale->subtotal, 0, ',', ' ') }} FCFA"));
    expect(ecran, contains('LogicalKeyboardKey.escape'));
    expect(ecran, contains('384'), reason: 'sm:w-96 = 384 px');
    expect(ecran, contains('SymbolesAgri.download'));
    expect(ecran, contains('AvoirsRepository.quantiteFr('));
    // `closeDrawer()` : le voile, le ✕ et « Fermer ».
    expect(vue, contains('wire:click="closeDrawer"'));
  }, skip: saut);

  test('⚠️ « Télécharger PDF » : le ticket de caisse du web (`exports.sale-ticket`), droit `export-ventes`', () {
    expect(composant, contains("\$this->authorize('export-ventes');"));
    expect(composant, contains("'exports.sale-ticket'"));
    final api = File('$dossierLaravel/app/Http/Controllers/Api/VenteController.php').readAsStringSync();
    expect(api, contains("'exports.sale-ticket'"));
    expect(api, contains("can('export-ventes')"));
    expect(File('$dossierLaravel/routes/api.php').readAsStringSync(), contains("'/ventes/{id}/pdf'"));
    expect(codeSeul(fichiers[1]), contains("'/api/ventes/\$venteId/pdf'"));
  }, skip: saut);

  test('l\'écran ne touche NI au stock NI à la comptabilité : l\'annulation est une demande', () {
    for (final f in [fichiers[0], fichiers[1]]) {
      final source = codeSeul(f);
      expect(source, isNot(contains('stockAdjustments')), reason: f);
      expect(source, isNot(contains('accountingEntries')), reason: f);
      expect(source, isNot(contains('stockQty')), reason: f);
    }
  }, skip: saut);

  test('aucune valeur en dur interdite : ni `Icons.`, ni dialogue natif, ni taille de texte hors prototype', () {
    for (final f in fichiers) {
      final source = codeSeul(f);
      expect(RegExp(r'\bIcons\.').hasMatch(source), isFalse, reason: f);
      expect(source, isNot(contains('AlertDialog')), reason: f);
      expect(RegExp(r'fontSize:\s*(12(\.5)?|13)\b').hasMatch(source), isFalse, reason: f);
    }
  }, skip: saut);

  test('le hub branche l\'onglet et ne garde plus l\'ancien historique', () {
    final hub = File('lib/features/ventes/ventes_devis_screen.dart').readAsStringSync();
    expect(hub, contains('HistoriqueVentesOnglet('));
    expect(hub, isNot(contains('_ongletHistorique')));
    expect(hub, isNot(contains('DonneesHistorique')));
  });
}
