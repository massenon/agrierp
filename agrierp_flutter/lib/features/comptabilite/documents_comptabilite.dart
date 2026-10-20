import '../../core/export/document_officiel.dart';
import 'comptabilite_repository.dart';

/// Documents officiels (PDF) des quatre pages comptables du poste — ticket F0.87 (item 9, T4).
///
/// ⚠️⚠️ **TITRES, SOUS-TITRES, COLONNES ET MENTION DE DÉSÉQUILIBRE SONT CEUX DU WEB** (ticket F0.88,
/// arbitrage client du 13/10/2026) : `resources/views/exports/*.blade.php` et les arguments passés
/// par les composants Livewire à `PdfExportService::render`, relus par un test. Avant F0.88 la
/// maquette faisait foi (`exportPlanComptablePDF`…) ; elle reste relue par un test qui ÉNUMÈRE les
/// écarts : sous-titres « État au JJ/MM/AAAA » (plan, journal ; maquette « Liste des comptes
/// actifs », « Écritures comptables SYSCOHADA »), « Solde Progressif » (maquette « Solde »),
/// « Ouv. Débit » … « Final Crédit » (maquette « Ouv. D » … « Final C »). ⚠️ Les titres et colonnes
/// de l'ÉCRAN restent ceux de la maquette : seuls les documents changent.
///
/// ⚠️ Ce qui n'est PAS repris du web (contenu de cellule, pas libellé ; décisions ouvertes) : la
/// classe « 4 - Tiers » du plan, « code - libellé » du premier compte au journal, le suffixe
/// « FCFA » des montants du journal et de l'ouverture du Grand Livre. Les choix F0.87 restent :
/// dates JJ/MM/AAAA, « (incomplète) », documents sans ligne non édités.
///
/// ⚠️⚠️ **LES CHIFFRES SONT CEUX DE L'ÉCRAN, PAR LA MÊME SOURCE** : les constructeurs reçoivent les
/// objets que l'écran affiche (`GrandLivreCompte`, `BalanceGenerale`, `DonneesComptabilite`) et les
/// formatent avec les MÊMES fonctions ([montant], [montantOuTiret], [jour]) — l'écran les appelle
/// aussi. Aucun recalcul ici.
///
/// ⚠️ **AJOUTS DU WEB REPRIS, À VALIDER** : la maquette n'exporte que le corps du tableau
/// (`#…-tbody tr`). Le web ajoute au Grand Livre une ligne « Solde d'ouverture » et une ligne
/// « Totaux de la période », à la Balance la ligne TOTAUX et la mention de déséquilibre. Le poste
/// les reprend (avec les valeurs des cartes et de la ligne TOTAUX de l'écran) : un grand livre
/// imprimé sans son solde de départ ne se relit pas. Depuis F0.88, la mention de déséquilibre porte
/// le TEXTE du web (« Balance déséquilibrée — écart de X FCFA. … ») et l'écart avec ses centimes
/// ([montantEcart]).
///
/// Une donnée que le poste ne peut pas affirmer est « — », jamais 0, avec sa raison en pied.
class DocumentsComptabilite {
  const DocumentsComptabilite._();

  /// Tiret affiché pour toute information que le poste ne détient pas.
  static const inconnu = '—';

  /// Raison commune d'un solde inconnu (Grand Livre et Balance), à l'écran comme sur le document.
  static const motifJournalIncomplet =
      'Journal incomplet : des écritures de ce poste sont déséquilibrées '
      '(tirage incomplet), le solde ne peut pas être affirmé';

  /// Mention de l'écran de la Balance quand le journal est incomplet (suit [motifJournalIncomplet]).
  static const suiteBalanceIncomplete =
      "Soldes d'ouverture et finaux portent un tiret ; "
      'les mouvements de la période sont ceux du journal reçu.';

  /// Texte du bandeau « Balance Déséquilibrée » de `balance-generale.html` (ÉCRAN seulement depuis
  /// F0.88 : le document imprime la mention du web).
  static const anomalieBalance =
      "Une anomalie de saisie doit être corrigée avant toute clôture (périodique ou annuelle) de l'exercice.";

  /// Marque d'une écriture incomplète dans la colonne Montant du document. ⚠️ L'écran écrit « ⚠ » :
  /// ce signe n'est PAS dans la police embarquée (Roboto) et sortirait en carré barré — prouvé par
  /// un test qui construit le PDF.
  static const marqueIncomplete = '(incomplète)';

  // ── Formateurs PARTAGÉS avec l'écran ──────────────────────────────────────

  /// ⚠️ Le signe se lit sur la valeur ARRONDIE (F0.86-bis) : un écart de -0,4 s'écrit « 0 », comme
  /// `number_format(-0.4, 0)` du serveur, jamais « -0 ».
  static String montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  /// ⚠️ Un montant nul ne s'écrit pas « 0 » au Grand Livre ni à la Balance : « — », comme la
  /// maquette et la page web (`> 0 ? montant : '—'`) — une ligne porte un débit OU un crédit.
  static String montantOuTiret(double valeur) =>
      valeur > 0 ? montant(valeur) : inconnu;

