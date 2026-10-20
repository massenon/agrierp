import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'caisse_repository.dart';
import 'caisse_screen.dart';
import 'ventes_devis_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/ventes-devis.html` → Ventes & Devis.
///
/// ⚠️⚠️ **HUB À QUATRE ONGLETS, DANS L'ORDRE DE LA MAQUETTE** : Enregistrer
/// Vente · Devis Prestations · Historique des Ventes · Retours et Avoirs. Le
/// hub charge quatre `<iframe>` (`pos-interface`, `devis`,
/// `historique-ventes`, `retours-avoirs`) ; la barre latérale ne porte qu'une
/// entrée.
///
/// 🔴→✅ **L'ENTRÉE DE MENU OUVRAIT DIRECTEMENT LA CAISSE**, sautant le hub :
/// l'utilisateur n'avait aucun chemin vers l'historique de ses propres ventes.
/// La caisse est désormais le PREMIER ONGLET de ce hub, comme dans la
/// maquette — l'écran lui-même est inchangé.
class VentesDevisScreen extends StatefulWidget {
  const VentesDevisScreen({
    super.key,
    required this.depot,
    required this.caisse,
  });

  final VentesDevisRepository depot;
  final CaisseRepository caisse;

  @override
  State<VentesDevisScreen> createState() => _VentesDevisScreenState();
}

