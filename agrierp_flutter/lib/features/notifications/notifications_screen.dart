import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
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

  /// Ticket U14 — `wire:model.live.debounce.300ms="search"` : la recherche appliquée 300 ms après la frappe.
  String _rechercheAppliquee = '';
  Timer? _attenteRecherche;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  /// 🔴→✅ Ticket U14 — les TOASTS du web (`markAsRead` : succès « Notification marquée comme lue. » ; `delete` :
  /// avertissement « Notification supprimée. ») ; un échec (réseau, session) en toast d'erreur. Le poste affichait un
  /// bandeau sous les filtres.
  Future<void> _agir(
    Future<void> Function() action,
    String messageReussi,
    TypeToast type,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ToastAgri.afficher(context, messageReussi, type: type);
      widget.onModifie?.call();
    } on EchecNotification catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, e.message, type: TypeToast.erreur);
    }
    await _charger();
  }

  /// `wire:confirm="Supprimer cette notification ?"` du web : la question, puis « Annuler » ou la suppression.
  Future<void> _supprimer(LigneNotification n) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.delete,
        couleurIcone: AgriColors.errorRed,
        titre: 'Supprimer cette notification ?',
        message: n.message,
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('suppr-confirmer'),
            libelle: 'Supprimer',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _agir(() => widget.depot.supprimer(n.id), 'Notification supprimée.', TypeToast.avertissement);
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
                  recherche: _rechercheAppliquee,
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

  Widget _cartes(DonneesNotifications d, bool large) => GrilleKpi(colonnes: large ? 3 : 2, children: [
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
                onChanged: (texte) {
                  _attenteRecherche?.cancel();
                  _attenteRecherche = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _rechercheAppliquee = texte);
                  });
                },
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
    // Ticket U14 — `@if($this->notifications->isEmpty())` : la phrase SEULE, sans en-tête de tableau.
    child: lignes.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: AgriSpacing.xl),
            child: Text(
              'Aucune notification pour le moment.',
              key: Key('notif-vide'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          )
        : SingleChildScrollView(
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
                // Ticket U14 — `@if(!$notif->is_read)` : pas de « Marquer comme lue » sur une notification déjà lue.
                if (!n.lue)
                  _action(
                    Key('lue-$i'),
                    SymbolesAgri.check_circle,
                    'Marquer comme lue',
                    AgriColors.brandEmerald,
                    () => _agir(
                      () => widget.depot.marquerLue(n.id),
                      'Notification marquée comme lue.',
                      TypeToast.succes,
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
                  () => _supprimer(n),
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
