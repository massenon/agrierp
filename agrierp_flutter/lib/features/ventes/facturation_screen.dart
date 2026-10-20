import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import 'facturation_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/facturation.html` → Facturation & MeCeF.
///
/// ⚠️⚠️ **UNE FACTURE EST UNE VENTE.** Il n'existe pas de table `invoices` :
/// `sales.mecef_status` et `sales.mecef_qr_ref` portent la normalisation
/// fiscale auprès de la DGI (dispositif MeCeF, ticket 7.1).
///
/// ⚠️⚠️ **CE QUE CET ÉCRAN A RÉVÉLÉ.** Le canal d'envoi hors ligne appliquait
/// les quatre effets d'une vente — stock, fiche d'élevage, écriture,
/// encaissement — et **oubliait la transmission MeCeF** que la caisse web fait
/// systématiquement. Toute vente encaissée sans réseau arrivait donc sur le
/// serveur sans QR ni déclaration : jamais connue de l'administration fiscale.
/// Corrigé au ticket 14.80 ; la colonne « Statut MeCeF » le rend désormais
/// visible, facture par facture.
///
/// ⚠️ **AUCUNE FACTURE NE SE CRÉE ICI**, et ce n'est pas un renoncement : le
/// formulaire « Nouvelle Facture » de la maquette (Client + Montant HT + TVA,
/// sans article) produirait une facture déconnectée de toute vente et de tout
/// stock. La surface web redirige déjà vers la caisse ; le poste fait de même.
class FacturationScreen extends StatefulWidget {
  const FacturationScreen({
    super.key,
    required this.depot,
    this.onOuvrirCaisse,
  });

  final FacturationRepository depot;

  /// Ouvre la caisse — seul point d'entrée réel d'une facture.
  final VoidCallback? onOuvrirCaisse;

  @override
  State<FacturationScreen> createState() => _FacturationScreenState();
}

class _FacturationScreenState extends State<FacturationScreen> {
  /// Filtres de la maquette, dans son ordre.
  static const filtres = <String>[
    'Tous les statuts',
    'Transmise',
    'En attente',
    'Erreur MeCeF',
  ];

  String _filtre = filtres.first;
  DonneesFacturation? _donnees;

