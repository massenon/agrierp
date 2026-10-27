import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/systeme/justificatif_local.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../stocks/pmp_service.dart';
import 'depenses_repository.dart';

/// La modale « Nouvelle Dépense » / « Modifier la Dépense » —
/// `<x-modal name="modal-depense" max-width="xl">` de `resources/views/livewire/achats/saisie-depenses.blade.php`
/// (maître, article 5), ticket DEP5.
///
/// Une dépense, plusieurs lignes : l'EN-TÊTE (Date de la Transaction, Mode de Paiement, Compte de Trésorerie Débité,
/// Centre de Coût, Fournisseur, Bénéficiaire, Reçu / Facture) puis les LIGNES dynamiques (Libellé, Compte de Charge,
/// Montant), « Ajouter une ligne », la ligne se retire (la dernière jamais), « Total : N FCFA » EN DIRECT (la somme des
/// lignes, jamais saisie), « Enregistrer la Dépense ». Les erreurs se posent sous leur champ avec les messages du web
/// (`DepenseRefusee`) ; une soumission réussie ferme la modale (résultat `true`).
///
/// 🔴→✅ Tickets DEP6 et DEP7 — « Centre de Coût * » est OBLIGATOIRE (message sous le champ, comme le web) ; dès qu'un
/// fournisseur est choisi, « Règlement * » propose « Payée comptant » ou « À crédit (dette fournisseur) » : à crédit, ni
/// « Mode de Paiement » ni « Compte de Trésorerie Débité » (aucun décaissement, la dette naît au serveur).
///
/// Mode et compte de trésorerie ne se contredisent jamais (comme `updatedPaymentMode()` / `updatedTreasuryAccountId()` du
/// web) : choisir un mode filtre les comptes et abandonne celui d'un autre type ; choisir un compte fixe le mode.
///
/// ⚠️ ÉCART (plateforme) : « Reçu / Facture (Photo) ». La synchronisation ne transporte aucun fichier : le champ est à sa
/// place et dit sa limite, au lieu d'accepter une photo qui ne partirait jamais.
class ModaleDepense extends StatefulWidget {
  const ModaleDepense({super.key, required this.depot, this.enModification});

  final DepensesRepository depot;

  /// La dépense à modifier (SANS pièce) ; `null` : « Nouvelle Dépense ».
  final LigneDepense? enModification;

  /// Ouvre la modale ; `true` si une dépense a été enregistrée.
  static Future<bool?> ouvrir(
    BuildContext context, {
    required DepensesRepository depot,
    LigneDepense? enModification,
  }) => afficherModale<bool>(
    context: context,
    constructeur: (_) => ModaleDepense(depot: depot, enModification: enModification),
  );

  @override
  State<ModaleDepense> createState() => _ModaleDepenseState();
}

/// Une ligne en cours de saisie (ses champs vivent tant que la modale est ouverte).
class _LigneEdition {
  _LigneEdition({this.id, String libelle = '', this.compteId, String montant = ''})
    : libelle = TextEditingController(text: libelle),
      montant = TextEditingController(text: montant);

  final String? id;
  final TextEditingController libelle;
  final TextEditingController montant;
  String? compteId;

  LigneSaisie enSaisie() => LigneSaisie(
    id: id,
    libelle: libelle.text,
    compteChargeId: compteId,
    montant: montant.text,
  );

  void liberer() {
    libelle.dispose();
    montant.dispose();
  }
}

class _ModaleDepenseState extends State<ModaleDepense> {
  List<ChartOfAccount> _comptesDeCharge = const [];
  List<TreasuryAccount> _comptes = const [];
  List<CostCenter> _centres = const [];
  List<Supplier> _fournisseurs = const [];

  DateTime _date = HeureBenin.aujourdhui();
  String? _mode;
  String? _compteId;
  String? _centreId;
  String? _fournisseurId;

  /// Ticket DEP7 — `comptant` ou `credit` (`DepensesRepository.reglements`) ; `comptant` tant qu'aucun fournisseur n'est choisi.
  String _reglement = 'comptant';
  final _beneficiaire = TextEditingController();
  final List<_LigneEdition> _lignes = [];

  bool _enregistrement = false;
  Map<String, String> _erreurs = const {};

