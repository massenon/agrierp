import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'notifications_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/notifications.html` → Centre de Notifications.
///
/// ⚠️⚠️ **LES NOTIFICATIONS VIENNENT DU SERVEUR, ET LE POSTE NE LES VOIT
/// QU'APRÈS UN TIRAGE.** Aucune n'est produite au poste : alertes de stock,
/// mortalité, prophylaxie, créances sont levées par le serveur. L'écran affiche
/// donc l'état du dernier tirage et le dit en pied de tableau, plutôt que de
/// laisser croire à un direct.
///
/// ⚠️ **« LUE » ET « SUPPRIMER » EXIGENT LE RÉSEAU** et ne sont pas mis en file
/// (voir [ServeurNotifications]) : hors ligne, l'action est refusée par une
/// phrase, jamais appliquée à moitié.
///
/// ⚠️ **ÉCARTS ASSUMÉS** : le panneau repliable « Résumé des alertes » des petits
/// écrans n'est pas repris (le poste est une fenêtre de bureau, jamais sous
/// 768 px) ; la flèche « Résoudre » n'existe que si le poste possède la page
/// visée.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.depot,
    this.onOuvrir,
    this.onModifie,
  });

  final NotificationsRepository depot;

  /// Ouvre l'écran visé par « Résoudre ».
  final void Function(EcranPoste)? onOuvrir;

  /// Appelé après un marquage ou une suppression, pour rafraîchir la cloche.
  final VoidCallback? onModifie;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Les quatre catégories du filtre de la maquette, dans son ordre.
  static const categories = ['Élevage', 'Stocks', 'Finance', 'RH'];
  static const statuts = ['Non lue', 'Lue'];

  final _recherche = TextEditingController();
  DonneesNotifications? _donnees;
  String _categorie = '';
  String _statut = '';

  /// Dernier retour d'action : (réussi, message).
  (bool, String)? _retour;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  Future<void> _agir(
    Future<void> Function() action,
    String messageReussi,
  ) async {
    try {
      await action();
      if (!mounted) return;
      _retour = (true, messageReussi);
      widget.onModifie?.call();
    } on EchecNotification catch (e) {
      if (!mounted) return;
      _retour = (false, e.message);
    }
    await _charger();
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
                final lignes = NotificationsRepository.filtrer(
                  d.lignes,
                  recherche: _recherche.text,
                  categorie: _categorie,
                  statut: _statut,
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entete(large),
                      const SizedBox(height: AgriSpacing.lg),
                      _cartes(d, large),
                      const SizedBox(height: AgriSpacing.lg),
                      _filtres(),
                      if (_retour != null) ...[
                        const SizedBox(height: AgriSpacing.md),
                        _bandeau(_retour!.$1, _retour!.$2),
                      ],
                      const SizedBox(height: AgriSpacing.md),
                      _tableau(lignes),
                      const SizedBox(height: AgriSpacing.sm),
                      const Text(
                        'Ce poste affiche les notifications du dernier '
                        'tirage (200 au plus).',
                        key: Key('notif-portee'),
                        style: TextStyle(
                          fontSize: 10,
                          color: AgriColors.outline,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
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
              SymbolesAgri.notifications,
              size: 26,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Centre de Notifications',
              style: TextStyle(
                fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Toutes les alertes et notifications système d'AgriERP.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  // ── Résumé des alertes : trois cartes, dans l'ordre de la maquette ───────

  Widget _cartes(DonneesNotifications d, bool large) => GridView.count(
    crossAxisCount: large ? 3 : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 3.6 : 1.8,
    children: [
      CarteKpi(
        libelle: 'Non Lues',
        valeur: '${d.nonLues}',
        couleurLisere: AgriColors.errorRed,
        icone: SymbolesAgri.mark_email_unread,
        couleurIcone: AgriColors.errorRed,
      ),
      CarteKpi(
        libelle: 'Critiques',
        valeur: '${d.critiques}',
        couleurLisere: AgriColors.accentYellow,
        icone: SymbolesAgri.warning,
        couleurIcone: AgriColors.brandForest,
      ),
      CarteKpi(
        libelle: 'Total (30 jours)',
        valeur: '${d.total30Jours}',
        couleurLisere: AgriColors.brandEmerald,
        icone: SymbolesAgri.notifications,
      ),
    ],
  );

  // ── Barre de filtres ──────────────────────────────────────────────────────

  Widget _filtres() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    // `flex-1 min-w-[180px]` pour la recherche, les deux listes à leur taille.
    child: Row(
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180),
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('notif-recherche'),
                controller: _recherche,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: InputDecoration(
                  hintText: 'Rechercher un message...',
                  hintStyle: const TextStyle(fontSize: AgriTypography.xs),
                  prefixIcon: const Icon(SymbolesAgri.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                    borderSide: const BorderSide(
                      color: AgriColors.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AgriSpacing.sm),
        _liste(
          context,
          const Key('notif-categorie'),
          'Toutes catégories',
          categories,
          _categorie,
          (v) => setState(() => _categorie = v),
        ),
        const SizedBox(width: AgriSpacing.sm),
        _liste(
          context,
          const Key('notif-statut'),
          'Toutes',
          statuts,
          _statut,
          (v) => setState(() => _statut = v),
        ),
      ],
    ),
  );

  Widget _liste(
    BuildContext context,
    Key cle,
    String toutes,
    List<String> options,
    String valeur,
    void Function(String) surChoix,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
    height: 36,
    decoration: BoxDecoration(
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: cle,
        value: valeur,
        isDense: true,
        // ⚠️ Le style du MENU DÉROULANT ne vient pas du thème : sans cette
        // base, il retombe sur la police par défaut du moteur (des carrés en
        // test, une police étrangère à l'application sur le poste).
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: AgriTypography.xs,
          color: AgriColors.onSurface,
        ),
        items: [
          DropdownMenuItem(value: '', child: Text(toutes)),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => surChoix(v ?? ''),
      ),
    ),
  );

  Widget _bandeau(bool reussi, String message) {
    final couleur = reussi ? AgriColors.brandEmerald : AgriColors.errorRed;

    return Container(
      key: Key(reussi ? 'notif-reussi' : 'notif-echec'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        border: Border.all(color: couleur.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          Icon(
            reussi ? SymbolesAgri.check_circle : SymbolesAgri.error,
            size: 18,
            color: couleur,
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tableau ───────────────────────────────────────────────────────────────

  static const _colonnes = <(String, int)>[
    ('Date / Heure', 3),
    ('Catégorie', 2),
    ('Message', 6),
    ('Gravité', 2),
    ('Statut', 2),
    ('Actions', 2),
  ];

  Widget _tableau(List<LigneNotification> lignes) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 960,
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
                  for (final (libelle, flex) in _colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        textAlign: libelle == 'Actions'
                            ? TextAlign.end
                            : TextAlign.start,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  'Aucune notification à afficher.',
                  key: Key('notif-vide'),
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (var i = 0; i < lignes.length; i++) _ligne(i, lignes[i]),
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int i, LigneNotification n) {
    final ecran = n.ecranDuLien;

    return Container(
      key: Key('ligne-notif-$i'),
      color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              n.dateTexte,
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
          Expanded(flex: 2, child: _pastille(n.categorie, _styleCategorie)),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.only(right: AgriSpacing.sm),
              child: Text(
                n.message,
                style: const TextStyle(fontSize: AgriTypography.xs),
              ),
            ),
          ),
          Expanded(flex: 2, child: _pastille(n.graviteLibelle, _styleGravite)),
          Expanded(
            flex: 2,
            child: Text(
              n.lue ? 'Lue' : 'Non lue',
              key: Key('statut-notif-$i'),
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: n.lue ? AgriColors.brandEmerald : AgriColors.errorDeep,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _action(
                  Key('lue-$i'),
                  SymbolesAgri.check_circle,
                  'Marquer comme lue',
                  AgriColors.brandEmerald,
                  () => _agir(
                    () => widget.depot.marquerLue(n.id),
                    'Notification marquée comme lue.',
                  ),
                ),
                if (ecran != null && widget.onOuvrir != null)
                  _action(
                    Key('resoudre-$i'),
                    SymbolesAgri.arrow_forward,
                    'Résoudre',
                    AgriColors.infoBlue,
                    () => widget.onOuvrir!(ecran),
                  ),
                _action(
                  Key('suppr-$i'),
                  SymbolesAgri.delete,
                  'Supprimer',
                  AgriColors.outline,
                  () => _agir(
                    () => widget.depot.supprimer(n.id),
                    'Notification supprimée.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    Key cle,
    IconData icone,
    String infobulle,
    Color couleur,
    VoidCallback surAppui,
  ) => IconButton(
    key: cle,
    tooltip: infobulle,
    onPressed: surAppui,
    iconSize: 18,
    // ⚠️ `constraints` est IGNORÉ par Material 3, qui impose 48 px : trois
    // boutons y tiennent à 144 px dans une colonne de 109. Le style, lui, est
    // respecté — et la zone de clic reste de 28 px, comme `p-1` + icône de 18.
    style: IconButton.styleFrom(
      minimumSize: const Size(28, 28),
      padding: const EdgeInsets.all(4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    color: couleur,
    icon: Icon(icone),
  );

  Widget _pastille(String texte, (Color, Color, Color) Function(String) style) {
    final (fond, bordure, encre) = style(texte);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: fond,
          border: Border.all(color: bordure),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          texte,
          style: TextStyle(
            fontSize: 11,
            fontWeight: AgriTypography.gras,
            color: encre,
          ),
        ),
      ),
    );
  }

  /// Élevage vert, Stocks jaune, Finance et RH bleus — les couleurs de la
  /// maquette. Une catégorie qu'elle ne connaît pas (« Système ») prend le gris
  /// neutre de « Info ».
  static (Color, Color, Color) _styleCategorie(String categorie) =>
      switch (categorie) {
        'Élevage' => (
          AgriColors.brandEmerald.withValues(alpha: 0.10),
          AgriColors.brandEmerald.withValues(alpha: 0.30),
          AgriColors.brandEmerald,
        ),
        'Stocks' => (
          AgriColors.accentYellow.withValues(alpha: 0.20),
          AgriColors.accentYellow,
          AgriColors.brandForest,
        ),
        'Finance' || 'RH' => (
          AgriColors.infoBlue.withValues(alpha: 0.10),
          AgriColors.infoBlue.withValues(alpha: 0.30),
          AgriColors.infoBlue,
        ),
        _ => (
          AgriColors.surfaceZebra,
          AgriColors.outlineVariant,
          AgriColors.outline,
        ),
      };

  static (Color, Color, Color) _styleGravite(String libelle) =>
      switch (libelle) {
        'Critique' => (
          AgriColors.errorBg,
          AgriColors.errorDeep.withValues(alpha: 0.30),
          AgriColors.errorDeep,
        ),
        'Moyen' => (
          AgriColors.accentYellow.withValues(alpha: 0.20),
          AgriColors.accentYellow,
          AgriColors.brandForest,
        ),
        _ => (
          AgriColors.surfaceZebra,
          AgriColors.outlineVariant,
          AgriColors.outline,
        ),
      };
}