  /// Ticket EX7 (EF9) — page des factures (25), dans l'exercice affiché.
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    // Ticket EX7 — « (mois) » sur le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de
    // 2026 lu en 2027), comme `Facturation::getKpisProperty`.
    final donnees = await widget.depot.charger(mois: PorteeExerciceChoisi.lire(context)?.moisDeReference);
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  /// Ticket EX7 (EF9) — les factures de l'exercice AFFICHÉ (web : `soldBetween` de l'exercice), filtre compris.
  List<LigneFacture> _visibles(DonneesFacturation d) {
    final etat = PorteeExerciceChoisi.lire(context);
    return [
      for (final f in d.factures)
        if ((etat == null || etat.contient(f.vente.soldAt)) &&
            (_filtre == filtres.first || f.statut.libelle == _filtre))
          f,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);
                final lignes = _visibles(d);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entete(large),
                      const SizedBox(height: AgriSpacing.md),
                      _grilleKpis(large, d),
                      const SizedBox(height: AgriSpacing.md),
                      _barreFiltres(),
                      const SizedBox(height: AgriSpacing.md),
                      // Ticket EX7 (EF9) — 25 factures par page, `<x-pagination>` du web sous le tableau.
                      _tableau(
                        PorteeExerciceChoisi.lire(context) == null ? lignes : PaginationAgri.tranche(lignes, _page),
                      ),
                      if (PorteeExerciceChoisi.lire(context) case final etat?)
                        PaginationAgri(
                          nom: 'factures',
                          total: lignes.length,
                          page: _page,
                          annee: etat.annee,
                          onPage: (p) => setState(() => _page = p),
                        ),
                      const SizedBox(height: AgriSpacing.md),
                      _mentionPoste(
                        "Une facture naît d'une vente : elle se crée à la "
                        'caisse, jamais ici. La transmission au dispositif '
                        'MeCeF est faite par le serveur à la réception de la '
                        'vente — un poste hors ligne ne peut pas joindre la '
                        'DGI lui-même.',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _entete(bool large) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(SymbolesAgri.receipt_long, size: 26, color: AgriColors.brandEmerald),
      const SizedBox(width: AgriSpacing.xs),
      Expanded(
        child: Text(
          'Facturation & MeCeF',
          style: TextStyle(
            fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
      ),
      // ⚠️ Le bouton de la maquette est conservé, et il MÈNE À LA CAISSE :
      // c'est ce que la surface web a tranché, et la seule façon qu'une
      // facture corresponde à une vente réelle.
      if (widget.onOuvrirCaisse != null)
        FilledButton.icon(
          key: const Key('nouvelle-facture'),
          onPressed: widget.onOuvrirCaisse,
          icon: const Icon(SymbolesAgri.add, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
          ),
          label: const Text(
            'Nouvelle Facture',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
    ],
  );

  Widget _grilleKpis(bool large, DonneesFacturation d) => GridView.count(
    crossAxisCount: large ? 4 : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: [
      CarteKpi(
        libelle: 'Factures (mois)',
        valeur: '${d.duMois.length}',
        legende: '${_montant(d.montantDuMois)} FCFA',
        couleurLisere: AgriColors.brandEmerald,
        icone: SymbolesAgri.receipt_long,
      ),
      CarteKpi(
        libelle: 'Statut "Transmise"',
        valeur: '${d.compte(StatutMecef.transmise)}',
        legende: 'Reçues par le dispositif',
        couleurLisere: AgriColors.infoBlue,
        icone: SymbolesAgri.verified,
        couleurIcone: AgriColors.infoBlue,
      ),
      CarteKpi(
        libelle: 'En attente',
        valeur: '${d.compte(StatutMecef.enAttente)}',
        legende: 'Transmission en cours',
        couleurLisere: AgriColors.accentYellow,
        icone: SymbolesAgri.schedule,
        couleurIcone: AgriColors.brandForest,
      ),
      // ⚠️⚠️ DEUX COMPTES DISTINCTS, ET C'EST TOUT LE SUJET. « Erreur » = la
      // DGI a refusé ; « Non transmise » = personne n'a essayé, parce que la
      // vente n'a pas encore quitté ce poste. Les additionner masquerait
      // lequel des deux problèmes se pose.
      CarteKpi(
        libelle: 'Erreur MeCeF',
        valeur: '${d.compte(StatutMecef.erreur)}',
        legende: d.enAttenteDEnvoi > 0
            ? '${d.enAttenteDEnvoi} facture(s) pas encore envoyée(s)'
            : 'Toutes les ventes sont parties',
        couleurLisere: AgriColors.errorRed,
        icone: SymbolesAgri.error_outline,
        couleurIcone: AgriColors.errorRed,
      ),
    ],
  );

  Widget _barreFiltres() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final filtre in filtres) ...[
          InkWell(
            key: Key('filtre-$filtre'),
            onTap: () => setState(() {
              _filtre = filtre;
              _page = 1;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: _filtre == filtre
                    ? AgriColors.brandEmerald
                    : AgriColors.surfaceCard,
                border: Border.all(
                  color: _filtre == filtre
                      ? AgriColors.brandEmerald
                      : AgriColors.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                filtre,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: _filtre == filtre ? Colors.white : AgriColors.outline,
                ),
              ),
            ),
          ),
          const SizedBox(width: AgriSpacing.xs),
        ],
      ],
    ),
  );

