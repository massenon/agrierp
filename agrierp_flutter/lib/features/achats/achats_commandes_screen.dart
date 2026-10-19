import 'package:flutter/material.dart';

import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import 'achats_modales.dart';
import 'achats_repository.dart';
import 'fournisseurs_repository.dart';
import 'profil_fournisseur_screen.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/achats-commandes.html` → Achats & Commandes.
///
/// ⚠️⚠️ **HUB À TROIS ONGLETS**, dans l'ordre du hub : Enregistrer un Achat ·
/// Liste d'Achats · Bons de Commande — chargés en `<iframe>` par la maquette
/// (`enregistrer-achat`, `liste-achats`, `bons-commande`).
///
/// ⚠️⚠️ **LE PREMIER ONGLET ÉCRIT VRAIMENT, ET LE POSTE N'APPLIQUE RIEN.**
/// L'achat est enregistré localement `pending` ; ses cinq effets — entrée en
/// stock avec recalcul du PMP, décaissement, dette fournisseur, écriture
/// SYSCOHADA — sont rejoués par le SERVEUR à la réception. Un stock décrémenté
/// ici ferait diverger deux valorisations, et le PMP du poste ne vaudrait plus
/// rien. Tant que l'envoi n'a pas eu lieu, la ligne porte « En attente de
/// synchronisation » : la ferme, elle, ne connaît pas encore cet achat.
///
/// ⚠️ **LES LIBELLÉS SANS ACCENT SONT CEUX DE LA MAQUETTE** — « Selectionner
/// Fournisseur », « Quantite », « Compte Debite », « Montant Paye », « Qte »,
/// « Reference ». `enregistrer-achat.html` ne les accentue pas là où les autres
/// pages le font. Les accentuer serait harmoniser en silence une incohérence du
/// template : elle rejoint l'arbitrage client déjà ouvert sur les huit `<th>`
/// de `gestion-stocks.html`.
///
/// ⚠️ **LE DÉTAIL, L'IMPRESSION ET L'EXPORT SONT EN LECTURE SEULE (ticket F0.75)** :
/// « Détail de l'Achat » (modale, là où la maquette ouvre un tiroir), « Exporter PDF » et
/// « Imprimer » passent par `ExportOfficiel`, effets injectés par [imprimer].
///
/// ⚠️⚠️ **RETOUR FOURNISSEUR ET REMBOURSEMENT S'ÉCRIVENT AU POSTE DEPUIS F0.74, ET LE POSTE
/// N'ENREGISTRE QUE LA DEMANDE** : `pending`, puis synchronisé. Le SERVEUR choisit les
/// lignes concernées, décrémente le stock, contre-passe l'écriture, annule la dette, plafonne
/// le remboursement et passe l'écriture — et il peut REFUSER (achat sans écriture d'origine,
/// stock insuffisant, exercice clos) : son motif s'affiche mot pour mot sur la ligne.
class AchatsCommandesScreen extends StatefulWidget {
  const AchatsCommandesScreen({
    super.key,
    required this.depot,
    this.depotFournisseurs,
    this.imprimer,
    this.maintenant,
  });

  final AchatsRepository depot;

  /// Ouvre le profil du fournisseur depuis le détail (le lien de la maquette,
  /// `profile-fournisseur.html`). Absent : le nom s'affiche sans lien.
  final FournisseursRepository? depotFournisseurs;

  /// Éditeur injecté — `EditeursRapports.imprimer` en production, un espion en
  /// test. Absent : les boutons d'édition ne font rien (comme à l'écran des
  /// rapports).
  final Editeur? imprimer;

  /// Horloge injectée : un document daté par `DateTime.now()` ne se comparerait
  /// pas d'une exécution à l'autre.
  final DateTime Function()? maintenant;

  @override
  State<AchatsCommandesScreen> createState() => _AchatsCommandesScreenState();
}