  /// Écart de la Balance (« Écart (doit être 0) », mention de déséquilibre du document) — ticket
  /// F0.88, arbitrage client du 13/10/2026.
  ///
  /// ⚠️⚠️ **ÉCART ASSUMÉ PAR RAPPORT AU WEB** : le web écrit `number_format($ecart, 0, ',', ' ')`,
  /// si bien qu'un écart de 0,40 F s'affichait « 0 » en rouge, avec le bandeau « Balance
  /// Déséquilibrée » — trompeur. Un écart NON NUL s'écrit ici avec ses centimes (« 0,40 »,
  /// « -1 234,50 ») : virgule décimale et espace des milliers, ceux de [montant] (et du web). Un
  /// écart nul reste « 0 ». Les autres montants gardent leur arrondi au franc.
  ///
  /// ⚠️ Le SEUIL d'équilibre n'est pas ici : `BalanceGenerale.equilibree` (|écart| < 0,01, Laravel).
  /// L'écart reçu est déjà arrondi au centime (`round(…, 2)` du serveur, repris par le dépôt) : « 0 »
  /// ici ⟺ équilibrée.
  ///
  /// ⚠️ Signe : écart = débits − crédits (soldes finaux), comme le serveur, la page web et la
  /// maquette ; négatif = crédits plus forts, et le web garde ce signe (« -1 » pour -0,6). Il est lu
  /// sur les CENTIMES ARRONDIS (F0.86-bis) : -0,004 ou -0,0 s'écrivent « 0 », jamais « -0 » ;
  /// -0,40 s'écrit « -0,40 ».
  static String montantEcart(double ecart) {
    final centimes = (ecart * 100).round();
    if (centimes == 0) return '0';
    // `centimes` est DÉJÀ la valeur arrondie (au centime) : le signe s'y lit sans risque de « -0 »
    // (garde-fou F0.86-bis de `montant_signe_test.dart`, qui vise le signe lu AVANT l'arrondi).
    final signe = centimes < 0 ? '-' : '';
    final valeur = centimes.abs();
    final cts = (valeur % 100).toString().padLeft(2, '0');
    return '$signe${montant((valeur ~/ 100).toDouble())},$cts';
  }

  static String jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Sous-titre du web pour le plan et le journal : `'État au '.now()->format('d/m/Y')`. ⚠️ [le] est
  /// l'horloge du POSTE (injectée à l'écran), jamais `DateTime.now()` ici : constructeurs purs.
  static String etatAu(DateTime le) => 'État au ${jour(le)}';

  static String _ouTiret(String v) => v.isEmpty ? inconnu : v;

  // ── Plan Comptable ────────────────────────────────────────────────────────

  /// `exportPlanComptablePDF()` — tous les comptes reçus, dans l'ordre de l'écran (code). La classe
  /// est celle de l'écran (le numéro ; « — » si absente). Sous-titre du web : « État au [le] ».
  static DocumentOfficiel plan(DonneesComptabilite d, {required DateTime le}) =>
      DocumentOfficiel(
        titre: 'Plan Comptable SYSCOHADA',
        fichier: 'plan-comptable-{jour}.pdf',
        sousTitre: etatAu(le),
        entetes: const ['N° Compte', 'Intitulé', 'Classe'],
        lignes: [
          for (final c in d.comptes)
            DonneesDocument([c.code, c.label, '${c.accountClass ?? inconnu}']),
        ],
      );

  // ── Journal Comptable ─────────────────────────────────────────────────────

  /// Cellule « Montant » d'une écriture sur le document (l'écran ajoute « ⚠ »).
  static String montantJournal(LigneJournal e) => e.equilibree
      ? montant(e.totalDebit)
      : '${montant(e.totalDebit)} $marqueIncomplete';

  /// `exportJournalPDF()` — les six premières colonnes de l'écran (sans « Actions »), dans son ordre
  /// (mêmes libellés que la vue web). Sous-titre du web : « État au [le] ».
  static DocumentOfficiel journal(
    DonneesComptabilite d, {
    required DateTime le,
  }) {
    final incompletes = d.journal.where((e) => !e.equilibree).length;

    return DocumentOfficiel(
      titre: 'Journal Comptable',
      fichier: 'journal-comptable-{jour}.pdf',
      sousTitre: etatAu(le),
      entetes: const [
        'N° Pièce',
        'Date',
        'Libellé',
        'Débit',
        'Crédit',
        'Montant',
      ],
      lignes: [
        for (final e in d.journal)
          DonneesDocument([
            _ouTiret(e.piece),
            jour(e.ecriture.entryDate),
            _ouTiret(e.libelle),
            e.comptesDebites,
            e.comptesCredites,
            montantJournal(e),
          ]),
      ],
      noteDePied: incompletes == 0
          ? null
          : '$incompletes écriture(s) marquée(s) « incomplète » : lignes non encore reçues au '
                'poste (tirage incomplet) ; le montant affiché est le total des débits reçus.',
    );
  }

  // ── Grand Livre ───────────────────────────────────────────────────────────