  Widget _tableau(List<LigneFacture> lignes) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1000,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in const [
                    ('N° Facture', 3),
                    ('Client', 4),
                    ('Date', 3),
                    ('Montant TTC', 3),
                    ('Statut MeCeF', 4),
                    ('Actions', 2),
                  ])
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  '— Aucune facture pour ces critères —',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (var i = 0; i < lignes.length; i++)
              Container(
                key: Key('ligne-$i'),
                color: i.isOdd
                    ? AgriColors.surfaceZebra
                    : AgriColors.surfaceCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _numero(lignes[i])),
                    Expanded(
                      flex: 4,
                      child: Text(
                        lignes[i].client,
                        overflow: TextOverflow.ellipsis,
                        style: _cellule,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _date(lignes[i].vente.soldAt),
                        style: _cellule,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _montant(lignes[i].vente.total),
                        style: const TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                        ),
                      ),
                    ),
                    Expanded(flex: 4, child: _pastilleStatut(lignes[i])),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          key: Key('voir-facture-$i'),
                          onPressed: () => _ouvrirFacture(lignes[i]),
                          icon: const Icon(SymbolesAgri.visibility, size: 16),
                          color: AgriColors.infoBlue,
                          tooltip: 'Facture Normalisee MeCeF',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// ⚠️⚠️ **AUCUN NUMÉRO DE FACTURE N'EXISTE DANS LE SCHÉMA.** La maquette
  /// affiche « FAC-2026-0042 » ; `sales` n'a pas de colonne de référence — le
  /// même constat que pour les achats et les ventes. Ce que la facture porte
  /// réellement, c'est sa référence MeCeF quand elle a été transmise : c'est
  /// donc elle qui s'affiche, et un tiret quand elle n'existe pas encore.
  /// **ARBITRAGE CLIENT** : ajouter une numérotation de facture ?
  Widget _numero(LigneFacture f) => Text(
    f.vente.mecefQrRef ?? '—',
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: AgriTypography.gras,
      color: f.vente.mecefQrRef == null
          ? AgriColors.outline
          : AgriColors.brandEmerald,
    ),
  );

  Widget _pastilleStatut(LigneFacture f) {
    final (couleur, libelle) = switch (f.statut) {
      StatutMecef.transmise => (AgriColors.brandEmerald, f.statut.libelle),
      StatutMecef.enAttente => (AgriColors.accentYellow, f.statut.libelle),
      StatutMecef.erreur => (AgriColors.errorRed, f.statut.libelle),
      StatutMecef.jamais => (
        AgriColors.outline,
        f.envoyee ? f.statut.libelle : 'Vente pas encore envoyée',
      ),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          libelle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: AgriTypography.gras,
            color: f.statut == StatutMecef.enAttente
                ? AgriColors.brandForest
                : couleur,
          ),
        ),
      ),
    );
  }

  /// La modale « Facture Normalisee MeCeF » de la maquette.
  ///
  /// ⚠️ **LE QR N'EST PAS DESSINÉ, SA RÉFÉRENCE EST AFFICHÉE.** Le code est
  /// produit par le dispositif MeCeF et imprimé sur la facture officielle par
  /// la surface web ; le poste n'a pas la chaîne d'édition. Dessiner un QR à
  /// partir de la seule référence produirait une image d'apparence officielle
  /// que rien ne certifie.
  void _ouvrirFacture(LigneFacture f) {
    afficherModale<void>(
      context: context,
      constructeur: (context) => ModaleAgri(
        titre: 'Facture Normalisee MeCeF',
        surtitre: f.client,
        contenu: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ligneDetail('Date', _date(f.vente.soldAt)),
            _ligneDetail('Montant TTC', '${_montant(f.vente.total)} FCFA'),
            _ligneDetail('Mode de paiement', f.vente.paymentMode),
            _ligneDetail('Statut MeCeF', f.statut.libelle),
            const SizedBox(height: AgriSpacing.sm),
            const Text(
              'RÉFÉRENCE MeCeF',
              style: TextStyle(
                fontSize: 10,
                fontWeight: AgriTypography.gras,
                color: AgriColors.outline,
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            SelectableText(
              f.vente.mecefQrRef ?? '— Facture non transmise —',
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                fontFamily: 'monospace',
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
            const SizedBox(height: AgriSpacing.sm),
            const Text(
              "Le code QR de la facture officielle est imprimé depuis la "
              'surface web : il est produit par le dispositif MeCeF, et le '
              'poste ne peut pas le certifier lui-même.',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _ligneDetail(String libelle, String valeur) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          libelle,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        Text(
          valeur,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
          ),
        ),
      ],
    ),
  );

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _mentionPoste(String texte) => Container(
    key: const Key('mention-poste'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
