import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import 'fiche_fournisseur_modales.dart';
import 'fournisseurs_repository.dart';
import 'profil_fournisseur_screen.dart';

/// `prototype_html/fournisseurs.html` → Fournisseurs.
///
/// ⚠️⚠️ **HUB À TROIS ONGLETS**, dans l'ordre du hub : Ajouter Fournisseur ·
/// Fiches Fournisseurs · Dettes Fournisseurs — chargés en `<iframe>` par la
/// maquette (`ajouter-fournisseur`, `fiches-fournisseurs`,
/// `dettes-fournisseurs`).
///
/// ⚠️⚠️ **LES FICHES FOURNISSEURS S'ÉCRIVENT AU POSTE (ticket F0.71), EN ATTENTE
/// D'ENVOI** : créées, modifiées ou archivées localement, puis validées par le serveur
/// à la synchronisation — comme les produits. Pas d'import (Laravel n'en a pas), pas
/// de suppression définitive : archiver suffit et ne détruit rien.
///
/// ⚠️⚠️ **LE RÈGLEMENT D'UNE DETTE EST ENREGISTRÉ AU POSTE (ticket F0.69), EN
/// ATTENTE D'ENVOI.** Le poste ne décaisse rien et n'impute rien : il note « tant, à
/// ce fournisseur, depuis ce compte ». Le serveur impute sur les dettes les plus
/// anciennes, décaisse le compte et passe l'écriture ; l'ardoise affichée déduit en
/// attendant les règlements non encore acquittés, pour ne pas inviter à payer deux
/// fois.
class FournisseursScreen extends StatefulWidget {
  const FournisseursScreen({super.key, required this.depot});

  final FournisseursRepository depot;

  @override
  State<FournisseursScreen> createState() => _FournisseursScreenState();
}

