import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/temps/heure_benin.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
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
    this.imprimer,
  });

  final FacturationRepository depot;

  /// Éditeur PDF du poste (la facture d'une vente, hors ligne) ; `null` : le bouton n'imprime rien.
  final Editeur? imprimer;

  /// Ouvre la caisse — seul point d'entrée réel d'une facture.
  final VoidCallback? onOuvrirCaisse;

  @override
  State<FacturationScreen> createState() => _FacturationScreenState();
}

class _FacturationScreenState extends State<FacturationScreen> {
  /// Filtres du web (`facturation.blade.php`, MECEF-1 : les libellés de `MecefEtat`), dans son ordre.
  static const filtres = <String>[
    'Tous les statuts',
    'Normalisée',
    'En attente',
    'Refusée',
    'Expirée',
  ];

  String _filtre = filtres.first;
  DonneesFacturation? _donnees;

  /// Ticket VC-5 — module MeCeF activé ? Sinon la page est un registre de factures simple (comme au web).
  bool _mecef = true;

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
    final donnees = await widget.depot.charger(
      mois: PorteeExerciceChoisi.lire(context)?.moisDeReference,
    );
    final mecef = await widget.depot.mecefActif();
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _mecef = mecef;
    });
  }

  Future<void> _imprimer(LigneFacture f) async {
    final editeur = widget.imprimer;
    if (editeur == null) return;
    String message;
    try {
      final doc = await widget.depot.documentFacture(f.vente.id);
      message = doc == null
          ? 'Facture introuvable.'
          : await editeur(doc, HeureBenin.maintenant()) ??
                'Facture envoyée à l’impression.';
    } catch (_) {
      message =
          'L’édition de la facture a échoué. Réessayez ou vérifiez l’imprimante.';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
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
                      if (_mecef) ...[
                        _barreFiltres(),
                        const SizedBox(height: AgriSpacing.md),
                      ],
                      // Ticket EX7 (EF9) — 25 factures par page, `<x-pagination>` du web sous le tableau.
                      _tableau(
                        PorteeExerciceChoisi.lire(context) == null
                            ? lignes
                            : PaginationAgri.tranche(lignes, _page),
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
                        _mecef
                            ? "Une facture naît d'une vente : elle se crée à la "
                                  'caisse, jamais ici. La transmission au dispositif '
                                  'MeCeF est faite par le serveur à la réception de la '
                                  'vente — un poste hors ligne ne peut pas joindre la '
                                  'DGI lui-même.'
                            : "Une facture naît d'une vente : elle se crée à la caisse, jamais ici. "
                                  "La certification MeCeF n'est pas activée : la facture s'imprime en PDF, sans référence MeCeF.",
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
      const Icon(
        SymbolesAgri.receipt_long,
        size: 26,
        color: AgriColors.brandEmerald,
      ),
      const SizedBox(width: AgriSpacing.xs),
      Expanded(
        child: Text(
          _mecef ? 'Facturation & MeCeF' : 'Facturation',
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

  Widget _grilleKpis(bool large, DonneesFacturation d) => !_mecef
      ? GrilleKpi(
          colonnes: large ? 3 : 1,
          children: [
            CarteKpi(
              libelle: 'Factures (mois)',
              valeur: '${d.duMois.length}',
              couleurLisere: AgriColors.brandEmerald,
              icone: SymbolesAgri.receipt_long,
            ),
            CarteKpi(
              libelle: 'Montant facturé (mois)',
              valeur: '${_montant(d.montantDuMois)} FCFA',
              couleurLisere: AgriColors.infoBlue,
              icone: SymbolesAgri.payments,
              couleurIcone: AgriColors.infoBlue,
            ),
            CarteKpi(
              libelle: 'Clients facturés (mois)',
              valeur:
                  '${{for (final f in d.duMois)
                    if (f.vente.customerId != null) f.vente.customerId}.length}',
              couleurLisere: AgriColors.accentYellow,
              icone: SymbolesAgri.group,
              couleurIcone: AgriColors.brandForest,
            ),
          ],
        )
      : GrilleKpi(
          colonnes: large ? 4 : 2,
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
              valeur: '${d.compte(StatutMecef.erreur) + d.compte(StatutMecef.expiree)}',
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
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(1000, contraintes.maxWidth),
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
                      if (_mecef || libelle != 'Statut MeCeF')
                      Expanded(
                        flex: flex,
                        child: Text(
                          libelle.toUpperCase(),
                          style: _enteteColonne,
                        ),
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
                      Expanded(
                        flex: 3,
                        child: _mecef
                            ? _numero(lignes[i])
                            : _numeroFacture(lignes[i]),
                      ),
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
                      if (_mecef)
                        Expanded(flex: 4, child: _statutAvecMotif(lignes[i])),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('imprimer-facture-$i'),
                                onPressed: () => _imprimer(lignes[i]),
                                icon: const Icon(
                                  SymbolesAgri.picture_as_pdf,
                                  size: 16,
                                ),
                                color: AgriColors.brandEmerald,
                                tooltip: 'Imprimer la facture (PDF)',
                              ),
                              if (_mecef)
                                IconButton(
                                  key: Key('voir-facture-$i'),
                                  onPressed: () => _ouvrirFacture(lignes[i]),
                                  icon: const Icon(
                                    SymbolesAgri.visibility,
                                    size: 16,
                                  ),
                                  color: AgriColors.infoBlue,
                                  tooltip: 'Facture Normalisee MeCeF',
                                ),
                            ],
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

  Widget _numeroFacture(LigneFacture f) => Text(
    f.numero,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandEmerald,
    ),
  );

  /// MECEF-1 — la pastille, et sous elle le MOTIF (français, venu de la DGI ou de la passerelle) d'une facture en attente,
  /// refusée ou expirée : comme `facturation.blade.php`.
  Widget _statutAvecMotif(LigneFacture f) {
    final motif = f.statut == StatutMecef.transmise ? null : f.vente.mecefMessage;
    if (motif == null || motif.isEmpty) return _pastilleStatut(f);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _pastilleStatut(f),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            motif,
            key: Key('motif-mecef-${f.vente.id}'),
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  Widget _pastilleStatut(LigneFacture f) {
    final (couleur, libelle) = switch (f.statut) {
      StatutMecef.transmise => (AgriColors.brandEmerald, f.statut.libelle),
      StatutMecef.enAttente => (AgriColors.accentYellow, f.statut.libelle),
      StatutMecef.erreur => (AgriColors.errorRed, f.statut.libelle),
      StatutMecef.expiree => (AgriColors.errorRed, f.statut.libelle),
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

  /// La modale « Facture Normalisee MeCeF ».
  ///
  /// MECEF-1 — le QR est DESSINÉ à partir de la DONNÉE renvoyée par la DGI (`mecef_qr_ref`, jamais construite au poste) :
  /// il n'y en a un que pour une facture NORMALISÉE ; une facture en attente, refusée ou expirée ne montre ni QR ni
  /// mention inventée, mais son motif. Les mentions (code MeCeF/DGI, NIM, compteurs, date) sont celles de la DGI.
  void _ouvrirFacture(LigneFacture f) {
    final v = f.vente;
    final le = v.mecefNormaliseLe;
    String heure(DateTime d) =>
        '${_date(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    afficherModale<void>(
      context: context,
      constructeur: (context) => ModaleAgri(
        titre: 'Facture Normalisee MeCeF',
        surtitre: f.client,
        contenu: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ligneDetail('Date', _date(v.soldAt)),
            _ligneDetail('Montant TTC', '${_montant(v.total)} FCFA'),
            _ligneDetail('Mode de paiement', v.paymentMode),
            _ligneDetail('Statut MeCeF', f.statut.libelle),
            if (f.normalisee && (v.mecefCode ?? '').isNotEmpty) _ligneDetail('Code MeCeF/DGI', v.mecefCode!),
            if (f.normalisee && (v.mecefNim ?? '').isNotEmpty) _ligneDetail('NIM', v.mecefNim!),
            if (f.normalisee && (v.mecefCompteurs ?? '').isNotEmpty) _ligneDetail('Compteurs', v.mecefCompteurs!),
            if (f.normalisee && le != null) _ligneDetail('Normalisée le', heure(le)),
            if (!f.normalisee && (v.mecefMessage ?? '').isNotEmpty) _ligneDetail('Motif', v.mecefMessage!),
            const SizedBox(height: AgriSpacing.sm),
            if (f.normalisee && v.mecefQrRef != null) ...[
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(AgriSpacing.sm),
                  child: QrImageView(key: const Key('qr-facture'), data: v.mecefQrRef!, size: 180),
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              SelectableText(
                v.mecefQrRef!,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontFamily: 'monospace',
                  color: AgriColors.outline,
                ),
              ),
            ] else
              const Text(
                'Aucune référence MeCeF disponible pour cette facture.',
                style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
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
        const SizedBox(width: AgriSpacing.sm),
        // MECEF-1 : un motif français peut être long — il passe à la ligne au lieu de déborder.
        Flexible(
          child: Text(
            valeur,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
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
