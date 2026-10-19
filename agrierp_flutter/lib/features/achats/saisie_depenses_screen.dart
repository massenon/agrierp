import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'depenses_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/saisie-depenses.html` → Saisie des Dépenses.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. « Indicateurs de performance » — Dépenses du mois · Charges Fixes ·
///      Charges Variables ;
///   2. « Nouvelle Dépense » : Date de la Transaction * · Libellé de la
///      Dépense * · Catégorie de Charges (SYSCOHADA) * · Montant Décaissé
///      (FCFA) * · Compte de Trésorerie Débité * · Reçu / Facture (Photo) ·
///      bouton « Enregistrer la Dépense » ;
///   3. le tableau — Date · Libellé · Catégorie · Montant · Statut · Actions.
///
/// ⚠️ **LE TABLEAU NE MONTRE QUE LES DÉPENSES DE CE POSTE.** Le contrat de
/// synchronisation ne redescend pas celles du serveur. Le dire est
/// indispensable : sans cela la liste se lit comme un état complet, et une
/// dépense saisie sur le web paraîtra manquante.
///
/// ⚠️ **CHARGES FIXES / VARIABLES : ARBITRAGE CLIENT EN ATTENTE.** Le
/// classement d'une charge en fixe ou variable n'est défini nulle part — ni
/// dans le CDC, ni dans le référentiel. Les deux cartes affichent « — » plutôt
/// qu'un montant réparti au jugé, qui donnerait une structure de coûts fausse.
///
/// ⚠️ **LE JUSTIFICATIF PHOTO N'EST PAS PORTÉ PAR LA SYNCHRONISATION.**
/// `receipt_path` existe côté serveur mais le contrat ne transporte aucun
/// fichier. Le champ est présent, à sa place, et annonce la limite — au lieu
/// d'accepter une photo qui ne partirait jamais.
class SaisieDepensesScreen extends StatefulWidget {
  const SaisieDepensesScreen({super.key, required this.depot});

  final DepensesRepository depot;

  @override
  State<SaisieDepensesScreen> createState() => _SaisieDepensesScreenState();
}

class _SaisieDepensesScreenState extends State<SaisieDepensesScreen> {
  List<ExpenseCategory> _categories = const [];
  List<TreasuryAccount> _comptes = const [];
  List<Expense> _depenses = const [];
  double _totalDuMois = 0;

  DateTime _date = HeureBenin.aujourdhui();
  final _libelle = TextEditingController();
  String? _categorie;
  final _montant = TextEditingController();
  String? _compteId;

  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _libelle.dispose();
    _montant.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final categories = await widget.depot.categories();
    final comptes = await widget.depot.comptesTresorerie();
    final depenses = await widget.depot.mesDepenses();
    final total = await widget.depot.totalDuMois(HeureBenin.maintenant());

    if (!mounted) return;