class _FournisseursScreenState extends State<FournisseursScreen> {
  /// Les trois onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Ajouter Fournisseur', Icons.person_add),
    ('Fiches Fournisseurs', Icons.contact_page),
    ('Dettes Fournisseurs', Icons.account_balance_wallet),
  ];

  String _onglet = onglets.first.$1;
  DonneesFournisseurs? _donnees;

  /// Profil ouvert (`profile-fournisseur.html`), `null` : le hub.
  String? _profil;

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
    final d = _donnees;

    if (_profil != null) {
      return ProfilFournisseurScreen(
        depot: widget.depot,
        fournisseurId: _profil!,
        onRetour: () {
          setState(() => _profil = null);
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
                        'Fiches Fournisseurs' => _ongletFiches(d, large),
                        'Dettes Fournisseurs' => _ongletDettes(d, large),
                        _ => _ongletAjouter(d, large),
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
              key: Key('onglet-fournisseurs-$titre'),
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

  // ── Onglet 1 : Ajouter Fournisseur ────────────────────────────────────────

  Widget _ongletAjouter(DonneesFournisseurs d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Fournisseurs — Ajout', large),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES DEUX CARTES DE `ajouter-fournisseur.html`, dans son ordre et
      // avec ses icônes (`local_shipping`, `person_add`). Elles manquaient
      // depuis le portage de l'écran : c'est le comptage du ticket F0.54 qui
      // les a trouvées, rien d'autre ne les signalait.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-ajouter-actifs'),
          libelle: 'Fournisseurs actifs',
          valeur: '${d.fournisseursActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.local_shipping,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-ajouter-nouveaux'),
          libelle: 'Nouveaux (mois)',
          // ⚠️⚠️ UN TIRET, JAMAIS UN ZÉRO. `created_at` ne descend pas au
          // poste : « 0 » affirmerait qu'aucun fournisseur n'est arrivé ce
          // mois-ci, alors que le poste n'en sait simplement rien.
          valeur: d.nouveauxDuMois == null ? '—' : '${d.nouveauxDuMois}',
          legende: "Date d'entrée non transmise au poste",
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.person_add,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      Align(alignment: Alignment.centerRight, child: _boutonNouveau(d)),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 900,
        colonnes: const [
          ('Nom', 4),
          ('Contact', 4),
          ('Catégorie', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun fournisseur synchronisé —',
        lignes: [
          for (var i = 0; i < d.fournisseurs.length; i++)
            _ligne(i, [
              (
                // Le nom ouvre le profil, comme le lien de la page web.
                InkWell(
                  key: Key('profil-fournisseur-$i'),
                  onTap: () => setState(
                    () => _profil = d.fournisseurs[i].fournisseur.id,
                  ),
                  child: Text(
                    d.fournisseurs[i].fournisseur.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
                4,
              ),
              (
                Text(
                  d.fournisseurs[i].fournisseur.phone ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  d.fournisseurs[i].fournisseur.category ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (_statutFiche(d.fournisseurs[i]), 3),
              (_actionsFiche(d.fournisseurs[i].fournisseur), 2),
            ]),
        ],
      ),
    ],
  );

  // ── Onglet 2 : Fiches Fournisseurs ────────────────────────────────────────

  Widget _ongletFiches(DonneesFournisseurs d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Fiches Fournisseurs', large),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES DEUX CARTES DE `fiches-fournisseurs.html` (`local_shipping`,
      // `payments`). « Fournisseurs actifs » est la MÊME que sur l'onglet
      // précédent — la maquette la répète, le poste aussi : la retirer ici
      // ferait un onglet à une carte là où elle en montre deux.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-fiches-actifs'),
          libelle: 'Fournisseurs actifs',
          valeur: '${d.fournisseursActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.local_shipping,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-fiches-volume'),
          libelle: "Volume d'achat (mois)",
          valeur: _montant(d.volumeAchatDuMois),
          unite: 'F',
          legende: 'Achats présents sur ce poste',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.payments,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerRight,
        child: _boutonNouveau(d, cle: 'nouveau-fournisseur-fiches'),
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ('Nom', 4),
          ('Catégorie', 3),
          ('Total Achats (Année)', 3),
          ('Dernière commande', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun fournisseur synchronisé —',
        lignes: [
          for (var i = 0; i < d.fournisseurs.length; i++)
            _ligne(i, [
              (
                // Le nom ouvre le profil, comme le lien de la page web.
                InkWell(
                  key: Key('profil-fournisseur-$i'),
                  onTap: () => setState(
                    () => _profil = d.fournisseurs[i].fournisseur.id,
                  ),
                  child: Text(
                    d.fournisseurs[i].fournisseur.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
                4,
              ),
              (
                Text(
                  d.fournisseurs[i].fournisseur.category ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  _montant(d.fournisseurs[i].totalAchatsAnnee),
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  _date(d.fournisseurs[i].derniereCommande),
                  style: _cellule,
                ),
                3,
              ),
              (_statutFiche(d.fournisseurs[i]), 3),
              (_actionsFiche(d.fournisseurs[i].fournisseur), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ « Total Achats (Année) » compte les achats PRÉSENTS AU POSTE : le
      // premier tirage les descend tous, chaque tirage incrémental apporte les
      // nouveaux. Un achat encore en attente d'envoi y figure aussi — il est
      // réel, même si la ferme ne le connaît pas encore.
      _mentionPoste(
        "Le total de l'année se calcule sur les achats connus de ce poste, "
        'achats en attente de synchronisation compris. L\'import n\'existe pas '
        'encore côté serveur ; l\'export PDF et la suppression définitive ne '
        'sont pas disponibles au poste (archiver ne supprime rien).',
      ),
    ],
  );

  // ── Onglet 3 : Dettes Fournisseurs ────────────────────────────────────────

  Widget _ongletDettes(DonneesFournisseurs d, bool large) {
    final jour = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _titre('Dettes Fournisseurs', large)),
            ElevatedButton.icon(
              key: const Key('enregistrer-reglement'),
              onPressed: () => _ouvrirReglement(d),
              icon: const Icon(Icons.payments, size: 18),
              label: const Text(
                '+ Enregistrer un Règlement',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Ardoise Totale',
            valeur: _montant(d.ardoiseTotale),
            unite: 'FCFA',
            couleurLisere: AgriColors.errorRed,
            icone: Icons.account_balance_wallet,
            couleurIcone: AgriColors.errorRed,
          ),
          CarteKpi(
            libelle: 'Dettes Échues',
            valeur: '${d.echues(jour)}',
            legende: 'Échéance dépassée',
            couleurLisere: AgriColors.accentYellow,
            icone: Icons.schedule,
            couleurIcone: AgriColors.brandForest,
          ),
          CarteKpi(
            libelle: 'Fournisseurs',
            valeur: '${d.fournisseurs.length}',
            legende: 'Partenaires actifs',
            couleurLisere: AgriColors.brandEmerald,
            icone: Icons.groups,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 900,
          colonnes: const [
            ('Fournisseur', 4),
            ('Montant Dû', 3),
            ('Échéance', 3),
            ('Statut', 3),
            ('Actions', 2),
          ],
          vide: '— Aucune dette fournisseur en cours —',
          lignes: [
            for (var i = 0; i < d.dettes.length; i++)
              _ligne(i, [
                (
                  Text(
                    d.dettes[i].dette.supplierName ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                  4,
                ),
                (
                  Text(
                    _montant(d.dettes[i].montantDu),
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                  3,
                ),
                (_echeance(d.dettes[i], jour), 3),
                (
                  Text(
                    d.dettes[i].dette.status ?? '—',
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
        if (d.totalEnAttente > 0)
          _mentionPoste(
            'Règlements en attente de synchronisation : '
            '${_montant(d.totalEnAttente)} F. Ils sont déduits de l\'ardoise '
            'ci-dessus ; le serveur les impute et les comptabilise à la '
            'prochaine synchronisation.',
          ),
      ],
    );
  }

  Future<void> _ouvrirReglement(DonneesFournisseurs d) async {
    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleReglement(depot: widget.depot, donnees: d),
    );
    if (enregistre == true) await _charger();
  }

  /// Échéance, colorée par son retard.
  Widget _echeance(LigneDette d, DateTime jour) {
    final retard = d.retard(jour);

    if (retard == null) return const Text('—', style: _cellule);

    final enRetard = retard > 0;

    return Text(
      enRetard
          ? '${_date(d.dette.dueDate)} (+$retard j)'
          : _date(d.dette.dueDate),
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: enRetard ? AgriTypography.gras : AgriTypography.normal,
        color: enRetard ? AgriColors.errorDeep : AgriColors.onSurface,
      ),
    );
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  /// ⚠️ **TOUS LES FOURNISSEURS DESCENDUS SONT ACTIFS** : le serveur ne sert
  /// que ceux-là. Le poste ne peut donc pas afficher « Archivé » — et prétendre
  /// distinguer les deux serait faux.
  Widget _boutonNouveau(
    DonneesFournisseurs d, {
    String cle = 'nouveau-fournisseur',
  }) => ElevatedButton.icon(
    key: Key(cle),
    onPressed: () => _ouvrirFiche(null),
    icon: const Icon(Icons.add_circle, size: 18),
    label: const Text(
      'Nouveau Fournisseur',
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: FontWeight.bold,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: AgriColors.brandEmerald,
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
    ),
  );

  Future<void> _ouvrirFiche(Supplier? existant) async {
    final ecrit = await ouvrirFicheFournisseur(
      context: context,
      depot: widget.depot,
      existant: existant,
    );
    if (ecrit) await _charger();
  }

  Future<void> _archiver(Supplier fiche) async {
    final ok = await confirmerArchivageFournisseur(
      context: context,
      depot: widget.depot,
      fiche: fiche,
    );
    if (ok) await _charger();
  }

  Widget _actionsFiche(Supplier f) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: Key('modifier-fiche-${f.id}'),
        tooltip: 'Modifier',
        onPressed: () => _ouvrirFiche(f),
        icon: const Icon(Icons.edit, size: 16),
        color: AgriColors.outline,
      ),
      IconButton(
        key: Key('archiver-fiche-${f.id}'),
        tooltip: 'Archiver',
        onPressed: () => _archiver(f),
        icon: const Icon(Icons.archive, size: 16),
        color: AgriColors.outline,
      ),
    ],
  );

  /// « Actif », ou « En attente » tant que le serveur n'a pas acquitté la fiche.
  Widget _statutFiche(LigneFournisseur l) {
    if (!l.enAttente) return _pastilleActif();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: Key('fiche-en-attente-${l.fournisseur.id}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'En attente',
          style: TextStyle(
            fontSize: 10,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
      ),
    );
  }

  Widget _pastilleActif() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AgriColors.brandEmerald.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Actif',
        style: TextStyle(
          fontSize: 10,
          fontWeight: AgriTypography.gras,
          color: AgriColors.brandEmerald,
        ),
      ),
    ),
  );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GridView.count(
    crossAxisCount: large ? cartes.length : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: cartes,
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

  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(Icons.visibility, size: 16, color: AgriColors.outline),
    ),
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
        const Icon(Icons.info_outline, size: 18, color: AgriColors.brandForest),
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

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Modale « Enregistrer un Règlement » (`dettes-fournisseurs.html`).
///
/// ⚠️ « Compte de Trésorerie » ne figure pas dans la maquette : Laravel l'ajoute,
/// parce qu'un règlement fait sortir de l'argent d'un compte précis. Même ajout ici.
///
/// ⚠️ La saisie est refusée AVANT d'être écrite (montant, plafond du dû) : le
/// message reste dans la modale, rien n'est effacé.
class _ModaleReglement extends StatefulWidget {
  const _ModaleReglement({required this.depot, required this.donnees});

  final FournisseursRepository depot;
  final DonneesFournisseurs donnees;

  @override
  State<_ModaleReglement> createState() => _ModaleReglementState();
}

class _ModaleReglementState extends State<_ModaleReglement> {
  final _montant = TextEditingController();
  String _fournisseur = '';
  String _compte = '';
  DateTime _date = DateTime.now();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final montant = double.tryParse(_montant.text.trim().replaceAll(',', '.'));

    if (_fournisseur.isEmpty || _compte.isEmpty || montant == null) {
      setState(
        () => _erreur = 'Fournisseur, montant et compte sont obligatoires.',
      );
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      await widget.depot.enregistrerReglement(
        fournisseurId: _fournisseur,
        montant: montant,
        compteId: _compte,
        date: _date,
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
    final d = widget.donnees;
    final avecDette = {for (final l in d.dettes) l.dette.supplierId};

    return ModaleAgri(
      titre: 'Enregistrer un Règlement',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Fournisseur *',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('reglement-fournisseur'),
            initialValue: _fournisseur,
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
              // ⚠️ Seuls les fournisseurs à qui l'on doit quelque chose.
              for (final f in d.fournisseurs)
                if (avecDette.contains(f.fournisseur.id))
                  DropdownMenuItem(
                    value: f.fournisseur.id,
                    child: Text(f.fournisseur.name),
                  ),
            ],
            onChanged: (v) => setState(() => _fournisseur = v ?? ''),
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Montant réglé (FCFA) *',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          TextField(
            key: const Key('reglement-montant'),
            controller: _montant,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: AgriTypography.xs),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Date de règlement *',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          OutlinedButton(
            key: const Key('reglement-date'),
            onPressed: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (choisie != null) setState(() => _date = choisie);
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_date.day.toString().padLeft(2, '0')}/'
                '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Compte de Trésorerie *',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('reglement-compte'),
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
              for (final c in d.comptes)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _compte = v ?? ''),
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                _erreur!,
                key: const Key('reglement-erreur'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.errorDeep,
                ),
              ),
            ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('reglement-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _envoi ? null : _valider,
        ),
      ],
    );
  }
}