class _AchatsCommandesScreenState extends State<AchatsCommandesScreen> {
  /// Les trois onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Enregistrer un Achat', SymbolesAgri.add_shopping_cart),
    ("Liste d'Achats", SymbolesAgri.receipt_long),
    ('Bons de Commande', SymbolesAgri.assignment),
  ];

  /// Modes de paiement — **les trois de la maquette** (l.174-177), avec ses
  /// libellés exacts, associés aux valeurs de l'enum serveur.
  ///
  /// ⚠️ `credit` EXISTE CÔTÉ SERVEUR ET LA MAQUETTE NE L'OFFRE PAS. Un achat à
  /// crédit s'exprime ici par un « Montant Paye » inférieur au total, qui ouvre
  /// une dette fournisseur. L'ajouter à la liste serait inventer une option que
  /// le commanditaire n'a pas validée. **ARBITRAGE CLIENT.**
  static const modesPaiement = <(String, String)>[
    ('especes', 'Caisse (Especes)'),
    ('virement', 'Virement Bancaire'),
    ('mobile_money', 'Mobile Money'),
  ];

  String _onglet = onglets.first.$1;

  String? _fournisseurId;
  String? _produitId;
  String _modePaiement = 'especes';
  String? _compteId;

  final _quantite = TextEditingController();
  final _prixUnitaire = TextEditingController();
  final _montantPaye = TextEditingController();

  final List<LigneSaisieAchat> _panier = [];

  DonneesAchats? _donnees;
  String? _message;
  bool _messageEstUneErreur = false;

  /// Fournisseur dont le profil est ouvert depuis le détail d'un achat ;
  /// `null` : le hub.
  String? _profilFournisseur;

  DateTime get _maintenant => (widget.maintenant ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _quantite.dispose();
    _prixUnitaire.dispose();
    _montantPaye.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;

    setState(() {
      _donnees = donnees;
      // ⚠️ NI FOURNISSEUR NI PRODUIT PRÉSÉLECTIONNÉS : la maquette ouvre ses
      // deux listes sur « Choisir… » (l.107, l.126). Présélectionner ferait
      // enregistrer un achat au premier fournisseur de la liste pour qui
      // enchaînerait les champs sans regarder.
      _compteId ??= donnees.comptes.isEmpty ? null : donnees.comptes.first.id;
    });
  }

  double get _totalPanier => _panier.fold<double>(0, (t, l) => t + l.total);

  void _ajouterAuPanier(DonneesAchats d) {
    final produit = d.produits.where((p) => p.id == _produitId).firstOrNull;
    final quantite = double.tryParse(_quantite.text.replaceAll(',', '.')) ?? 0;
    final prix = double.tryParse(_prixUnitaire.text.replaceAll(',', '.')) ?? 0;

    if (produit == null || quantite <= 0) {
      setState(() {
        _message = 'Choisissez un article et une quantité supérieure à zéro.';
        _messageEstUneErreur = true;
      });
      return;
    }

    setState(() {
      _panier.add(
        LigneSaisieAchat(
          produit: produit,
          quantite: quantite,
          prixUnitaire: prix,
        ),
      );
      _quantite.clear();
      _prixUnitaire.clear();
      _message = null;
    });
  }

  Future<void> _enregistrer() async {
    if (_fournisseurId == null) {
      setState(() {
        _message = 'Choisissez le fournisseur de cet achat.';
        _messageEstUneErreur = true;
      });
      return;
    }

    if (_panier.isEmpty || _compteId == null) {
      setState(() {
        _message = "Ajoutez au moins un article au bon d'achat.";
        _messageEstUneErreur = true;
      });
      return;
    }

    final paye = double.tryParse(_montantPaye.text.replaceAll(',', '.')) ?? 0;

    await widget.depot.enregistrer(
      fournisseurId: _fournisseurId!,
      lignes: List.of(_panier),
      modePaiement: _modePaiement,
      compteId: _compteId!,
      montantPaye: paye,
    );

    if (!mounted) return;

    setState(() {
      _panier.clear();
      _montantPaye.clear();
      _message =
          'Achat enregistré sur ce poste — il partira à la prochaine '
          'synchronisation.';
      _messageEstUneErreur = false;
    });

    await _charger();
  }

  // ── Liste d'Achats : détail, impression ───────────────────────────────────

  /// « Exporter PDF » — la liste entière, comme `exportAchatsPDF()`.
  ///
  /// ⚠️ Une liste vide n'est pas éditée : un document réduit à son en-tête
  /// ressemble à un rapport « rien à signaler » alors que le poste n'a
  /// simplement aucun achat.
  Future<void> _exporterListe(DonneesAchats d) async {
    if (d.achats.isEmpty) {
      _annoncer('Aucun achat à exporter.');
      return;
    }
    await _editer(DocumentsAchats.liste(d.achats));
  }

  Future<void> _editer(DocumentOfficiel document) async {
    final editeur = widget.imprimer;
    if (editeur == null) return;

    final message = await editeur(document, _maintenant);
    _annoncer(message ?? 'Document envoyé à l’impression.');
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
        backgroundColor: AgriColors.brandEmerald,
      ),
    );
  }

  /// « Détail de l'Achat » : ouvert depuis l'œil de la ligne.
  Future<void> _voir(LigneAchat ligne) async {
    final ouvrir = await afficherModale<String>(
      context: context,
      constructeur: (contexte) => ModaleAgri(
        titre: "Détail de l'Achat",
        contenu: _detailAchat(contexte, ligne),
        actions: [
          // « Retour Fournisseur » du tiroir (bouton rouge). Absent quand un retour est
          // déjà engagé : le serveur masque le sien de la même façon.
          if (ligne.retournable)
            ElevatedButton.icon(
              key: const Key('detail-retour'),
              onPressed: () => Navigator.of(contexte).pop('retour'),
              icon: const Icon(SymbolesAgri.cancel, size: 16),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.errorRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
              label: const Text(
                'Retour Fournisseur',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                ),
              ),
            ),
          OutlinedButton.icon(
            key: const Key('detail-imprimer'),
            onPressed: () {
              Navigator.of(contexte).pop('imprimer');
              _editer(DocumentsAchats.bonReception(ligne));
            },
            icon: const Icon(SymbolesAgri.print, size: 16),
            style: OutlinedButton.styleFrom(
              foregroundColor: AgriColors.brandForest,
              side: const BorderSide(color: AgriColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
            label: const Text(
              'Imprimer',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (ouvrir == 'fournisseur') {
      setState(() => _profilFournisseur = ligne.achat.supplierId);
    } else if (ouvrir == 'retour') {
      await _demanderRetour(ligne);
    }
  }

  /// « Retour Fournisseur » : la modale écrit la DEMANDE (`pending`) ; rien d'autre ne
  /// bouge au poste.
  Future<void> _demanderRetour(LigneAchat ligne) async {
    final ecrit = await ouvrirRetourFournisseur(
      context: context,
      depot: widget.depot,
      ligne: ligne,
    );
    if (!ecrit || !mounted) return;
    _annoncer(
      'Retour demandé : il part à la prochaine synchronisation. Le serveur '
      'choisit les lignes concernées et peut le refuser.',
    );
    await _charger();
  }

  Future<void> _demanderRemboursement(DonneesAchats d) async {
    final ecrit = await ouvrirRemboursement(
      context: context,
      depot: widget.depot,
      donnees: d,
    );
    if (!ecrit || !mounted) return;
    _annoncer(
      'Remboursement enregistré : il part à la prochaine synchronisation. Le '
      'serveur le plafonne à la créance ouverte et peut le refuser.',
    );
    await _charger();
  }

  /// Les trois blocs du tiroir de la maquette, dans son ordre.
  Widget _detailAchat(BuildContext contexte, LigneAchat ligne) {
    final a = ligne.achat;
    final nom = a.supplierName;

    return Column(
      key: const Key('detail-achat'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _blocDetail('Informations générales', [
          _rangeeDetail('Référence', DocumentsAchats.inconnu),
          _rangeeDetail('Date', AchatsRepository.jour(a.purchaseDate)),
          _rangeeDetail('Opérateur', DocumentsAchats.inconnu),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _blocDetail('Fiche Fournisseur', [
          if (nom != null && widget.depotFournisseurs != null)
            InkWell(
              key: const Key('detail-fournisseur'),
              onTap: () => Navigator.of(contexte).pop('fournisseur'),
              child: Text(
                nom,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandEmerald,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else
            Text(
              nom ?? DocumentsAchats.inconnu,
              key: const Key('detail-fournisseur'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
              ),
            ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _blocDetail('Détails Financiers', [
          _rangeeDetail(
            'Montant Total',
            '${AchatsRepository.montant(a.total)} FCFA',
            gras: true,
          ),
          _rangeeDetail('TVA Récupérable (18%)', DocumentsAchats.inconnu),
          _rangeeDetail('Statut', ligne.statut, gras: true),
        ]),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ La légende des tirets : sans elle, « — » se lirait « zéro ».
        _mentionPoste(
          "« — » : le poste ne détient pas cette information. Aucune "
          "référence d'achat ni opérateur ne descend du serveur ; la TVA "
          'récupérable se ventile là-bas, ligne par ligne, selon le taux de '
          'chaque produit.',
          cle: const Key('legende-detail-achat'),
        ),
      ],
    );
  }

  Widget _blocDetail(String titre, List<Widget> rangees) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _etiquette(titre),
      Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceZebra,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rangees,
        ),
      ),
    ],
  );

  Widget _rangeeDetail(String libelle, String valeur, {bool gras = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
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
            Flexible(
              child: Text(
                valeur,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: gras ? AgriTypography.gras : null,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    // Le lien « Fiche Fournisseur » du détail : le profil existant, avec son
    // Retour — comme depuis « Fiches Fournisseurs ».
    final depotFournisseurs = widget.depotFournisseurs;
    if (_profilFournisseur != null && depotFournisseurs != null) {
      return ProfilFournisseurScreen(
        depot: depotFournisseurs,
        fournisseurId: _profilFournisseur!,
        onRetour: () {
          setState(() => _profilFournisseur = null);
          _charger();
        },
      );
    }

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        "Liste d'Achats" => _ongletListe(d, large),
                        'Bons de Commande' => _ongletBons(d, large),
                        _ => _ongletSaisie(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-achats-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Onglet 1 : Enregistrer un Achat ───────────────────────────────────────

  Widget _ongletSaisie(DonneesAchats d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Enregistrer un Achat', large),
      const SizedBox(height: AgriSpacing.md),
      if (large)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 60, child: _panneauArticles(d)),
              const SizedBox(width: AgriSpacing.md),
              Expanded(flex: 40, child: _panneauReglement(d)),
            ],
          ),
        )
      else ...[
        _panneauArticles(d),
        const SizedBox(height: AgriSpacing.md),
        _panneauReglement(d),
      ],
      if (_message != null) ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_message!, _messageEstUneErreur),
      ],
      const SizedBox(height: AgriSpacing.lg),
      Text(
        'Achats Recemment Enregistres',
        style: TextStyle(
          fontSize: large ? AgriTypography.lg : AgriTypography.base,
          fontWeight: AgriTypography.gras,
          color: AgriColors.onSurface,
        ),
      ),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        largeur: 900,
        colonnes: const [
          ('Reference', 3),
          ('Fournisseur', 4),
          ('Date', 3),
          ('Montant', 3),
          ('Statut', 4),
          ('Actions', 2),
        ],
        vide: '— Aucun achat enregistré —',
        lignes: [
          for (var i = 0; i < d.achats.take(5).length; i++)
            _ligne(i, [
              (_reference(), 3),
              (
                Text(
                  d.achats[i].achat.supplierName ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (Text(_date(d.achats[i].achat.purchaseDate), style: _cellule), 3),
              (Text(_montant(d.achats[i].achat.total), style: _cellule), 3),
              (_statut(d.achats[i], 'saisie-$i'), 4),
              (_actionInerte(), 2),
            ]),
        ],
      ),
    ],
  );

  Widget _panneauArticles(DonneesAchats d) => _carte(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette('Selectionner Fournisseur'),
        _liste(
          cle: 'fournisseur',
          valeur: _fournisseurId,
          options: [for (final f in d.fournisseurs) (f.id, f.name)],
          vide: '— Aucun fournisseur synchronisé —',
          invite: 'Choisir le fournisseur...',
          onChanged: (v) => setState(() => _fournisseurId = v),
        ),
        const SizedBox(height: AgriSpacing.md),
        _etiquette('Ajouter un Article'),
        _etiquettePetite('Produit / Article'),
        _liste(
          cle: 'produit',
          valeur: _produitId,
          options: [for (final p in d.produits) (p.id, p.name)],
          vide: '— Aucun produit synchronisé —',
          invite: 'Choisir un produit...',
          onChanged: (v) => setState(() => _produitId = v),
        ),
        const SizedBox(height: AgriSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiquettePetite('Quantite'),
                  _champ('quantite', _quantite),
                ],
              ),
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiquettePetite('Prix Unitaire'),
                  _champ('prix-unitaire', _prixUnitaire),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        OutlinedButton.icon(
          key: const Key('ajouter-au-bon'),
          onPressed: () => _ajouterAuPanier(d),
          icon: const Icon(SymbolesAgri.add_circle_outline, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandEmerald,
            side: const BorderSide(color: AgriColors.brandEmerald, width: 2),
            padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
          ),
          label: const Text(
            "Ajouter au bon d'achat",
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 520,
          // ⚠️⚠️ **CINQ COLONNES, PAS QUATRE — ET LA CINQUIÈME RETIRE UNE
          // LIGNE.** La maquette ferme son en-tête par un `<th></th>` vide
          // (`enregistrer-achat.html` l.155) : c'est la colonne du bouton de
          // suppression. Elle manquait ici, et avec elle **le seul moyen de
          // corriger une ligne ajoutée par erreur** — il fallait enregistrer
          // un achat faux pour vider le bon. Ni le contrôle de vocabulaire
          // (une en-tête vide n'a pas de mot) ni un test de rendu ne
          // pouvaient le voir : trouvé en comparant la SUITE ORDONNÉE des
          // colonnes à celle de la maquette (ticket F0.49).
          colonnes: const [
            ('Designation', 5),
            ('Qte', 2),
            ('P.U', 3),
            ('Total', 3),
            ('', 2),
          ],
          vide: "— Le bon d'achat est vide —",
          lignes: [
            for (var i = 0; i < _panier.length; i++)
              _ligne(i, [
                (
                  Text(
                    _panier[i].produit.name,
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  5,
                ),
                (Text(_nombre(_panier[i].quantite), style: _cellule), 2),
                (Text(_montant(_panier[i].prixUnitaire), style: _cellule), 3),
                (
                  Text(
                    _montant(_panier[i].total),
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                  3,
                ),
                (
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: Key('retirer-ligne-$i'),
                      onPressed: () => setState(() => _panier.removeAt(i)),
                      icon: const Icon(SymbolesAgri.delete_outline, size: 16),
                      color: AgriColors.errorDeep,
                      tooltip: 'Retirer du bon',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  2,
                ),
              ]),
          ],
        ),
      ],
    ),
  );

  Widget _panneauReglement(DonneesAchats d) => _carte(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TOTAL',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.outline,
              ),
            ),
            Text(
              '${_montant(_totalPanier)} FCFA',
              key: const Key('total-achat'),
              style: const TextStyle(
                fontSize: AgriTypography.xl,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _etiquette('Mode de Paiement'),
        _liste(
          cle: 'mode-paiement',
          valeur: _modePaiement,
          options: modesPaiement,
          vide: '—',
          onChanged: (v) => setState(() => _modePaiement = v ?? 'especes'),
        ),
        const SizedBox(height: AgriSpacing.sm),
        _etiquette('Compte Debite'),
        _liste(
          cle: 'compte',
          valeur: _compteId,
          options: [for (final c in d.comptes) (c.id, c.label)],
          vide: '— Aucun compte synchronisé —',
          onChanged: (v) => setState(() => _compteId = v),
        ),
        const SizedBox(height: AgriSpacing.sm),
        _etiquette('Montant Paye (FCFA)'),
        _champ('montant-paye', _montantPaye),
        const SizedBox(height: AgriSpacing.md),
        FilledButton.icon(
          key: const Key('enregistrer-achat'),
          onPressed: _enregistrer,
          icon: const Icon(SymbolesAgri.save, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
            padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
          ),
          label: const Text(
            "Enregistrer l'Achat",
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        // ⚠️ « Piece Justificative » de la maquette (l.192) : le poste n'a ni
        // sélecteur de fichier ni canal d'envoi de pièce jointe. Promettre le
        // champ ferait croire la photo du reçu enregistrée.
        _mentionPoste(
          "La pièce justificative se joint depuis la surface web : le poste "
          "n'a pas de canal d'envoi de fichier. L'achat, lui, part avec sa "
          'date de saisie.',
        ),
      ],
    ),
  );

  // ── Onglet 2 : Liste d'Achats ─────────────────────────────────────────────

  Widget _ongletListe(DonneesAchats d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AgriSpacing.sm,
        children: [
          _titre("Liste d'Achats", large),
          Wrap(
            spacing: AgriSpacing.xs,
            runSpacing: AgriSpacing.xs,
            children: [
              FilledButton.icon(
                key: const Key('exporter-pdf-achats'),
                onPressed: () => _exporterListe(d),
                icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AgriColors.brandEmerald,
                  shape: const StadiumBorder(),
                ),
                label: const Text(
                  'Exporter PDF',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
              ),
              // « Ajouter Remboursement » : bouton blanc à texte rouge (`text-error-deep`).
              OutlinedButton.icon(
                key: const Key('ajouter-remboursement'),
                onPressed: () => _demanderRemboursement(d),
                icon: const Icon(SymbolesAgri.payments, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgriColors.errorDeep,
                  side: const BorderSide(color: AgriColors.outlineVariant),
                  shape: const StadiumBorder(),
                ),
                label: const Text(
                  'Ajouter Remboursement',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES QUATRE CARTES DE `liste-achats.html`, dans son ordre et avec ses
      // couleurs : `payments` émeraude, `task_alt` bleu, `warning` rouge,
      // `assignment_return` jaune. Trouvées manquantes par le comptage du
      // ticket F0.54.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-achats-depenses'),
          libelle: 'Dépenses Totales',
          valeur: _montant(d.depensesTotales),
          unite: 'FCFA',
          // ⚠️ COMME LE SERVEUR : la page web somme TOUS les achats, retournés compris
          // (constat 3 du ticket 15.20, non corrigé). Le poste ne s'en écarte pas — deux
          // surfaces d'une même ferme afficheraient deux totaux — mais le DIT.
          legende: d.achatsRetournes.isEmpty
              ? null
              : 'dont ${_montant(d.depensesRetournees)} FCFA retournés '
                    '(comptés comme sur le serveur)',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.payments,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-achats-regles'),
          libelle: 'Achats Réglés',
          valeur: '${d.achatsRegles}',
          legende: 'Statut arrêté par le serveur',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.task_alt,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-achats-dettes'),
          libelle: 'Dettes en Cours',
          // ⚠️ F0.77 : reste dû lu sur les dettes servies ; inconnu = tiret, jamais 0.
          valeur: d.dettesEnCours == null ? '—' : _montant(d.dettesEnCours!),
          unite: d.dettesEnCours == null ? null : 'FCFA',
          legende: d.dettesEnCours == null
              ? "${d.achatsEndettesSansDette} achat(s) endetté(s) sans dette "
                    "servie par le serveur : reste dû inconnu du poste"
              : null,
          couleurLisere: AgriColors.errorRed,
          icone: SymbolesAgri.warning,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-achats-ecarts'),
          libelle: 'Écarts / Retours',
          // ⚠️ CALCULABLE DEPUIS F0.74 (`returned_at` descend, les retours du poste sont
          // acquittés) : plus de tiret. Des ACHATS retournés, pas des lignes de retour
          // comme sur la page web — `purchase_returns` ne descend pas.
          valeur: '${d.ecartsEtRetours}',
          legende: d.retoursEnAttente > 0
              ? 'achats retournés · ${d.retoursEnAttente} demande(s) en attente '
                    "d'envoi, non comptée(s)"
              : 'achats retournés',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.assignment_return,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1050,
        colonnes: const [
          ('Référence Achat', 3),
          ('Date', 3),
          ('Fournisseur', 4),
          ('Catégorie', 3),
          ('Montant Total', 3),
          ('Statut', 4),
          ('Actions', 3),
        ],
        vide: '— Aucun achat pour ces critères —',
        lignes: [
          for (var i = 0; i < d.achats.length; i++)
            _ligne(i, [
              (_reference(), 3),
              (Text(_date(d.achats[i].achat.purchaseDate), style: _cellule), 3),
              (
                Text(
                  d.achats[i].achat.supplierName ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  d.achats[i].achat.supplierCategory ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  _montant(d.achats[i].achat.total),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                3,
              ),
              (_statut(d.achats[i], 'liste-$i'), 4),
              (_actionsAchat(d.achats[i], i), 3),
            ]),
        ],
      ),
      if (d.remboursements.any(
        (r) => r.remboursement.syncStatus != SyncStatus.synced,
      )) ...[
        const SizedBox(height: AgriSpacing.md),
        _remboursementsDuPoste(d),
      ],
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        'Retour fournisseur et remboursement : le poste enregistre la '
        'DEMANDE, le serveur l’applique à la synchronisation. Pour un retour, '
        'c’est lui qui choisit les lignes concernées, décrémente le stock, '
        'contre-passe l’écriture et annule la dette — et il peut refuser '
        "(achat sans écriture d'origine, stock insuffisant, exercice clos) : "
        'son motif s’affiche alors sur la ligne, mot pour mot. L’import '
        "d'achats par fichier n'est pas embarqué (le serveur n'en a pas).",
        cle: const Key('mention-retours'),
      ),
    ],
  );

  /// Remboursements saisis ici et PAS ENCORE acquittés par le serveur : en attente, ou
  /// refusés (avec le motif du serveur, mot pour mot). Un remboursement acquitté a rejoint la
  /// créance servie : il n'a plus rien à dire ici.
  Widget _remboursementsDuPoste(DonneesAchats d) => _carte(
    Column(
      key: const Key('remboursements-poste'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette('Remboursements du poste'),
        for (final r in d.remboursements)
          if (r.remboursement.syncStatus != SyncStatus.synced)
            Padding(
              key: Key('remboursement-${r.remboursement.id}'),
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.nomFournisseur ?? '—'} · '
                    '${_montant(r.remboursement.amount)} FCFA · '
                    '${_date(r.remboursement.refundDate)}',
                    style: _cellule,
                  ),
                  const SizedBox(height: 2),
                  _pastille(
                    r.remboursement.syncStatus == SyncStatus.pending
                        ? 'Remboursement en attente'
                        : 'Remboursement refusé par le serveur',
                    r.remboursement.syncStatus == SyncStatus.pending
                        ? AgriColors.accentYellow
                        : AgriColors.errorRed,
                    Key('pastille-remboursement-${r.remboursement.id}'),
                  ),
                  if (r.motifRefus != null)
                    Text(
                      r.motifRefus!,
                      key: Key('motif-remboursement-${r.remboursement.id}'),
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        color: AgriColors.errorDeep,
                      ),
                    ),
                ],
              ),
            ),
      ],
    ),
  );

  // ── Onglet 3 : Bons de Commande ───────────────────────────────────────────

  Widget _ongletBons(DonneesAchats d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Bons de Commande', large),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1050,
        colonnes: const [
          ('Réf Commande', 3),
          ("Date d'Émission", 3),
          ('Livraison Attendue', 3),
          ('Fournisseur', 4),
          ('Montant Estimé', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun bon de commande synchronisé —',
        lignes: [
          for (var i = 0; i < d.bonsCommande.length; i++)
            _ligne(i, [
              (_reference(), 3),
              (Text(_date(d.bonsCommande[i].createdAt), style: _cellule), 3),
              (
                Text(
                  _date(d.bonsCommande[i].expectedDeliveryDate),
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  d.bonsCommande[i].supplierName ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  _montant(d.bonsCommande[i].estimatedTotal),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                3,
              ),
              (
                Text(
                  d.bonsCommande[i].status ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LA SAISIE D'UN BON DE COMMANDE N'EST PAS PORTÉE. Un bon engage la
      // ferme auprès d'un fournisseur : le serveur le sert en LECTURE SEULE et
      // ignore tout envoi le concernant. Un bon saisi ici serait effacé au
      // tirage suivant — et le fournisseur aurait été appelé pour rien.
      _mentionPoste(
        "La saisie d'un bon de commande et la validation d'une réception se "
        'font sur la surface web : le serveur sert les bons en lecture seule. '
        'Le poste les affiche pour que la livraison attendue soit connue au '
        'magasin.',
      ),
    ],
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  /// ⚠️⚠️ **AUCUNE RÉFÉRENCE D'ACHAT N'EXISTE DANS LE SCHÉMA.** La maquette
  /// affiche « ACH-2026-101 » ; `purchases` n'a pas de colonne de référence, ni
  /// au poste ni sur le serveur — exactement comme les ventes (ticket 14.71).
  /// Fabriquer un numéro ici en inventerait un que la ferme ne retrouverait sur
  /// aucun document. **ARBITRAGE CLIENT.**
  Widget _reference() => const Text('—', style: _cellule);

  Widget _pastille(String texte, Color couleur, Key cle) => Container(
    key: cle,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.sm,
      vertical: 2,
    ),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      texte,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: AgriTypography.gras,
        color: couleur == AgriColors.accentYellow
            ? AgriColors.brandForest
            : couleur,
      ),
    ),
  );

  /// Statut de la ligne, plus — depuis F0.74 — l'état du RETOUR demandé au poste :
  /// « Retourné » (le serveur l'a appliqué ou acquitté), pastille « Retour en attente »
  /// (saisi ici, pas encore reçu), « Retour refusé par le serveur » + son motif mot pour mot.
  Widget _statut(LigneAchat ligne, String prefixe) {
    final couleur = ligne.refuse
        ? AgriColors.errorRed
        : ligne.retourne
        ? AgriColors.outline
        : !ligne.envoye
        ? AgriColors.accentYellow
        : (ligne.achat.hasDebt ? AgriColors.errorRed : AgriColors.brandEmerald);

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pastille(ligne.statut, couleur, Key('statut-$prefixe')),
          // ⚠️ F0.77 : achat refusé au push — motif du serveur mot pour mot.
          if (ligne.refuse && ligne.motifRefusAchat != null)
            Text(
              ligne.motifRefusAchat!,
              key: Key('motif-achat-$prefixe'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          if (ligne.retourEnAttente) ...[
            const SizedBox(height: 2),
            _pastille(
              'Retour en attente',
              AgriColors.accentYellow,
              Key('pastille-retour-$prefixe'),
            ),
          ],
          if (ligne.retourRefuse) ...[
            const SizedBox(height: 2),
            _pastille(
              'Retour refusé par le serveur',
              AgriColors.errorRed,
              Key('pastille-retour-$prefixe'),
            ),
            if (ligne.motifRefusRetour != null)
              Text(
                ligne.motifRefusRetour!,
                key: Key('motif-retour-$prefixe'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.errorDeep,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _grilleKpis(bool large, List<Widget> cartes) => GridView.count(
    crossAxisCount: large ? cartes.length : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: cartes,
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _carte(Widget contenu) => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: contenu,
  );

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: AgriTypography.gras,
        color: AgriColors.outline,
      ),
    ),
  );

  Widget _etiquettePetite(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 9,
        fontWeight: AgriTypography.gras,
        color: AgriColors.outline,
      ),
    ),
  );

  Widget _liste({
    required String cle,
    required String? valeur,
    required List<(String, String)> options,
    required String vide,
    required ValueChanged<String?> onChanged,
    String? invite,
  }) {
    if (options.isEmpty) {
      return Text(
        vide,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          fontStyle: FontStyle.italic,
          color: AgriColors.outline,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: Key('liste-$cle'),
      initialValue: valeur,
      isDense: true,
      // ⚠️ `w-full` dans la maquette : sans `isExpanded`, l'option retenue
      // garde sa largeur naturelle et déborde de sa boîte.
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      style: const TextStyle(
        fontSize: AgriTypography.sm,
        color: AgriColors.onSurface,
      ),
      hint: invite == null
          ? null
          : Text(
              invite,
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.outline,
              ),
            ),
      items: [
        for (final (id, libelle) in options)
          DropdownMenuItem(value: id, child: Text(libelle)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _champ(String cle, TextEditingController controleur) => TextField(
    key: Key('champ-$cle'),
    controller: controleur,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    style: const TextStyle(fontSize: AgriTypography.sm),
  );

  Widget _bandeau(String texte, bool erreur) => Container(
    key: const Key('bandeau-achat'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: (erreur ? AgriColors.errorRed : AgriColors.brandEmerald)
          .withValues(alpha: 0.10),
      border: Border.all(
        color: (erreur ? AgriColors.errorRed : AgriColors.brandEmerald)
            .withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Text(
      texte,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        color: erreur ? AgriColors.errorDeep : AgriColors.brandForest,
      ),
    ),
  );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
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
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  /// L'œil « Voir » de la maquette (`title="Voir"`) et le bouton rouge « Retour
  /// fournisseur » (`cancel`) — celui-ci n'est proposé que si aucun retour n'est engagé.
  Widget _actionsAchat(LigneAchat ligne, int index) => Align(
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('voir-achat-$index'),
          onPressed: () => _voir(ligne),
          icon: const Icon(SymbolesAgri.visibility, size: 18),
          color: AgriColors.infoBlue,
          tooltip: 'Voir',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        if (ligne.retournable) ...[
          const SizedBox(width: AgriSpacing.sm),
          IconButton(
            key: Key('retour-achat-$index'),
            onPressed: () => _demanderRetour(ligne),
            icon: const Icon(SymbolesAgri.cancel, size: 18),
            color: AgriColors.errorDeep,
            tooltip: 'Retour fournisseur',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    ),
  );

  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  Widget _mentionPoste(String texte, {Key? cle}) => Container(
    key: cle ?? const Key('mention-poste'),
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

  static String _montant(double valeur) => AchatsRepository.montant(valeur);

  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.round().toString()
      : valeur.toString();

  static String _date(DateTime? d) => AchatsRepository.jour(d);
}