class _VentesDevisScreenState extends State<VentesDevisScreen> {
  /// Les quatre onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Enregistrer Vente', SymbolesAgri.point_of_sale),
    ('Devis Prestations', SymbolesAgri.description),
    ('Historique des Ventes', SymbolesAgri.receipt_long),
    ('Retours et Avoirs', SymbolesAgri.assignment_return),
  ];

  String _onglet = onglets.first.$1;
  String _statut = '';
  String _mode = '';

  DonneesHistorique? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _barreOnglets(),
          Expanded(
            child: switch (_onglet) {
              'Devis Prestations' => _ongletIndisponible(
                titre: 'Devis Prestations',
                icone: SymbolesAgri.description,
                sousTitre: 'Devis et proformas adressés aux clients.',
                raison:
                    'Un devis se négocie au bureau, avec la fiche du client '
                    'sous les yeux : ni le catalogue de devis ni le fichier '
                    'clients ne descendent au poste. Le proposer ici sans '
                    'client à qui l\'adresser produirait un document '
                    'incomplet.',
                cle: 'devis-non-embarque',
              ),
              'Historique des Ventes' => _ongletHistorique(),
              'Retours et Avoirs' => _ongletIndisponible(
                titre: 'Retours et Avoirs',
                icone: SymbolesAgri.assignment_return,
                sousTitre: 'Retours de marchandise et notes de crédit.',
                // ⚠️ UN AVOIR N'EST PAS UNE LIGNE DE PLUS : il rend le stock,
                // annule une créance et passe son écriture comptable. Le
                // poste ne tient ni comptabilité ni créances : l'enregistrer
                // ici laisserait trois effets sur quatre non faits.
                raison:
                    'Un avoir rend le stock, annule une créance et passe son '
                    'écriture comptable. Le poste ne tient ni comptabilité '
                    'ni créances : l\'enregistrer ici laisserait la plupart '
                    'de ses effets non faits, et le déséquilibre ne se '
                    'verrait qu\'au rapprochement.',
                cle: 'avoirs-non-embarque',
              ),
              _ => CaisseScreen(depot: widget.caisse),
            },
          ),
        ],
      ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-ventes-$titre'),
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
                    const SizedBox(width: 4),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
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

  // ── Onglet Historique des Ventes ──────────────────────────────────────────

  Widget _ongletHistorique() {
    final d = _donnees;
    if (d == null) return const Center(child: CircularProgressIndicator());

    return Builder(
      // ⚠️ `Builder` ET NON `LayoutBuilder` : la mise en page se
      // décide sur la largeur de l'ÉCRAN (MediaQuery), jamais sur
      // celle du contenu. Retirer les contraintes de la portée
      // interdit la rechute.
      builder: (context) {
        final large = AgriBreakpoints.large(context);

        return SingleChildScrollView(
          padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _entete(large),
              const SizedBox(height: AgriSpacing.lg),
              _kpis(d, large),
              const SizedBox(height: AgriSpacing.lg),
              _filtres(),
              const SizedBox(height: AgriSpacing.md),
              _tableau(d),
            ],
          ),
        );
      },
    );
  }

  Widget _entete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              SymbolesAgri.receipt_long,
              size: 26,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Historique des Ventes',
              style: TextStyle(
                fontSize: large ? 24 : 20,
                fontWeight: FontWeight.bold,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        // ⚠️⚠️ LA MAQUETTE ÉCRIT « Toutes les ventes enregistrées de
        // l'entreprise ». Au poste c'est FAUX : le tirage ne descend pas
        // `sales`, et l'historique local ne contient que les
        // encaissements de CE poste. Recopier la phrase ferait croire à
        // un gérant qu'il lit le chiffre de la ferme.
        const Text(
          'Ventes encaissées sur ce poste. Celles du comptoir web et des '
          'autres postes ne descendent pas ici.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  Widget _kpis(DonneesHistorique d, bool large) => GridView.count(
    crossAxisCount: large ? 4 : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.6 : 1.7,
    children: [
      _carteKpi(
        "Chiffre d'Affaires",
        '${_montant(d.chiffreAffaires)} FCFA',
        AgriColors.brandEmerald,
      ),
      _carteKpi('Transactions', '${d.transactions}', AgriColors.infoBlue),
      _carteKpi(
        'Panier Moyen',
        // ⚠️ Aucune vente : « 0 FCFA » se lirait comme un panier vide.
        d.panierMoyen == null ? '—' : '${_montant(d.panierMoyen!)} FCFA',
        AgriColors.accentYellow,
      ),
      // 🔴→✅ TICKET F0.43 — L'ENCOURS EST RÉEL. `receivables` descend au
      // poste depuis le ticket 14.75 ; cette carte portait un tiret parce
      // que la table n'arrivait pas, pas parce que la donnée manquait.
      //
      // ⚠️ **LE RESTE DÛ, PAS LE MONTANT FACTURÉ.**
      _carteKpi(
        'Encours Créances',
        '${_montant(d.encoursCreances)} FCFA',
        AgriColors.errorRed,
      ),
    ],
  );

  Widget _carteKpi(
    String libelle,
    String valeur,
    Color barre, {
    String legende = '',
  }) => CarteKpi(
    key: Key('kpi-$libelle'),
    libelle: libelle,
    valeur: valeur,
    legende: legende,
    couleurLisere: barre,
  );

  Widget _filtres() => Container(
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
        _menu(
          cle: 'filtre-statut',
          valeur: _statut,
          defaut: 'Statut : Toutes',
          options: VentesDevisRepository.statuts,
          surChangement: (v) => setState(() => _statut = v),
        ),
        _menu(
          cle: 'filtre-mode',
          valeur: _mode,
          defaut: 'Mode : Tous',
          options: VentesDevisRepository.modes,
          surChangement: (v) => setState(() => _mode = v),
        ),
        // ⚠️⚠️ LE FILTRE CLIENT EST INERTE : `customers` ne descend pas au
        // poste. Un menu qui ne proposerait que « Tous » serait un piège ;
        // désactivé, il dit que le filtre existe et pourquoi il ne
        // fonctionne pas ici.
        Opacity(
          opacity: 0.5,
          child: Container(
            key: const Key('filtre-client'),
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              'Client : Tous',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ),
        ),
        TextButton(
          key: const Key('reinitialiser'),
          onPressed: () => setState(() {
            _statut = '';
            _mode = '';
          }),
          child: const Text(
            'Réinitialiser',
            style: TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        _boutonInerte(SymbolesAgri.table_view, 'Excel (.xlsx)'),
        _boutonInerte(SymbolesAgri.picture_as_pdf, 'PDF'),
      ],
    ),
  );

  Widget _menu({
    required String cle,
    required String valeur,
    required String defaut,
    required List<String> options,
    required void Function(String) surChangement,
  }) => Container(
    key: Key(cle),
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: valeur,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.onSurface,
        ),
        items: [
          DropdownMenuItem(value: '', child: Text(defaut)),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => surChangement(v ?? ''),
      ),
    ),
  );

  Widget _boutonInerte(IconData icone, String libelle) => Opacity(
    opacity: 0.5,
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icone, size: 18),
      label: Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AgriColors.brandForest,
        side: const BorderSide(color: AgriColors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
      ),
    ),
  );

  /// Correspondance entre les libellés du filtre et les valeurs stockées.
  ///
  /// ⚠️ La caisse enregistre `especes`, `mobile_money`… ; la maquette affiche
  /// « Espèces », « Mobile Money ». Comparer les deux directement ne filtrerait
  /// jamais rien — et un filtre qui ne filtre pas est pire qu'absent.
  static const _valeurMode = {
    'Espèces': 'especes',
    'Mobile Money': 'mobile_money',
    'Virement': 'virement',
    'Crédit client': 'credit',
  };

  static const _valeurStatut = {
    'Payée': 'validee',
    'En attente': 'en_attente',
    'Annulée': 'annulee',
  };

  List<LigneHistorique> _filtrees(DonneesHistorique d) => d.lignes.where((l) {
    if (_statut.isNotEmpty && l.vente.status != _valeurStatut[_statut]) {
      return false;
    }
    if (_mode.isNotEmpty && l.vente.paymentMode != _valeurMode[_mode]) {
      return false;
    }
    return true;
  }).toList();

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  Widget _tableau(DonneesHistorique d) {
    final lignes = _filtrees(d);

    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1180,
          child: Column(
            children: [
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('FACTURE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('CLIENT', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('DATE', style: _enteteColonne),
                    ),
                    Expanded(child: Text('ARTICLES', style: _enteteColonne)),
                    Expanded(
                      flex: 2,
                      child: Text('REMISE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('TOTAL TTC', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('PAYÉ', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('RESTE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('MODE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STATUT', style: _enteteColonne),
                    ),
                    Expanded(child: Text('ACTIONS', style: _enteteColonne)),
                  ],
                ),
              ),
              if (lignes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AgriSpacing.lg),
                  child: Text(
                    '— Aucune vente encaissée sur ce poste pour ces critères —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              for (var i = 0; i < lignes.length; i++) _ligne(lignes[i], i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ligne(LigneHistorique l, int index) => Container(
    key: Key('vente-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        // ⚠️⚠️ AUCUN NUMÉRO DE FACTURE N'EXISTE — ni au poste, ni dans
        // `sales` côté serveur, ni dans le POS Livewire (ticket 14.71).
        // La maquette affiche « V-2026-0884 » : c'est un libellé
        // décoratif. L'identité de la vente, ici, c'est sa date et son
        // heure.
        const Expanded(
          flex: 2,
          child: Text('—', style: TextStyle(fontSize: AgriTypography.xs)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            // ⚠️ Le fichier clients ne descend pas : une vente rattachée à
            // un client ne peut pas être nommée ici.
            l.vente.customerId == null
                ? 'Client Anonyme'
                : 'Client non synchronisé',
            style: const TextStyle(fontSize: AgriTypography.xs),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            _horodatage(l.vente.soldAt),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          child: Text(
            '${l.nombreArticles}',
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            _montant(l.vente.discount),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            _montant(l.vente.total),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            l.paye == null ? '—' : _montant(l.paye!),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            l.reste == null ? '—' : _montant(l.reste!),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            l.vente.paymentMode,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(flex: 2, child: _pastilleStatut(l.vente.status)),
        const Expanded(
          child: Opacity(
            opacity: 0.4,
            child: Icon(
              SymbolesAgri.picture_as_pdf,
              size: 16,
              color: AgriColors.outline,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pastilleStatut(String statut) {
    final (libelle, couleur) = switch (statut) {
      'annulee' => ('Annulée', AgriColors.errorDeep),
      'en_attente' => ('En attente', AgriColors.accentYellow),
      _ => ('Payée', AgriColors.brandEmerald),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          border: Border.all(color: couleur.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      ),
    );
  }

  // ── Onglets non embarqués ─────────────────────────────────────────────────

  Widget _ongletIndisponible({
    required String titre,
    required String sousTitre,
    required String raison,
    required IconData icone,
    required String cle,
  }) => SingleChildScrollView(
    padding: const EdgeInsets.all(AgriSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: AgriSpacing.md),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AgriColors.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 26, color: AgriColors.brandEmerald),
                  const SizedBox(width: AgriSpacing.xs),
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                sousTitre,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        Container(
          key: Key(cle),
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '— Module non embarqué au poste —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
              Text(
                raison,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Formats ───────────────────────────────────────────────────────────────

  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
