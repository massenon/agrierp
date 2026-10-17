import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'fiche_fournisseur_modales.dart';
import 'fournisseurs_repository.dart';

/// `prototype_html/profile-fournisseur.html` → Profil Fournisseur.
///
/// Fiche du tiers : identité, « Solde Global Dû », et trois onglets — Achats ·
/// Dettes · Commandes. Ouvert depuis le nom d'un fournisseur de « Fiches
/// Fournisseurs », comme le lien de la page web.
///
/// ⚠️⚠️ **« SOLDE GLOBAL DÛ » EST NET DES RÈGLEMENTS EN ATTENTE** : le règlement saisi
/// ici est réel même si la ferme ne le connaît pas encore. L'afficher encore dû
/// inviterait à le payer deux fois.
///
/// ⚠️ **LES RÉFÉRENCES SONT DES TIRETS.** La maquette montre « ACH-2026-101 » et
/// « BC-2026-041 » ; ni `purchases` ni `purchase_orders` n'ont de colonne de
/// référence, au poste comme sur le serveur. La page web fabrique un préfixe d'UUID
/// (`ACH` + 8 caractères) que la ferme ne retrouve sur aucun document : le poste
/// n'en invente pas (même décision que « Liste d'Achats »). ARBITRAGE CLIENT.
///
/// ⚠️ « Modifier la fiche » ouvre la même modale que « Fiches Fournisseurs » (ticket
/// F0.71) : la fiche est écrite en attente, puis validée par le serveur.
class ProfilFournisseurScreen extends StatefulWidget {
  const ProfilFournisseurScreen({
    super.key,
    required this.depot,
    required this.fournisseurId,
    required this.onRetour,
  });

  final FournisseursRepository depot;
  final String fournisseurId;
  final VoidCallback onRetour;

  @override
  State<ProfilFournisseurScreen> createState() =>
      _ProfilFournisseurScreenState();
}

class _ProfilFournisseurScreenState extends State<ProfilFournisseurScreen> {
  static const onglets = ['Achats', 'Dettes', 'Commandes'];