  /// Ticket #48 — chemin absolu du justificatif copié localement (envoyé au serveur ensuite : ticket AC-3).
  String? _receiptLocalPath;

  @override
  void initState() {
    super.initState();
    final d = widget.enModification;
    if (d == null) {
      _lignes.add(_LigneEdition());
    } else {
      final e = d.depense;
      _date = e.expenseDate;
      _mode = e.paymentMode;
      _compteId = e.treasuryAccountId;
      _centreId = e.costCenterId;
      _fournisseurId = e.supplierId;
      _beneficiaire.text = e.beneficiary ?? '';
      _receiptLocalPath = e.receiptLocalPath;
      for (final l in d.lignes) {
        _lignes.add(
          _LigneEdition(
            id: l.id,
            libelle: l.libelle,
            compteId: l.compteChargeId,
            montant: PmpService.flottant(l.montant),
          ),
        );
      }
      if (_lignes.isEmpty) _lignes.add(_LigneEdition());
    }
    _charger();
  }

  @override
  void dispose() {
    _beneficiaire.dispose();
    for (final l in _lignes) {
      l.liberer();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    final comptesDeCharge = await widget.depot.comptesDeCharge();
    final comptes = await widget.depot.comptesTresorerie();
    final centres = await widget.depot.centresDeCout();
    final fournisseurs = await widget.depot.fournisseurs();
    if (!mounted) return;
    setState(() {
      _comptesDeCharge = comptesDeCharge;
      _comptes = comptes;
      _centres = centres;
      _fournisseurs = fournisseurs;
      // Une dépense existante sans mode (poste migré avant d'avoir le compte) : le type de son compte.
      if (_mode == null && _compteId != null) {
        _mode = comptes.where((c) => c.id == _compteId).firstOrNull?.type;
      }
    });
  }

  /// La dépense est saisie À CRÉDIT : fournisseur choisi ET règlement « À crédit » (`getACreditProperty()` du web).
  bool get _aCredit => _fournisseurId != null && _fournisseurId!.isNotEmpty && _reglement == 'credit';

  int get _total => DepensesRepository.total([for (final l in _lignes) l.enSaisie()]);

  // ── Gabarit de champ (classes du Blade) ──────────────────────────────────────────────────────────────────────────

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AgriColors.brandForest,
      ),
    ),
  );

  /// `<p class="invalid-feedback">` du Blade (11 px, `#BA1A1A`).
  Widget _erreur(String cle) {
    final texte = _erreurs[cle];
    if (texte == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        texte,
        key: Key('erreur-$cle'),
        style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
      ),
    );
  }

  /// Cadre `h-11 px-md border rounded-lg text-sm`, rouge et teinté si le champ est en erreur (`is-invalid`).
  BoxDecoration _cadre(String cle) => BoxDecoration(
    color: _erreurs.containsKey(cle) ? const Color(0xFFFFF5F5) : AgriColors.surfaceCard,
    border: Border.all(
      color: _erreurs.containsKey(cle) ? AgriColors.errorDeep : AgriColors.outlineVariant,
    ),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  Widget _champTexte({
    required String cle,
    required TextEditingController controleur,
    required String exemple,
    bool nombre = false,
    ValueChanged<String>? surChangement,
  }) {
    final enErreur = _erreurs.containsKey(cle);
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: BorderSide(
        color: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: TextField(
            key: Key('champ-$cle'),
            controller: controleur,
            onChanged: surChangement,
            keyboardType: nombre ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: AgriTypography.sm),
            decoration: InputDecoration(
              hintText: exemple,
              isDense: true,
              filled: enErreur,
              fillColor: const Color(0xFFFFF5F5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: 12,
              ),
              border: bord,
              enabledBorder: bord,
            ),
          ),
        ),
        _erreur(cle),
      ],
    );
  }

  Widget _liste({
    required String cle,
    required String? valeur,
    required String vide,
    required List<(String, String)> options,
    required ValueChanged<String?> surChangement,
  }) {
    // Une valeur hors de la liste (compte désactivé depuis la saisie) : le web garde la valeur et montre le choix vide ;
    // une liste Flutter refuse une valeur absente de ses entrées.
    final presente = options.any((o) => o.$1 == valeur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
          decoration: _cadre(cle),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: Key('liste-$cle'),
              isExpanded: true,
              value: presente ? valeur : null,
              hint: Text(
                vide,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  color: AgriColors.onSurface,
                ),
              ),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.onSurface,
              ),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: surChangement,
            ),
          ),
        ),
        _erreur(cle),
      ],
    );
  }

  Widget _champ(String etiquette, Widget champ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_etiquette(etiquette), champ],
  );

  // ── En-tête ──────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _champDate() => ChampDateFormulaire(
    cle: const Key('champ-date'),
    etiquette: 'Date de la Transaction *',
    valeur: _date,
    erreur: _erreurs['date'],
    cleErreur: const Key('erreur-date'),
    onTap: () async {
      final premier = await widget.depot.premierJourSaisissable();
      if (!mounted) return;
      final bornes = ExerciceDeSaisie.calendrier(
        premier: premier,
        repli: DateTime(2000),
        dernier: DateTime(2100),
        initial: _date,
      );
      final choisie = await showDatePicker(
        context: context,
        initialDate: bornes.initial,
        firstDate: bornes.premier,
        lastDate: DateTime(2100),
      );
      if (choisie != null) setState(() => _date = choisie);
    },
  );

  Widget _champMode() => _champ(
    'Mode de Paiement *',
    _liste(
      cle: 'mode',
      valeur: _mode,
      vide: '-- Sélectionner --',
      options: [for (final e in DepensesRepository.modesDePaiement.entries) (e.key, e.value)],
      surChangement: (v) => setState(() {
        _mode = v;
        // Un compte d'un autre type est abandonné (`updatedPaymentMode()` du web).
        final compte = _comptes.where((c) => c.id == _compteId).firstOrNull;
        if (compte != null && v != null && compte.type != v) _compteId = null;
      }),
    ),
  );

  Widget _champCompte() {
    final visibles = [for (final c in _comptes) if (_mode == null || _mode!.isEmpty || c.type == _mode) c];
    return _champ(
      'Compte de Trésorerie Débité *',
      _liste(
        cle: 'compte',
        valeur: _compteId,
        vide: '-- Sélectionner --',
        // `{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)`.
        options: [for (final c in visibles) (c.id, '${c.label} (${PmpService.francs(c.balance)} FCFA)')],
        surChangement: (v) => setState(() {
          _compteId = v;
          // Choisir un compte fixe le mode : son type (`updatedTreasuryAccountId()` du web).
          final type = _comptes.where((c) => c.id == v).firstOrNull?.type;
          if (type != null) _mode = type;
        }),
      ),
    );
  }

  Widget _champCentre() => _champ(
    'Centre de Coût *',
    _liste(
      cle: 'centre',
      valeur: _centreId,
      vide: '-- Sélectionner --',
      options: [for (final c in _centres) (c.id, c.label)],
      surChangement: (v) => setState(() => _centreId = v),
    ),
  );

  Widget _champFournisseur() => _champ(
    'Fournisseur',
    _liste(
      cle: 'fournisseur',
      valeur: _fournisseurId,
      vide: '-- Aucun --',
      // « -- Aucun -- » reste un choix (le fournisseur est facultatif) : il retire le fournisseur et donc le crédit.
      options: [('', '-- Aucun --'), for (final f in _fournisseurs) (f.id, f.name)],
      surChangement: (w) => setState(() {
        final v = w == null || w.isEmpty ? null : w;
        _fournisseurId = v;
        // Sans fournisseur, pas de crédit (`updatedSupplierId()` du web).
        if (v == null || v.isEmpty) _reglement = 'comptant';
      }),
    ),
  );

  /// « Règlement * » (ticket DEP7) : proposé dès qu'un fournisseur est choisi ; à crédit, une aide dit qu'aucune
  /// trésorerie n'est touchée (`data-aide-credit` du Blade).
  Widget _champReglement() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _champ(
        'Règlement *',
        _liste(
          cle: 'reglement',
          valeur: _reglement,
          vide: '-- Sélectionner --',
          options: [for (final e in DepensesRepository.reglements.entries) (e.key, e.value)],
          surChangement: (v) => setState(() => _reglement = v ?? 'comptant'),
        ),
      ),
      if (_aCredit)
        const Padding(
          padding: EdgeInsets.only(top: AgriSpacing.xs),
          child: Text(
            "Aucune trésorerie n'est touchée : la dette est créée au nom du fournisseur et se règle dans « Dettes Fournisseurs ».",
            key: Key('depense-aide-credit'),
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ),
    ],
  );

  Widget _champBeneficiaire() => _champ(
    'Bénéficiaire',
    _champTexte(
      cle: 'beneficiaire',
      controleur: _beneficiaire,
      exemple: "ex : M. Dossou (si ce n'est pas un fournisseur)",
    ),
  );

  /// « Reçu / Facture (Photo) » — cadre pointillé du Blade (`border-2 border-dashed … h-11`).
  /// Ticket #48 : le fichier est copié localement ; ticket AC-3 : il part ensuite au serveur (`receipt_sent`).
  Widget _recu() {
    final chemin = _receiptLocalPath;
    return _champ(
      'Reçu / Facture (Photo)',
      chemin == null
          ? InkWell(
              key: const Key('depense-recu-choisir'),
              onTap: _choisirJustificatif,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AgriColors.outlineVariant, width: 2),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(SymbolesAgri.add_a_photo, size: 18, color: AgriColors.outlineVariant),
                    SizedBox(width: AgriSpacing.xs),
                    Flexible(
                      child: Text(
                        'Joindre un justificatif (JPG, PNG, PDF) — envoyé à la ferme à la prochaine synchronisation',
                        key: Key('depense-recu-limite'),
                        style: TextStyle(fontSize: 10, color: AgriColors.outline),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: AgriColors.brandEmerald, width: 1),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
                color: AgriColors.brandEmerald.withValues(alpha: 0.05),
              ),
              child: Row(
                children: [
                  const Icon(SymbolesAgri.description, size: 18, color: AgriColors.brandEmerald),
                  const SizedBox(width: AgriSpacing.xs),
                  Expanded(
                    child: Text(
                      p.basename(chemin),
                      key: const Key('depense-recu-nom'),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AgriColors.brandForest,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: const Key('depense-recu-retirer'),
                    icon: const Icon(SymbolesAgri.close, size: 16, color: AgriColors.outline),
                    onPressed: () => setState(() => _receiptLocalPath = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Retirer le justificatif',
                  ),
                ],
              ),
            ),
    );
  }

  /// Ouvre le sélecteur de fichier et copie le fichier choisi dans le dossier local de l'application.
  Future<void> _choisirJustificatif() async {
    final chemin = await choisirEtCopierJustificatif();
    if (chemin == null || !mounted) return;
    setState(() => _receiptLocalPath = chemin);
  }

  // ── Lignes ───────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _enTeteLignes() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        'LIGNES DE LA DÉPENSE *',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
      ),
      InkWell(
        key: const Key('bouton-ajouter-ligne'),
        onTap: () => setState(() => _lignes.add(_LigneEdition())),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SymbolesAgri.add, size: 18, color: AgriColors.brandEmerald),
            SizedBox(width: AgriSpacing.xs),
            Text(
              'Ajouter une ligne',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandEmerald,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  static const _titreColonne = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline);

  Widget _ligne(int i) {
    final l = _lignes[i];
    final cleCompte = 'ligne.$i.compte';
    final presente = _comptesDeCharge.any((c) => c.id == l.compteId);
    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _champTexte(
              cle: 'ligne.$i.libelle',
              controleur: l.libelle,
              exemple: 'ex : Carburant livraison ou Achat provende Lot 3',
              surChangement: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
                  decoration: _cadre(cleCompte),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: Key('liste-ligne-$i-compte'),
                      isExpanded: true,
                      value: presente ? l.compteId : null,
                      hint: const Text(
                        '-- Sélectionner --',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
                      ),
                      style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
                      items: [
                        for (final c in _comptesDeCharge)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.code} - ${c.label}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => l.compteId = v),
                    ),
                  ),
                ),
                _erreur(cleCompte),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            flex: 2,
            child: _champTexte(
              cle: 'ligne.$i.montant',
              controleur: l.montant,
              exemple: 'ex : 25000',
              nombre: true,
              surChangement: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: 36,
            height: 44,
            child: IconButton(
              key: Key('ligne-$i-retirer'),
              tooltip: 'Retirer la ligne',
              padding: EdgeInsets.zero,
              onPressed: _lignes.length < 2
                  ? null
                  : () => setState(() {
                      _lignes.removeAt(i).liberer();
                      _erreurs = const {};
                    }),
              icon: const Icon(SymbolesAgri.delete, size: 18, color: AgriColors.outline),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreurs = const {};
    });

    try {
      await widget.depot.enregistrer(
        date: _date,
        modePaiement: _mode,
        compteTresorerieId: _compteId,
        centreCoutId: _centreId,
        fournisseurId: _fournisseurId,
        beneficiaire: _beneficiaire.text,
        lignes: [for (final l in _lignes) l.enSaisie()],
        idEnModification: widget.enModification?.depense.id,
        aCredit: _aCredit,
        receiptLocalPath: _receiptLocalPath,
      );
    } on DepenseRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurs = e.erreurs;
        _enregistrement = false;
      });
      return;
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `submitExpense()` : exercice clos ou absent, le motif R4 sous « Date ».
      if (!mounted) return;
      setState(() {
        _erreurs = {'date': e.motif};
        _enregistrement = false;
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // `md:grid-cols-2` : deux colonnes dès le point de rupture `md` du web (768 px de FENÊTRE).
    final large = AgriBreakpoints.moyen(context);
    final entete = <Widget>[
      _champDate(),
      // Ticket DEP7 — à crédit, ni mode ni compte de trésorerie (`@unless($this->aCredit)` du Blade).
      if (!_aCredit) ...[_champMode(), _champCompte()],
      _champCentre(),
      _champFournisseur(),
      if (_fournisseurId != null && _fournisseurId!.isNotEmpty) _champReglement(),
      _champBeneficiaire(),
    ];
    return ModaleAgri(
      titre: widget.enModification == null ? 'Nouvelle Dépense' : 'Modifier la Dépense',
      largeur: LargeurModale.xl,
      contenu: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Enregistrez une charge d'exploitation de trésorerie directe : une dépense, plusieurs lignes.",
            key: Key('depense-modale-aide'),
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.md),
          if (_erreurs['formulaire'] != null) ...[_erreur('formulaire'), const SizedBox(height: AgriSpacing.sm)],
          for (var i = 0; i < entete.length; i += large ? 2 : 1) ...[
            if (i > 0) const SizedBox(height: AgriSpacing.md),
            if (large)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: entete[i]),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(child: i + 1 < entete.length ? entete[i + 1] : const SizedBox.shrink()),
                ],
              )
            else
              entete[i],
          ],
          const SizedBox(height: AgriSpacing.md),
          _recu(),
          const SizedBox(height: AgriSpacing.md),
          _enTeteLignes(),
          _erreur('lignes'),
          const SizedBox(height: AgriSpacing.xs),
          const Row(
            children: [
              Expanded(flex: 5, child: Text('LIBELLÉ *', style: _titreColonne)),
              SizedBox(width: AgriSpacing.sm),
              Expanded(flex: 4, child: Text('COMPTE DE CHARGE *', style: _titreColonne)),
              SizedBox(width: AgriSpacing.sm),
              Expanded(flex: 2, child: Text('MONTANT (FCFA) *', style: _titreColonne)),
              SizedBox(width: 36),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          for (var i = 0; i < _lignes.length; i++) _ligne(i),
          _erreur('total'),
          Container(
            padding: const EdgeInsets.only(top: AgriSpacing.sm),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AgriColors.outlineVariant))),
            alignment: Alignment.centerRight,
            child: Text(
              'Total : ${PmpService.francs(_total.toDouble())} FCFA',
              key: const Key('depense-total'),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('bouton-enregistrer-depense'),
              onPressed: _enregistrement ? null : _enregistrer,
              icon: const Icon(SymbolesAgri.save, size: 18),
              label: const Text('Enregistrer la Dépense'),
              style: FilledButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold),
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.lg, vertical: AgriSpacing.sm),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