  /// `exportGrandLivrePDF()` — titre « Grand Livre — Compte 531 — Caisse » (libellé du sélecteur),
  /// sous-titre « Période du JJ/MM/AAAA au JJ/MM/AAAA » (dates AFFICHÉES ; la maquette recopiait la
  /// valeur brute AAAA-MM-JJ du champ, le web écrit JJ/MM/AAAA). Dernière colonne : « Solde
  /// Progressif » du web (F0.88 ; maquette « Solde »).
  ///
  /// Aucun mouvement sur la période : aucune ligne (l'écran n'édite pas un document vide).
  static DocumentOfficiel grandLivre(
    GrandLivreCompte g, {
    required DateTime debut,
    required DateTime fin,
  }) {
    final c = g.compte;
    final mouvements = g.mouvements;
    final ouverture = g.soldeOuverture;
    final soldeFinal = g.soldeFinal;

    return DocumentOfficiel(
      titre: c == null
          ? 'Grand Livre'
          : 'Grand Livre — Compte ${c.code} — ${c.label}',
      sousTitre: 'Période du ${jour(debut)} au ${jour(fin)}',
      // Ticket U11 — `'grand-livre-'.($account?->code ?? 'compte').'-'.now()->format('Y-m-d').'.pdf'` du web.
      fichier: 'grand-livre-${c?.code ?? 'compte'}-{jour}.pdf',
      entetes: const [
        'Date',
        'N° Pièce',
        'Libellé',
        'Débit',
        'Crédit',
        'Solde Progressif',
      ],
      lignes: mouvements.isEmpty
          ? const []
          : [
              TotalDocument([
                "Solde d'ouverture",
                '',
                '',
                '',
                '',
                ouverture == null ? inconnu : montant(ouverture),
              ]),
              for (final m in mouvements)
                DonneesDocument([
                  jour(m.ecriture.entryDate),
                  _ouTiret(m.piece),
                  _ouTiret(m.libelle),
                  montantOuTiret(m.ligne.debit),
                  montantOuTiret(m.ligne.credit),
                  montant(m.soldeProgressif),
                ]),
              TotalDocument([
                'Totaux de la période',
                '',
                '',
                montant(g.totalDebit),
                montant(g.totalCredit),
                soldeFinal == null ? inconnu : montant(soldeFinal),
              ], premiere: true),
            ],
      noteDePied: g.journalIncomplet && mouvements.isNotEmpty
          ? '$motifJournalIncomplet.'
          : null,
    );
  }

  // ── Balance Générale ──────────────────────────────────────────────────────

  /// Raison pour laquelle la Balance ne peut pas affirmer ses soldes, ou `null`.
  static String? motifBalance(BalanceGenerale b) => b.journalVide
      ? 'Aucune écriture reçue au poste'
      : b.journalIncomplet
      ? motifJournalIncomplet
      : null;

  /// `exportBalancePDF()` — sous-titre = texte de la période choisie ([periode]). Ouverture et final
  /// « — » quand le journal est incomplet ; mouvements toujours montrés. Colonnes du web
  /// (« Ouv. Débit » … « Final Crédit », F0.88) ; mention de déséquilibre du web, écart en centimes.
  static DocumentOfficiel balance(
    BalanceGenerale b, {
    required String periode,
  }) {
    final motif = motifBalance(b);
    String solde(double v) => motif != null ? inconnu : montantOuTiret(v);
    String total(double v) => motif != null ? inconnu : montant(v);

    return DocumentOfficiel(
      titre: 'Balance Générale',
      fichier: 'balance-generale-{jour}.pdf',
      sousTitre: periode,
      entetes: const [
        'N° Compte',
        'Libellé',
        'Ouv. Débit',
        'Ouv. Crédit',
        'Mvt Débit',
        'Mvt Crédit',
        'Final Débit',
        'Final Crédit',
      ],
      lignes: b.lignes.isEmpty
          ? const []
          : [
              for (final l in b.lignes)
                DonneesDocument([
                  l.code,
                  l.libelle,
                  solde(l.ouvertureDebit),
                  solde(l.ouvertureCredit),
                  montantOuTiret(l.mouvementsDebit),
                  montantOuTiret(l.mouvementsCredit),
                  solde(l.finalDebit),
                  solde(l.finalCredit),
                ]),
              TotalDocument([
                'TOTAUX',
                '',
                total(b.totalOuvertureDebit),
                total(b.totalOuvertureCredit),
                montant(b.totalMouvementsDebit),
                montant(b.totalMouvementsCredit),
                total(b.totalFinalDebit),
                total(b.totalFinalCredit),
              ], premiere: true),
            ],
      noteDePied: b.lignes.isEmpty
          ? null
          : motif != null
          ? (b.journalIncomplet ? '$motif. $suiteBalanceIncomplete' : null)
          : b.equilibree
          ? null
          : 'Balance déséquilibrée — écart de ${montantEcart(b.ecart)} FCFA. '
                'Une anomalie de saisie doit être corrigée avant toute clôture.',
    );
  }
}