  static const _entete = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );
  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  String _onglet = onglets.first;
  ProfilFournisseur? _profil;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  Future<void> _recharger() async {
    final profil = await widget.depot.profil(widget.fournisseurId);
    if (!mounted) return;
    setState(() {
      _profil = profil;
      _charge = true;
    });
  }

  static String _montant(double v) {
    final entier = v.round().abs().toString();
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v.round() < 0 ? '-' : ''}${groupes.join(' ')}';
  }

  static String _jour(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _initiales(String nom) => nom
      .split(' ')
      .where((m) => m.isNotEmpty)
      .take(2)
      .map((m) => m[0].toUpperCase())
      .join();

  Future<void> _modifierFiche(ProfilFournisseur p) async {
    final ecrit = await ouvrirFicheFournisseur(
      context: context,
      depot: widget.depot,
      existant: p.fournisseur,
    );
    if (ecrit) await _recharger();
  }

  Future<void> _ouvrirReglement(ProfilFournisseur p) async {
    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (_) =>
          _ModaleReglementProfil(depot: widget.depot, profil: p),
    );
    if (enregistre == true) await _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profil;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: !_charge
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(
                AgriBreakpoints.large(context)
                    ? AgriSpacing.lg
                    : AgriSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('profil-retour'),
                      onPressed: widget.onRetour,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text(
                        'Retour',
                        style: TextStyle(fontSize: AgriTypography.xs),
                      ),
                    ),
                  ),
                  const Text(
                    'Profil Fournisseur',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  const Text(
                    'Fiche complète, historique et créances du tiers.',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.md),
                  if (p == null)
                    const Text(
                      "— Ce fournisseur n'est plus au poste. Synchronisez. —",
                      key: Key('profil-introuvable'),
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontStyle: FontStyle.italic,
                        color: AgriColors.outline,
                      ),
                    )
                  else ...[
                    _carteIdentite(p),
                    const SizedBox(height: AgriSpacing.md),
                    _barreOnglets(),
                    const SizedBox(height: AgriSpacing.md),
                    switch (_onglet) {
                      'Dettes' => _dettes(p),
                      'Commandes' => _commandes(p),
                      _ => _achats(p),
                    },
                  ],
                ],
              ),
            ),
    );
  }

  BoxDecoration get _carte => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  Widget _carteIdentite(ProfilFournisseur p) => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte,
    child: Wrap(
      spacing: AgriSpacing.md,
      runSpacing: AgriSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: AgriColors.brandEmerald.withValues(alpha: 0.15),
          child: Text(
            _initiales(p.fournisseur.name),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.fournisseur.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              p.fournisseur.phone ?? '—',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
        if (p.fournisseur.category != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AgriColors.accentYellow.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AgriRadius.full),
            ),
            child: Text(
              p.fournisseur.category!,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Solde Global Dû',
              style: TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
            Text(
              '${_montant(p.soldeGlobal)} FCFA',
              key: const Key('profil-solde'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AgriColors.errorRed,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              key: const Key('profil-modifier'),
              onPressed: () => _modifierFiche(p),
              child: const Text('Modifier la fiche'),
            ),
            const SizedBox(width: AgriSpacing.sm),
            ElevatedButton(
              key: const Key('profil-reglement'),
              onPressed: () => _ouvrirReglement(p),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enregistrer un règlement'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Row(
      children: [
        for (final titre in onglets)
          InkWell(
            key: Key('profil-onglet-$titre'),
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
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: _onglet == titre
                      ? AgriColors.brandEmerald
                      : AgriColors.outline,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _tableau({
    required List<(String, int)> colonnes,
    required List<List<Widget>> lignes,
    required String vide,
  }) => Container(
    decoration: _carte,
    child: Column(
      children: [
        Container(
          color: AgriColors.surfaceZebra,
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Row(
            children: [
              for (final (libelle, flex) in colonnes)
                Expanded(
                  flex: flex,
                  child: Text(libelle.toUpperCase(), style: _entete),
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
        for (var i = 0; i < lignes.length; i++)
          Container(
            color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
            padding: const EdgeInsets.all(AgriSpacing.sm),
            child: Row(
              children: [
                for (var c = 0; c < lignes[i].length; c++)
                  Expanded(flex: colonnes[c].$2, child: lignes[i][c]),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _pastille(String texte, Color couleur) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        texte,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: couleur,
        ),
      ),
    ),
  );

  Widget _achats(ProfilFournisseur p) => _tableau(
    colonnes: const [
      ('Référence', 3),
      ('Date', 3),
      ('Catégorie', 3),
      ('Montant', 3),
      ('Statut', 4),
    ],
    vide: '— Aucun achat auprès de ce fournisseur —',
    lignes: [
      for (final a in p.achats)
        [
          const Text('—', style: _cellule),
          Text(_jour(a.achat.purchaseDate), style: _cellule),
          Text(p.categorieParAchat[a.achat.id] ?? '—', style: _cellule),
          Text(_montant(a.achat.total), style: _cellule),
          _pastille(
            a.statut,
            !a.envoye
                ? AgriColors.brandForest
                : (a.achat.hasDebt
                      ? AgriColors.errorRed
                      : AgriColors.brandEmerald),
          ),
        ],
    ],
  );

  Widget _dettes(ProfilFournisseur p) {
    if (p.dettes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        decoration: _carte,
        child: const Text(
          'Aucune dette active auprès de ce fournisseur — tous les achats '
          'sont réglés.',
          key: Key('profil-sans-dette'),
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontStyle: FontStyle.italic,
            color: AgriColors.outline,
          ),
        ),
      );
    }

    return _tableau(
      colonnes: const [('Facture', 4), ('Échéance', 4), ('Solde Dû', 4)],
      vide: '',
      lignes: [
        for (final d in p.dettes)
          [
            const Text('—', style: _cellule),
            Text(_jour(d.dette.dueDate), style: _cellule),
            Text(_montant(d.montantDu), style: _cellule),
          ],
      ],
    );
  }

  Widget _commandes(ProfilFournisseur p) => _tableau(
    colonnes: const [
      ('BC N°', 3),
      ('Émission', 3),
      ('Livraison', 3),
      ('Statut', 3),
    ],
    vide: '— Aucun bon de commande pour ce fournisseur —',
    lignes: [
      for (final c in p.commandes)
        [
          const Text('—', style: _cellule),
          Text(_jour(c.createdAt), style: _cellule),
          Text(_jour(c.expectedDeliveryDate), style: _cellule),
          _pastille(switch (c.status) {
            'recu' => 'Reçu',
            null => '—',
            final s => '${s[0].toUpperCase()}${s.substring(1)}',
          }, c.status == 'recu' ? AgriColors.brandEmerald : AgriColors.outline),
        ],
    ],
  );
}

/// Modale « Enregistrer un Règlement » du profil : le fournisseur est celui de la
/// fiche, on ne le choisit pas.
///
/// ⚠️ Montant refusé AVANT écriture s'il dépasse le solde dû ; le message reste
/// dans la modale, la saisie n'est pas effacée.
class _ModaleReglementProfil extends StatefulWidget {
  const _ModaleReglementProfil({required this.depot, required this.profil});

  final FournisseursRepository depot;
  final ProfilFournisseur profil;

  @override
  State<_ModaleReglementProfil> createState() => _ModaleReglementProfilState();
}

class _ModaleReglementProfilState extends State<_ModaleReglementProfil> {
  final _montant = TextEditingController();
  String _compte = '';
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final montant = double.tryParse(_montant.text.trim().replaceAll(',', '.'));
    if (montant == null || _compte.isEmpty) {
      setState(() => _erreur = 'Montant et compte de trésorerie obligatoires.');
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      await widget.depot.enregistrerReglement(
        fournisseurId: widget.profil.fournisseur.id,
        montant: montant,
        compteId: _compte,
        date: DateTime.now(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ReglementRefuse catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.motif;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: 'Enregistrer un Règlement',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Solde global dû',
                style: TextStyle(fontSize: AgriTypography.xs),
              ),
              Text(
                '${_ProfilFournisseurScreenState._montant(widget.profil.soldeGlobal)} FCFA',
                key: const Key('reglement-profil-solde'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Montant du Règlement (FCFA)',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          TextField(
            key: const Key('reglement-profil-montant'),
            controller: _montant,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: AgriTypography.xs),
            decoration: const InputDecoration(
              hintText: 'Saisir le montant...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Compte de Trésorerie',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('reglement-profil-compte'),
            initialValue: _compte,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('-- Sélectionner --'),
              ),
              for (final c in widget.profil.comptes)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _compte = v ?? ''),
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                _erreur!,
                key: const Key('reglement-profil-erreur'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.errorDeep,
                ),
              ),
            ),
        ],
      ),
      actions: [
        BoutonModalePrimaire(
          key: const Key('reglement-profil-valider'),
          libelle: 'Valider le Règlement',
          onPressed: _envoi ? null : _valider,
        ),
      ],
    );
  }
}