    setState(() {
      _categories = categories;
      _comptes = comptes;
      _depenses = depenses;
      _totalDuMois = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(),
            const SizedBox(height: AgriSpacing.lg),
            _indicateurs(),
            const SizedBox(height: AgriSpacing.lg),
            _formulaire(),
            const SizedBox(height: AgriSpacing.lg),
            _tableau(),
          ],
        ),
      ),
    );
  }

  Widget _enTete() {
    return const Row(
      children: [
        Icon(SymbolesAgri.payments, color: AgriColors.brandEmerald, size: 26),
        SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            'Saisie des Dépenses',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    );
  }

  /// « Indicateurs de performance » — trois cartes, dans l'ordre de la maquette.
  Widget _indicateurs() {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.moyen(context) ? 3 : 1;
        final largeur =
            (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(SymbolesAgri.bar_chart, size: 18, color: AgriColors.brandEmerald),
                SizedBox(width: AgriSpacing.xs),
                Text(
                  'Indicateurs de performance',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.sm),
            Wrap(
              spacing: AgriSpacing.md,
              runSpacing: AgriSpacing.md,
              children: [
                _carteKpi(
                  largeur: largeur,
                  libelle: 'Dépenses du mois',
                  valeur: '${_montantFormate(_totalDuMois)} F',
                  icone: SymbolesAgri.payments,
                  couleur: AgriColors.brandEmerald,
                ),
                // ⚠️ « — » ET NON UN MONTANT : le classement fixe/variable
                // n'est défini nulle part. Répartir au jugé donnerait une
                // structure de coûts fausse, et personne ne le verrait.
                _carteKpi(
                  largeur: largeur,
                  libelle: 'Charges Fixes',
                  valeur: '—',
                  icone: SymbolesAgri.event_repeat,
                  couleur: AgriColors.infoBlue,
                  note: 'classement à arbitrer',
                ),
                _carteKpi(
                  largeur: largeur,
                  libelle: 'Charges Variables',
                  valeur: '—',
                  icone: SymbolesAgri.trending_down,
                  couleur: AgriColors.accentYellow,
                  couleurIcone: AgriColors.brandForest,
                  note: 'classement à arbitrer',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _carteKpi({
    required double largeur,
    required String libelle,
    required String valeur,
    required IconData icone,
    required Color couleur,
    Color? couleurIcone,
    String? note,
  }) => SizedBox(
    width: largeur,
    child: CarteKpi(
      libelle: libelle,
      valeur: valeur,
      legende: note,
      icone: icone,
      couleurLisere: couleur,
      couleurIcone: couleurIcone ?? AgriColors.brandEmerald,
    ),
  );

  /// « Nouvelle Dépense ».
  Widget _formulaire() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  SymbolesAgri.add_circle,
                  color: AgriColors.brandEmerald,
                  size: 20,
                ),
                SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    'Nouvelle Dépense',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              "Enregistrez une charge d'exploitation de trésorerie directe.",
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
            const Divider(),
            if (_categories.isEmpty || _comptes.isEmpty) ...[
              // ⚠️ SANS RÉFÉRENTIEL, PAS DE SAISIE — et on dit pourquoi. Un
              // formulaire vide laisserait croire à une panne de l'écran.
              Container(
                padding: const EdgeInsets.all(AgriSpacing.md),
                decoration: BoxDecoration(
                  color: AgriColors.accentYellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: const Text(
                  'Comptes de charge ou de trésorerie non reçus : synchronisez '
                  'le poste avant de saisir une dépense.',
                  style: TextStyle(fontSize: 11, color: AgriColors.brandForest),
                ),
              ),
            ] else ...[
              _champDate(),
              const SizedBox(height: AgriSpacing.sm),
              _champTexte(
                libelle: 'Libellé de la Dépense *',
                controleur: _libelle,
                indice: 'ex : Sac de provende ponte',
                cle: 'libelle',
              ),
              const SizedBox(height: AgriSpacing.sm),
              _champListe(
                libelle: 'Catégorie de Charges (SYSCOHADA) *',
                cle: 'categorie',
                valeur: _categorie,
                options: _categories.map((c) => (c.label, c.label)).toList(),
                surChangement: (v) => setState(() => _categorie = v),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _champTexte(
                libelle: 'Montant Décaissé (FCFA) *',
                controleur: _montant,
                indice: 'ex : 25000',
                cle: 'montant',
                nombre: true,
              ),
              const SizedBox(height: AgriSpacing.sm),
              _champListe(
                libelle: 'Compte de Trésorerie Débité *',
                cle: 'compte',
                valeur: _compteId,
                options: _comptes
                    .map(
                      (c) => (
                        c.id,
                        c.accountCode == null
                            ? c.label
                            : '${c.label} (${c.accountCode})',
                      ),
                    )
                    .toList(),
                surChangement: (v) => setState(() => _compteId = v),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _recu(),
              if (_erreur != null) ...[
                const SizedBox(height: AgriSpacing.sm),
                Text(
                  _erreur!,
                  key: const Key('erreur-depense'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AgriColors.errorDeep,
                  ),
                ),
              ],
              const SizedBox(height: AgriSpacing.md),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  key: const Key('bouton-enregistrer-depense'),
                  onPressed: _enregistrement ? null : _enregistrer,
                  icon: const Icon(SymbolesAgri.save, size: 18),
                  label: const Text('Enregistrer la Dépense'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AgriRadius.lg),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _etiquette(String texte) => Text(
    texte.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      color: AgriColors.brandForest,
    ),
  );

  Widget _champDate() {
    final j = _date.day.toString().padLeft(2, '0');
    final m = _date.month.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette('Date de la Transaction *'),
        const SizedBox(height: 4),
        InkWell(
          key: const Key('champ-date'),
          onTap: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(_date.year - 2),
              lastDate: HeureBenin.maintenant(),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Text(
              '$j/$m/${_date.year}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _champTexte({
    required String libelle,
    required TextEditingController controleur,
    required String indice,
    required String cle,
    bool nombre = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: TextField(
            key: Key('champ-$cle'),
            controller: controleur,
            keyboardType: nombre ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: indice,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _champListe({
    required String libelle,
    required String cle,
    required String? valeur,
    required List<(String, String)> options,
    required ValueChanged<String?> surChangement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        const SizedBox(height: 4),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: Key('liste-$cle'),
              isExpanded: true,
              value: valeur,
              hint: const Text(
                '-- Sélectionner --',
                style: TextStyle(fontSize: 14, color: AgriColors.outline),
              ),
              style: const TextStyle(fontSize: 14, color: AgriColors.onSurface),
              items: options
                  .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                  .toList(),
              onChanged: surChangement,
            ),
          ),
        ),
      ],
    );
  }

  /// ⚠️ LE CHAMP EST LÀ, SA LIMITE EST DITE. Accepter une photo qui ne partirait
  /// jamais serait pire que ne pas l'offrir : l'animalier croirait le
  /// justificatif transmis.
  Widget _recu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette('Reçu / Facture (Photo)'),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.surfaceZebra,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: const Row(
            children: [
              Icon(SymbolesAgri.add_a_photo, size: 18, color: AgriColors.outline),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  'Le justificatif ne peut pas encore être transmis depuis le '
                  "poste : la synchronisation ne transporte aucun fichier. "
                  "Joignez-le depuis l'application web.",
                  style: TextStyle(fontSize: 10.5, color: AgriColors.outline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableau() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Dépenses de l'exploitation",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
            // Ticket U13 — les dépenses du web et des autres postes descendent au poste (archivées exclues) : la liste
            // est celle de l'exploitation au dernier tirage, plus les saisies d'ici pas encore envoyées.
            const Text(
              'Dépenses du web et de tous les postes au dernier tirage, plus celles saisies ici en attente '
              "d'envoi.",
              style: TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
            const SizedBox(height: AgriSpacing.sm),
            if (_depenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AgriSpacing.md),
                child: Text(
                  'Aucune dépense pour le moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              )
            else
              Table(
                border: TableBorder.all(color: AgriColors.outlineVariant),
                columnWidths: const {
                  0: FlexColumnWidth(1.4),
                  1: FlexColumnWidth(3),
                  2: FlexColumnWidth(2.4),
                  3: FlexColumnWidth(1.6),
                  4: FlexColumnWidth(1.6),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: AgriColors.surfaceZebra),
                    children: [
                      _CelluleEntete('Date'),
                      _CelluleEntete('Libellé'),
                      _CelluleEntete('Catégorie'),
                      _CelluleEntete('Montant'),
                      _CelluleEntete('Statut'),
                    ],
                  ),
                  for (final d in _depenses)
                    TableRow(
                      children: [
                        _Cellule(_dateCourte(d.expenseDate)),
                        _Cellule(d.label),
                        _Cellule(d.category),
                        _Cellule(
                          '${_montantFormate(d.amount)} F',
                          centre: true,
                          gras: true,
                        ),
                        _Cellule(_statut(d), centre: true),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// ⚠️ TANT QU'ELLE N'EST PAS PARTIE, LE STATUT DIT L'ÉTAT D'ENVOI : au poste, une dépense en attente n'engage
  /// encore rien ; afficher « Payée » laisserait croire le décaissement fait. Ticket U13 — une dépense CONNUE du
  /// serveur (descendue du web, d'un autre poste, ou acquittée) y est « Payée » : le serveur décaisse toute dépense
  /// reçue (`status = 'payee'`), c'est le badge du Blade.
  String _statut(Expense d) {
    return switch (d.syncStatus) {
      SyncStatus.pending => 'À envoyer',
      SyncStatus.synced => 'Payée',
      SyncStatus.conflict => 'Refusée',
    };
  }

  String _dateCourte(DateTime d) {
    final j = d.day.toString().padLeft(2, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$j/$m/${d.year}';
  }

  String _montantFormate(double montant) {
    final entier = montant.round().toString();
    final tampon = StringBuffer();

    for (var i = 0; i < entier.length; i++) {
      if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(' ');
      tampon.write(entier[i]);
    }

    return tampon.toString();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      await widget.depot.enregistrer(
        date: _date,
        libelle: _libelle.text,
        categorie: _categorie ?? '',
        montant: double.tryParse(_montant.text.replaceAll(',', '.')) ?? 0,
        compteTresorerieId: _compteId ?? '',
      );

      if (!mounted) return;

      _libelle.clear();
      _montant.clear();
      setState(() {
        _categorie = null;
        _compteId = null;
        _enregistrement = false;
      });

      await _charger();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dépense enregistrée — elle partira à la '
            'prochaine synchronisation.',
          ),
        ),
      );
    } on DepenseRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.motif;
        _enregistrement = false;
      });
    }
  }
}

class _CelluleEntete extends StatelessWidget {
  const _CelluleEntete(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: AgriColors.outline,
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(this.texte, {this.centre = false, this.gras = false});

  final String texte;
  final bool centre;
  final bool gras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte,
        textAlign: centre ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 11,
          fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          color: gras ? AgriColors.brandForest : AgriColors.onSurface,
        ),
      ),
    );
  }
}
