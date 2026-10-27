import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/widgets/lecture_seule.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/pagination_agri.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import '../../core/systeme/justificatif_local.dart';
import '../stocks/produits_repository.dart';
import 'achats_creation_rapide.dart';
import 'achats_modales.dart';
import 'achats_repository.dart';
import 'fournisseurs_repository.dart';
import 'profil_fournisseur_screen.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/toast_agri.dart';

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
    this.depotProduits,
    this.choisirJustificatif = choisirEtCopierJustificatif,
    this.imprimer,
    this.maintenant,
  });

  final AchatsRepository depot;

  /// Ouvre le profil du fournisseur depuis le détail (le lien de la maquette,
  /// `profile-fournisseur.html`). Absent : le nom s'affiche sans lien.
  final FournisseursRepository? depotFournisseurs;

  /// Ticket AC-2 — dépôt propriétaire des produits : le bouton « + » de l'article crée un produit à la volée. Absent : le
  /// bouton n'est pas offert.
  final ProduitsRepository? depotProduits;

  /// Ticket AC-3 — sélecteur du justificatif ; le sélecteur de fichiers du système en production, un faux en test.
  final ChoisirJustificatif choisirJustificatif;

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

  /// Ticket EX7 (EF9) — page de la Liste d'Achats (25 achats), dans l'exercice affiché.
  int _pageAchats = 1;

  String? _fournisseurId;
  String? _produitId;
  String _modePaiement = 'especes';
  String? _compteId;

  final _quantite = TextEditingController();
  final _prixUnitaire = TextEditingController();
  final _montantPaye = TextEditingController();

  final List<LigneSaisieAchat> _panier = [];

  /// Ticket AC-3 — chemin local du justificatif joint à l'achat en cours de saisie.
  String? _justificatif;

  // Ticket AC-1 — « Saisie d'un Bon de Commande » (`BonsCommande` du web) : fournisseur, livraison attendue, panier prévisionnel.
  String? _bonFournisseurId;
  DateTime? _bonLivraison;
  String? _bonProduitId;
  final _bonQuantite = TextEditingController(text: '1');
  final _bonPrix = TextEditingController();
  final List<LigneSaisieBon> _panierBon = [];

  DonneesAchats? _donnees;
  String? _message;
  bool _messageEstUneErreur = false;

  /// Date de l'achat en cours de saisie (onglet 1) — par défaut : aujourd'hui.
  DateTime? _dateAchat;

  /// Filtre de date de la Liste d'Achats (onglet 2) ; `null` : aucun filtre.
  DateTime? _dateFiltreAchats;

  // #41 — barre de recherche et filtre de règlement (fidèles au `search`/`statusFilter` du Blade).
  String _rechercheAchat = '';
  String _filtreStatutAchat = '';
  final _ctrlRechercheAchat = TextEditingController();

  /// Fournisseur dont le profil est ouvert depuis le détail d'un achat ;
  /// `null` : le hub.
  String? _profilFournisseur;

  DateTime get _maintenant => (widget.maintenant ?? HeureBenin.maintenant)();

  @override
  void initState() {
    super.initState();
    _dateAchat = _maintenant;
    _charger();
  }

  @override
  void dispose() {
    _quantite.dispose();
    _prixUnitaire.dispose();
    _bonQuantite.dispose();
    _bonPrix.dispose();
    _montantPaye.dispose();
    _ctrlRechercheAchat.dispose();
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

  /// `openAddSupplierModal` / `saveNewSupplier` du web : « Nouveau Fournisseur », puis le fournisseur est sélectionné.
  Future<void> _nouveauFournisseur() async {
    final fiche = await ouvrirNouveauFournisseurRapide(context: context, depot: widget.depotFournisseurs!);
    if (fiche == null) return;
    await _charger();
    if (!mounted) return;
    setState(() => _fournisseurId = fiche.id);
    ToastAgri.afficher(context, 'Fournisseur enregistré avec succès.');
  }

  /// `openAddProductModal` / `saveNewProduct` du web : « Nouveau Produit », puis le produit est sélectionné (P.U. à 0).
  Future<void> _nouveauProduit() async {
    final fiche = await ouvrirNouveauProduitRapide(context: context, depot: widget.depotProduits!);
    if (fiche == null) return;
    await _charger();
    if (!mounted) return;
    setState(() {
      _produitId = fiche.id;
      _prixUnitaire.text = '0';
    });
    ToastAgri.afficher(
      context,
      'Produit ajouté au catalogue — complétez sa fiche (tarification) depuis le Catalogue.',
    );
  }

  Widget _boutonPlus(Key cle, String infobulle, IconData icone, VoidCallback surTap) => SizedBox(
    width: 40,
    height: 40,
    child: Tooltip(
      message: infobulle,
      child: Material(
        color: AgriColors.brandEmerald,
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        child: InkWell(
          key: cle,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          onTap: surTap,
          child: Icon(icone, size: 20, color: Colors.white),
        ),
      ),
    ),
  );

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

    try {
      await widget.depot.enregistrer(
        fournisseurId: _fournisseurId!,
        lignes: List.of(_panier),
        modePaiement: _modePaiement,
        compteId: _compteId!,
        montantPaye: paye,
        date: _dateAchat,
        receiptLocalPath: _justificatif,
      );
    } on RefusExercice catch (e) {
      // 🔴→✅ Ticket EX6 (EF7) — `EnregistrerAchat::save()` : « Achat refusé : » + le motif R4 en toast d'erreur, le
      // panier conservé pour corriger et réessayer.
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Achat refusé : ${e.motif}',
          type: TypeToast.erreur,
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _panier.clear();
      _montantPaye.clear();
      _justificatif = null;
      _dateAchat = _maintenant;
      _message =
          'Achat enregistré sur ce poste — il partira à la prochaine '
          'synchronisation.';
      _messageEstUneErreur = false;
    });

    await _charger();
  }

  // ── Sélecteurs de date ────────────────────────────────────────────────────

  /// Ticket #40 — calendrier borné à l'exercice ouvert (fidèle à `min`/`max` du Blade).
  Future<void> _choisirDateAchat() async {
    final premier = await widget.depot.premierJourSaisissable();
    if (!mounted) return;
    final dernier = _maintenant;
    final bornes = ExerciceDeSaisie.calendrier(
      premier: premier,
      repli: DateTime(2020),
      dernier: dernier,
      initial: _dateAchat ?? dernier,
    );
    final choisie = await showDatePicker(
      context: context,
      initialDate: bornes.initial,
      firstDate: bornes.premier,
      lastDate: dernier,
      locale: const Locale('fr'),
    );
    if (choisie != null && mounted) setState(() => _dateAchat = choisie);
  }

  /// Ticket #40 — filtre de date de la Liste d'Achats, borné à l'exercice affiché.
  Future<void> _choisirDateFiltreAchats() async {
    final etat = PorteeExerciceChoisi.lire(context);
    final valeurCourante = _dateFiltreAchats ?? _maintenant;
    final choisie = await showDatePicker(
      context: context,
      initialDate: etat?.borner(valeurCourante) ?? valeurCourante,
      firstDate: etat?.bornes.debut ?? DateTime(2020),
      lastDate: etat?.bornes.fin ?? _maintenant,
      locale: const Locale('fr'),
    );
    if (choisie != null && mounted) setState(() => _dateFiltreAchats = choisie);
  }

  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  // #41 — correspondance recherche : 8 premiers chars de l'UUID (référence affichée) ou nom fournisseur.
  bool _matchRecherche(LigneAchat l, String q) {
    final r = q.toLowerCase();
    return l.achat.id.substring(0, l.achat.id.length.clamp(0, 8)).toLowerCase().contains(r) ||
        (l.achat.supplierName ?? '').toLowerCase().contains(r);
  }

  // #42 — reste dû d'un achat d'après les dettes servies (null = inconnu).
  double? _detteAchat(DonneesAchats d, LigneAchat l) {
    if (!l.achat.hasDebt || !l.envoye) return 0;
    final payables = d.dettes.where((p) => p.purchaseId == l.achat.id).toList();
    if (payables.isEmpty) return null;
    return payables.fold<double>(0, (t, p) => t + (p.amount - p.amountPaid).clamp(0, double.infinity));
  }

  Widget _montantPayeCell(DonneesAchats d, LigneAchat l, String cle) {
    final dette = _detteAchat(d, l);
    final paye = dette == null ? null : l.achat.total - dette;
    return Text(
      paye == null ? '—' : _montant(paye),
      key: Key(cle),
      style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
    );
  }

  Widget _detteCell(DonneesAchats d, LigneAchat l, String cle) {
    final dette = _detteAchat(d, l);
    return Text(
      dette == null ? '—' : (dette > 0 ? _montant(dette) : '0'),
      key: Key(cle),
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: AgriTypography.gras,
        color: dette != null && dette > 0 ? AgriColors.errorDeep : null,
      ),
    );
  }

  // ── Liste d'Achats : détail, impression ───────────────────────────────────

  /// « Exporter PDF » — la liste entière, comme `exportAchatsPDF()`.
  ///
  /// ⚠️ Une liste vide n'est pas éditée : un document réduit à son en-tête
  /// ressemble à un rapport « rien à signaler » alors que le poste n'a
  /// simplement aucun achat.
  Future<void> _exporterListe(DonneesAchats d) async {
    // Ticket EX7 (EF9) — tout l'exercice affiché (`achatsDeLExercice()` du web), jamais la seule page.
    final etat = PorteeExerciceChoisi.lire(context);
    final achats = etat == null ? d.achats : [for (final a in d.achats) if (etat.contient(a.achat.purchaseDate)) a];
    if (achats.isEmpty) {
      _annoncer('Aucun achat à exporter.');
      return;
    }
    await _editer(DocumentsAchats.liste(achats));
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
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AgriSpacing.sm,
        children: [
          _titre('Enregistrer un Achat', large, icone: SymbolesAgri.add_shopping_cart),
          ChampDateFiltre(
            cle: const Key('date-achat'),
            valeur: _dateAchat ?? _maintenant,
            onTap: _choisirDateAchat,
          ),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ Pas d'`IntrinsicHeight` : le tableau des articles contient un
      // `LayoutBuilder` (largeur minimale du défilement horizontal), qui refuse
      // les dimensions intrinsèques. Les deux cartes sont alignées en haut, donc
      // aucune hauteur commune n'était de toute façon imposée.
      if (large)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 60, child: _panneauArticles(d)),
            const SizedBox(width: AgriSpacing.md),
            Expanded(flex: 40, child: _panneauReglement(d)),
          ],
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _liste(
                cle: 'fournisseur',
                valeur: _fournisseurId,
                options: [for (final f in d.fournisseurs) (f.id, f.name)],
                vide: '— Aucun fournisseur synchronisé —',
                invite: 'Choisir le fournisseur...',
                onChanged: (v) => setState(() => _fournisseurId = v),
              ),
            ),
            if (widget.depotFournisseurs != null) ...[
              const SizedBox(width: AgriSpacing.xs),
              _boutonPlus(const Key('ajouter-fournisseur'), 'Ajouter un fournisseur', SymbolesAgri.person_add, _nouveauFournisseur),
            ],
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _etiquette('Ajouter un Article'),
        _etiquettePetite('Produit / Article'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _liste(
                cle: 'produit',
                valeur: _produitId,
                options: [for (final p in d.produits) (p.id, p.name)],
                vide: '— Aucun produit synchronisé —',
                invite: 'Choisir un produit...',
                onChanged: (v) => setState(() => _produitId = v),
              ),
            ),
            if (widget.depotProduits != null) ...[
              const SizedBox(width: AgriSpacing.xs),
              _boutonPlus(const Key('ajouter-produit'), 'Ajouter un produit', SymbolesAgri.add_box, _nouveauProduit),
            ],
          ],
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
        // Ticket AC-3 — « Pièce Justificative » (Blade : cadre pointillé « Associer une photo du reçu »).
        _etiquette('Pièce Justificative'),
        _pieceJustificative(),
        const SizedBox(height: AgriSpacing.md),
        // Ticket EX7 (EF10) — exercice affiché clos : grisé, motif en info-bulle (`@lectureSeule` du web).
        LectureSeule.infobulle(LectureSeule.motif(context), FilledButton.icon(
          key: const Key('enregistrer-achat'),
          onPressed: LectureSeule.motif(context) == null ? _enregistrer : null,
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
        )),
      ],
    ),
  );

  /// Ticket AC-3 — cadre pointillé du Blade ; le fichier est copié localement puis ENVOYÉ avec l'achat (synchronisation).
  Widget _pieceJustificative() {
    final chemin = _justificatif;
    if (chemin == null) {
      return InkWell(
        key: const Key('achat-recu-choisir'),
        onTap: () async {
          final choisi = await widget.choisirJustificatif();
          if (choisi != null && mounted) setState(() => _justificatif = choisi);
        },
        child: Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AgriColors.outlineVariant, width: 2),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: const Column(
            children: [
              Icon(SymbolesAgri.add_a_photo, size: 36, color: AgriColors.outlineVariant),
              SizedBox(height: AgriSpacing.xs),
              Text(
                'Associer une photo du reçu',
                key: Key('achat-recu-invite'),
                style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.outline),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: AgriColors.brandEmerald),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        color: AgriColors.brandEmerald.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          const Icon(SymbolesAgri.description, size: 18, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text(
              chemin.split(RegExp(r'[\\/]')).last,
              key: const Key('achat-recu-nom'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
            ),
          ),
          IconButton(
            key: const Key('achat-recu-retirer'),
            tooltip: 'Retirer le justificatif',
            onPressed: () => setState(() => _justificatif = null),
            icon: const Icon(SymbolesAgri.close, size: 16, color: AgriColors.outline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Onglet 2 : Liste d'Achats ─────────────────────────────────────────────

  Widget _ongletListe(DonneesAchats d, bool large) {
    // Ticket EX7 (EF9) — les achats de l'exercice AFFICHÉ, 25 par page (web : `achatsDeLExercice()` puis la page) ;
    // l'export reprend tout l'exercice. Les indicateurs restent ceux du web (toute la ferme).
    final etat = PorteeExerciceChoisi.lire(context);
    // Ticket #40 — filtre de date en plus du filtre exercice (fidèle au `dateFilter` du Blade).
    final achatsExercice = etat == null ? d.achats : [for (final a in d.achats) if (etat.contient(a.achat.purchaseDate)) a];
    final achats = _dateFiltreAchats == null
        ? achatsExercice
        : [for (final a in achatsExercice) if (_memeJour(a.achat.purchaseDate, _dateFiltreAchats!)) a];
    // #41 — filtre texte : 8 premiers caractères de la référence ou nom fournisseur.
    final achatsRecherche = _rechercheAchat.isEmpty
        ? achats
        : [for (final a in achats) if (_matchRecherche(a, _rechercheAchat)) a];
    // #41 — filtre statut de règlement (fidèle au `statusFilter` 'paye'/'dette' du Blade).
    final achatsFiltres = _filtreStatutAchat == 'paye'
        ? [for (final a in achatsRecherche) if (a.envoye && !a.achat.hasDebt && !a.retourne) a]
        : _filtreStatutAchat == 'dette'
            ? [for (final a in achatsRecherche) if (a.achat.hasDebt) a]
            : achatsRecherche;
    final page = etat == null ? achatsFiltres : PaginationAgri.tranche(achatsFiltres, _pageAchats);
    final verrou = LectureSeule.motif(context);
    return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AgriSpacing.sm,
        children: [
          _titre("Liste d'Achats", large, icone: SymbolesAgri.list_alt),
          Wrap(
            spacing: AgriSpacing.xs,
            runSpacing: AgriSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Filtre date (fidèle au `<input type="date" wire:model.live="dateFilter">` du Blade).
              if (_dateFiltreAchats != null) ...[
                ChampDateFiltre(
                  cle: const Key('filtre-date-achats'),
                  valeur: _dateFiltreAchats!,
                  onTap: _choisirDateFiltreAchats,
                ),
                InkWell(
                  key: const Key('effacer-filtre-date-achats'),
                  onTap: () => setState(() => _dateFiltreAchats = null),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                  child: const Tooltip(
                    message: 'Effacer le filtre de date',
                    child: Icon(SymbolesAgri.close, size: 18, color: AgriColors.outline),
                  ),
                ),
              ] else
                OutlinedButton.icon(
                  key: const Key('ouvrir-filtre-date-achats'),
                  onPressed: _choisirDateFiltreAchats,
                  icon: const Icon(SymbolesAgri.calendar_today, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgriColors.outline,
                    side: const BorderSide(color: AgriColors.outlineVariant),
                    shape: const StadiumBorder(),
                  ),
                  label: const Text(
                    'Filtrer par date',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                ),
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
              LectureSeule.infobulle(verrou, OutlinedButton.icon(
                key: const Key('ajouter-remboursement'),
                onPressed: verrou != null ? null : () => _demanderRemboursement(d),
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
              )),
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
          // Ticket U8 — des LIGNES de retour, comme la page web
          // (`PurchaseReturn::count()`) : `purchase_returns` descend au tirage.
          valeur: '${d.ecartsEtRetours}',
          legende: d.retoursEnAttente > 0
              ? '${d.retoursEnAttente} demande(s) en attente '
                    "d'envoi, non comptée(s)"
              : null,
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.assignment_return,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      // #41 — barre de recherche + filtre de règlement (fidèles au bloc `bg-white border...p-md` du Blade).
      Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Wrap(
          spacing: AgriSpacing.sm,
          runSpacing: AgriSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180),
              child: TextField(
                key: const Key('recherche-achats'),
                controller: _ctrlRechercheAchat,
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: InputDecoration(
                  hintText: 'Rechercher par référence ou fournisseur...',
                  hintStyle: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                  prefixIcon: const Icon(SymbolesAgri.search, size: 18, color: AgriColors.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AgriRadius.lg), borderSide: const BorderSide(color: AgriColors.outlineVariant)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: AgriSpacing.sm),
                  isDense: true,
                ),
                onChanged: (v) => setState(() { _rechercheAchat = v.trim(); _pageAchats = 1; }),
              ),
            ),
            DropdownButton<String>(
              key: const Key('filtre-statut-achats'),
              value: _filtreStatutAchat,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
              items: const [
                DropdownMenuItem(value: '', child: Text('Tous les règlements')),
                DropdownMenuItem(value: 'paye', child: Text('Payé entièrement')),
                DropdownMenuItem(value: 'dette', child: Text('Dette fournisseur')),
              ],
              onChanged: (v) => setState(() { _filtreStatutAchat = v ?? ''; _pageAchats = 1; }),
            ),
          ],
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1250,
        colonnes: const [
          ('Référence Achat', 3),
          ('Date', 3),
          ('Fournisseur', 4),
          ('Catégorie', 3),
          ('Montant Payé', 2),
          ('Montant Total', 2),
          ('Dette', 2),
          ('Statut', 4),
          ('Actions', 3),
        ],
        vide: '— Aucun achat pour ces critères —',
        lignes: [
          for (var i = 0; i < page.length; i++)
            _ligne(i, [
              (_reference(), 3),
              (Text(_date(page[i].achat.purchaseDate), style: _cellule), 3),
              (
                Text(
                  page[i].achat.supplierName ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              // Ticket U8 — catégorie de PRODUIT de la première ligne, comme le
              // web (`ListeAchats`), et non celle du fournisseur.
              (
                Text(
                  page[i].categorie ?? '—',
                  key: Key('categorie-achat-$i'),
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              // #42 — Montant Payé / Montant Total / Dette (fidèles au tiroir du Blade : `$purchase->payable->balance`).
              (_montantPayeCell(d, page[i], 'paye-$i'), 2),
              (
                Text(
                  _montant(page[i].achat.total),
                  key: Key('total-achat-$i'),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                2,
              ),
              (_detteCell(d, page[i], 'dette-$i'), 2),
              (_statut(page[i], 'liste-$i'), 4),
              (_actionsAchat(page[i], i), 3),
            ]),
        ],
      ),
      if (etat != null)
        PaginationAgri(
          nom: 'achats',
          total: achatsFiltres.length,
          page: _pageAchats,
          annee: etat.annee,
          onPage: (p) => setState(() => _pageAchats = p),
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
  }

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

  // ── Onglet 3 : Bons de Commande (ticket AC-1 : `bons-commande.blade.php`) ─────

  double get _totalBon => _panierBon.fold<double>(0, (t, l) => t + l.total);

  /// `updatedLineProductId` du web : choisir un produit propose son prix minimal comme P.U estimé.
  void _choisirProduitBon(DonneesAchats d, String? id) {
    final produit = d.produits.where((p) => p.id == id).firstOrNull;
    setState(() {
      _bonProduitId = id;
      _bonPrix.text = produit?.priceMin == null ? '' : _nombre(produit!.priceMin!);
    });
  }

  void _ajouterAuBon(DonneesAchats d) {
    final produit = d.produits.where((p) => p.id == _bonProduitId).firstOrNull;
    final quantite = int.tryParse(_bonQuantite.text.trim());
    final prix = double.tryParse(_bonPrix.text.trim().replaceAll(',', '.'));
    final refus = produit == null
        ? 'Le champ produit est obligatoire.'
        : (quantite == null || quantite < 1)
        ? 'Le champ quantité doit être un nombre entier supérieur ou égal à 1.'
        : (prix == null || prix < 0)
        ? 'Le champ prix unitaire estimé est obligatoire (zéro ou plus).'
        : null;
    if (refus != null) {
      setState(() {
        _message = refus;
        _messageEstUneErreur = true;
      });
      return;
    }
    setState(() {
      _panierBon.add(LigneSaisieBon(produit: produit!, quantite: quantite!, prixEstime: prix!));
      _bonProduitId = null;
      _bonPrix.clear();
      _bonQuantite.text = '1';
      _message = null;
    });
  }

  Future<void> _genererBon() async {
    try {
      await widget.depot.creerBon(
        fournisseurId: _bonFournisseurId ?? '',
        livraisonAttendue: _bonLivraison,
        lignes: List.of(_panierBon),
      );
    } on SaisieAchatRefusee catch (e) {
      setState(() {
        _message = e.motif;
        _messageEstUneErreur = true;
      });
      return;
    }
    setState(() {
      _panierBon.clear();
      _bonFournisseurId = null;
      _bonLivraison = null;
      _message = null;
    });
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, 'Bon de commande généré avec succès.');
  }

  Future<void> _choisirLivraison() async {
    final aujourdhui = _maintenant;
    final choisie = await showDatePicker(
      context: context,
      initialDate: _bonLivraison ?? aujourdhui,
      firstDate: DateTime(aujourdhui.year - 1),
      lastDate: DateTime(aujourdhui.year + 3),
      locale: const Locale('fr'),
    );
    if (choisie != null && mounted) setState(() => _bonLivraison = choisie);
  }

  /// `openReceiveModal` / `confirmReceiveOrder` : la modale « Valider la réception ».
  Future<void> _recevoirBon(LigneBon l) async {
    final ok = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        titre: 'Valider la réception',
        message:
            "Contrôle de validation et intégration aux stocks physiques. La validation de la réception générera "
            "automatiquement une facture d'achat formelle et incrémentera vos stocks de marchandises physiques en base locale.",
        icone: SymbolesAgri.assignment_turned_in,
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(contexte).pop(false)),
          BoutonModalePrimaire(
            key: const Key('reception-confirmer'),
            libelle: 'Confirmer la Réception',
            onPressed: () async {
              try {
                await widget.depot.recevoirBon(l.bon.id);
              } on SaisieAchatRefusee catch (e) {
                if (contexte.mounted) Navigator.of(contexte).pop(false);
                _annoncer(e.motif);
                return;
              }
              if (contexte.mounted) Navigator.of(contexte).pop(true);
            },
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _charger();
    _annoncer('Réception enregistrée — la facture d\'achat sera générée et les stocks mis à jour à la prochaine synchronisation.');
  }

  Future<void> _imprimerBon(DonneesAchats d, LigneBon l) async {
    final fournisseur = d.fournisseurs.where((f) => f.id == l.bon.supplierId).firstOrNull;
    final noms = {for (final p in d.produits) p.id: p};
    await _editer(DocumentsAchats.bonCommande(l, fournisseur: fournisseur, produits: noms));
  }

  static const _libellesStatutBon = {
    'brouillon': 'BROUILLON',
    'envoye': 'ENVOYÉ / EN COURS',
    'recu': 'REÇU / VALIDÉ',
    'annule': 'ANNULÉ',
  };

  Widget _ongletBons(DonneesAchats d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Bons de Commande', large),
      const SizedBox(height: AgriSpacing.xs),
      const Text(
        'Planification des approvisionnements de la ferme.',
        style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
      ),
      const SizedBox(height: AgriSpacing.md),
      _carte(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(SymbolesAgri.assignment_turned_in, size: 20, color: AgriColors.brandEmerald),
                SizedBox(width: AgriSpacing.xs),
                Text(
                  "Saisie d'un Bon de Commande",
                  style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              'Générer un ordre d\'achat prévisionnel multi-produits.',
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
            const SizedBox(height: AgriSpacing.md),
            Wrap(
              spacing: AgriSpacing.md,
              runSpacing: AgriSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _etiquettePetite('Fournisseur'),
                      _liste(
                        cle: 'bon-fournisseur',
                        valeur: _bonFournisseurId,
                        options: [for (final f in d.fournisseurs) (f.id, f.name)],
                        vide: '— Aucun fournisseur synchronisé —',
                        invite: 'Choisir le fournisseur...',
                        onChanged: (v) => setState(() => _bonFournisseurId = v),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _etiquettePetite('Date de Livraison Attendue'),
                    ChampDateFiltre(
                      cle: const Key('bon-livraison'),
                      valeur: _bonLivraison ?? _maintenant,
                      onTap: _choisirLivraison,
                    ),
                  ],
                ),
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _etiquettePetite('Produit / Article'),
                      _liste(
                        cle: 'bon-produit',
                        valeur: _bonProduitId,
                        options: [for (final p in d.produits) (p.id, p.name)],
                        vide: '— Aucun produit synchronisé —',
                        invite: 'Choisir un produit...',
                        onChanged: (v) => _choisirProduitBon(d, v),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_etiquettePetite('Quantité'), _champ('bon-quantite', _bonQuantite)],
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_etiquettePetite('P.U Estimé (FCFA)'), _champ('bon-prix', _bonPrix)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.md),
            OutlinedButton.icon(
              key: const Key('bon-ajouter'),
              onPressed: () => _ajouterAuBon(d),
              icon: const Icon(SymbolesAgri.add, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AgriColors.brandEmerald,
                side: const BorderSide(color: AgriColors.brandEmerald, width: 2),
                padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              ),
              label: const Text(
                'Ajouter au bon de commande',
                style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras),
              ),
            ),
          ],
        ),
      ),
      if (_message != null && _onglet == 'Bons de Commande') ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_message!, _messageEstUneErreur),
      ],
      const SizedBox(height: AgriSpacing.md),
      if (large)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 65, child: _panneauArticlesBon()),
            const SizedBox(width: AgriSpacing.md),
            Expanded(flex: 35, child: _panneauTotalBon()),
          ],
        )
      else ...[
        _panneauArticlesBon(),
        const SizedBox(height: AgriSpacing.md),
        _panneauTotalBon(),
      ],
      const SizedBox(height: AgriSpacing.lg),
      const Text(
        'Bons de commande émis',
        style: TextStyle(fontSize: AgriTypography.base, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
      ),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        largeur: 1150,
        colonnes: const [
          ('Réf Commande', 3),
          ("Date d'Émission", 3),
          ('Livraison Attendue', 3),
          ('Fournisseur', 4),
          ('Montant Estimé', 3),
          ('Statut', 4),
          ('Actions', 3),
        ],
        vide: 'Aucun bon de commande émis pour le moment.',
        lignes: [
          for (var i = 0; i < d.bonsCommande.length; i++)
            _ligne(i, [
              (Text(d.bonsCommande[i].bon.id.substring(0, 8).toUpperCase(), key: Key('bon-ref-$i'), style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandEmerald)), 3),
              (Text(_date(d.bonsCommande[i].bon.createdAt), style: _cellule), 3),
              (Text(_date(d.bonsCommande[i].bon.expectedDeliveryDate), style: _cellule), 3),
              (
                Text(
                  d.bonsCommande[i].bon.supplierName ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
                ),
                4,
              ),
              (
                Text(
                  _montant(d.bonsCommande[i].lignes.isEmpty ? d.bonsCommande[i].bon.estimatedTotal : d.bonsCommande[i].total),
                  style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
                ),
                3,
              ),
              (_statutBon(d.bonsCommande[i], i), 4),
              (_actionsBon(d, d.bonsCommande[i], i), 3),
            ]),
        ],
      ),
    ],
  );

  Widget _panneauArticlesBon() => _carte(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(SymbolesAgri.shopping_basket, size: 20, color: AgriColors.brandForest),
            SizedBox(width: AgriSpacing.xs),
            Text(
              'Articles Prévisionnels de la Commande',
              style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (_panierBon.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AgriSpacing.lg),
            child: Center(
              child: Text(
                'Aucun article ajouté au bon de commande.',
                key: Key('bon-panier-vide'),
                style: TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline),
              ),
            ),
          )
        else
          _tableau(
            largeur: 520,
            colonnes: const [('Produit', 5), ('Qté', 2), ('P.U', 2), ('Total', 3), ('', 1)],
            vide: '',
            lignes: [
              for (var i = 0; i < _panierBon.length; i++)
                _ligne(i, [
                  (Text(_panierBon[i].produit.name, style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)), 5),
                  (Text('${_panierBon[i].quantite} ${_panierBon[i].produit.unit}', style: _cellule), 2),
                  (Text(_montant(_panierBon[i].prixEstime), style: _cellule), 2),
                  (Text(_montant(_panierBon[i].total), key: Key('bon-ligne-total-$i'), style: _cellule.copyWith(fontWeight: AgriTypography.gras)), 3),
                  (
                    IconButton(
                      key: Key('bon-retirer-$i'),
                      tooltip: 'Retirer',
                      onPressed: () => setState(() => _panierBon.removeAt(i)),
                      icon: const Icon(SymbolesAgri.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: AgriColors.errorDeep,
                    ),
                    1,
                  ),
                ]),
            ],
          ),
      ],
    ),
  );

  Widget _panneauTotalBon() => _carte(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.accentYellow.withValues(alpha: 0.20),
            border: Border.all(color: AgriColors.accentYellow),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL ESTIMÉ',
                style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
              ),
              Text(
                '${_montant(_totalBon)} FCFA',
                key: const Key('bon-total'),
                style: const TextStyle(fontSize: AgriTypography.xl, fontWeight: FontWeight.w800, color: AgriColors.brandForest),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          "Rappel : Ces articles d'approvisionnement (aliments, vaccins) sont stockés dans le module Stocks (Classe 3) et ne "
          'seront jamais mélangés avec vos produits finis de la ferme (Classe 7).',
          cle: const Key('bon-rappel'),
        ),
        const SizedBox(height: AgriSpacing.md),
        ElevatedButton.icon(
          key: const Key('bon-generer'),
          onPressed: _genererBon,
          icon: const Icon(SymbolesAgri.check_circle, size: 18),
          style: ElevatedButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
          ),
          label: const Text('Générer le Bon', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras)),
        ),
      ],
    ),
  );

  /// Statut du bon (libellés du Blade) ; « En attente d'envoi » tant que le serveur n'a pas acquitté ; « Refusé » avec son motif.
  Widget _statutBon(LigneBon l, int i) {
    final etiquette = _libellesStatutBon[l.statut] ?? l.statut.toUpperCase();
    final couleur = switch (l.statut) {
      'recu' => AgriColors.brandEmerald,
      'annule' => AgriColors.errorRed,
      'envoye' => AgriColors.infoBlue,
      _ => AgriColors.outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pastille(etiquette, couleur, Key('bon-statut-$i')),
        if (l.enAttente || (l.receptionEnAttente && l.bon.status != 'recu'))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _pastille(
              l.receptionEnAttente && l.bon.status != 'recu' ? 'Réception en attente' : 'En attente d\'envoi',
              AgriColors.accentYellow,
              Key('bon-attente-$i'),
            ),
          ),
        if (l.refuse)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _pastille('Refusé par le serveur', AgriColors.errorRed, Key('bon-refus-$i')),
          ),
        if (l.motifRefus != null || l.motifRefusReception != null)
          Text(
            l.motifRefus ?? l.motifRefusReception!,
            key: Key('bon-motif-$i'),
            style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
          ),
      ],
    );
  }

  /// Imprimer (`exportPdf`) et « Valider la réception » (`openReceiveModal`, absent d'un bon reçu ou annulé).
  Widget _actionsBon(DonneesAchats d, LigneBon l, int i) => Row(
    children: [
      IconButton(
        key: Key('bon-imprimer-$i'),
        tooltip: 'Exporter PDF',
        onPressed: () => _imprimerBon(d, l),
        icon: const Icon(SymbolesAgri.print, size: 18),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        color: AgriColors.outline,
      ),
      if (l.receptionPossible)
        IconButton(
          key: Key('bon-recevoir-$i'),
          tooltip: 'Valider la réception',
          onPressed: () => _recevoirBon(l),
          icon: const Icon(SymbolesAgri.assignment_turned_in, size: 18),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
          color: AgriColors.brandEmerald,
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

  Widget _grilleKpis(bool large, List<Widget> cartes) => GrilleKpi(colonnes: large ? cartes.length : 2, children: cartes,
  );

  Widget _titre(String texte, bool large, {IconData? icone}) {
    final texteWidget = Text(
      texte,
      style: TextStyle(
        fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
        fontWeight: AgriTypography.gras,
        color: AgriColors.onSurface,
      ),
    );
    if (icone == null) return texteWidget;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: large ? 28.0 : 24.0, color: AgriColors.brandEmerald),
        const SizedBox(width: AgriSpacing.xs),
        texteWidget,
      ],
    );
  }

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

    // Ticket AC-2 : la valeur peut changer SANS clic (fournisseur ou produit créé à la volée, puis sélectionné) ; `initialValue`
    // n'est lu qu'à la création du champ, la clé de valeur le recrée.
    return KeyedSubtree(
      key: ValueKey('valeur-$cle-$valeur'),
      child: DropdownButtonFormField<String>(
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
    ),
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
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(largeur, contraintes.maxWidth),
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
            // Ticket EX7 (EF10) — exercice affiché clos : grisé, motif en info-bulle.
            onPressed: LectureSeule.motif(context) != null ? null : () => _demanderRetour(ligne),
            icon: const Icon(SymbolesAgri.cancel, size: 18),
            color: AgriColors.errorDeep,
            tooltip: LectureSeule.motif(context) ?? 'Retour fournisseur',
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
