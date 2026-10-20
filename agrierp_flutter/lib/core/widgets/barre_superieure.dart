import 'package:flutter/material.dart';

import '../fenetre/fenetre_poste.dart';
import '../theme/agri_tokens.dart';
import 'modale_agri.dart';
import '../theme/symboles_agri.dart';

/// Aperçu d'une notification pour le menu de la cloche.
///
/// ⚠️ Défini ICI, pas dans `features/notifications` : `core/` ne dépend pas des
/// écrans. L'appelant convertit ses lignes.
///
/// 🔴→✅ Ticket U14 — la cloche du web (`notification-bell.blade.php`) affiche le TITRE (`$notif->title`), pas le
/// message : le poste montrait le message. La couleur suit l'état de lecture seul (`text-error-deep` non lue,
/// `text-on-surface` lue), comme au web — le poste la réservait aux alertes critiques.
class ApercuNotification {
  const ApercuNotification({
    required this.id,
    required this.titre,
    required this.dateTexte,
    required this.lue,
  });

  final String id;
  final String titre;
  final String dateTexte;
  final bool lue;
}

/// Barre supérieure de `prototype_html` — reprise section par section.
///
/// La maquette y place, de gauche à droite : la bascule du menu (`menu` /
/// `menu_open`), le **fil d'Ariane** (« Production Elevage & Soins > Fiches
/// Lapins »), un champ de **recherche**, un indicateur **Sync**, le sélecteur
/// de rôle, et la **cloche de notifications** avec son compteur.
///
/// ⚠️ **LE SÉLECTEUR DE RÔLE N'EST PAS REPRIS** : c'est un widget de
/// démonstration de la maquette, au même titre que les boutons de test
/// d'alertes. La règle du projet l'exclut explicitement — le rôle vient ici de
/// la session réelle.
///
/// ⚠️⚠️ **LES COMMANDES DE FENÊTRE SONT UN AJOUT ASSUMÉ.** La maquette est une
/// page web : elle n'a évidemment aucun bouton réduire ou fermer. Le poste, lui,
/// est affiché **sans cadre système** : sans ces deux boutons, l'utilisateur ne
/// pourrait plus quitter l'application. Ils sont placés à l'extrémité droite,
/// là où Windows les met, pour ne déplacer aucun élément de la maquette.
class BarreSuperieure extends StatelessWidget {
  const BarreSuperieure({
    super.key,
    required this.groupe,
    required this.ecran,
    required this.enAttente,
    required this.onBasculerMenu,
    this.refuses = 0,
    this.onSynchroniser,
    this.menuOuvert = true,
    this.nomUtilisateur,
    this.onMonProfil,
    this.onAide,
    this.onContact,
    this.onParametres,
    this.onDeconnexion,
    this.recherche,
    this.nonLues,
    this.recentes = const [],
    this.onNotifications,
    this.onMarquerLue,
    this.avantFermeture,
    this.selecteurExercice,
  });

  /// Ticket EX7 (EF8) — sélecteur d'exercice global (`SelecteurExercice`, posé par le socle), à gauche du bouton
  /// « Synchroniser » comme au web. `null` : aucun sélecteur (tests de la barre seule).
  final Widget? selecteurExercice;

  /// `wire:poll.30s` de la cloche du web : la barre se relit toutes les 30 secondes (non lues, quatre dernières, et
  /// « il y a … » recalculé) — voir `RafraichissementPeriodique`, posé par le socle autour de la barre.
  static const rafraichissementCloche = Duration(seconds: 30);

  /// Nombre de notifications non lues. `null` : le poste ne sait pas (aucune
  /// source branchée) — la cloche se contente alors d'expliquer où elles vivent.
  final int? nonLues;

  /// Les plus récentes, la plus récente d'abord — quatre au plus sont montrées.
  final List<ApercuNotification> recentes;

  /// Ouvre le Centre de Notifications. `null` : pas de source branchée.
  final VoidCallback? onNotifications;

  /// Ticket U14 — le bouton `check_circle` « Marquer comme lue » d'une notification non lue (`markAsRead($id)` du
  /// web). `null` : pas de bouton.
  final Future<void> Function(String id)? onMarquerLue;

  /// Nom affiché à côté de l'icône de compte. `null` : aucune session.
  final String? nomUtilisateur;

  /// Ouvre « Mon Profil ». `null` : le rôle n'y a pas accès, l'entrée n'est
  /// pas proposée (premier niveau du RBAC ; l'écran se garde lui-même).
  final VoidCallback? onMonProfil;

  /// Ouvre « Aide & À Propos ». `null` : entrée non proposée.
  final VoidCallback? onAide;

  /// Ouvre « Contactez l'Éditeur ». `null` : entrée non proposée.
  final VoidCallback? onContact;

  /// Ticket H1 — « Paramètres » du menu du compte (`/parametres-hub` au web). `null` : entrée non proposée.
  final VoidCallback? onParametres;

  /// Ticket H1 — « Déconnexion », sous un séparateur, en `text-error-deep` comme au web. `null` : non proposée.
  final VoidCallback? onDeconnexion;

  /// Ticket H1b — champ de recherche globale (`RechercheGlobaleChamp`, défini dans `features/` : `core/` ne dépend
  /// pas des écrans). `null` : champ inerte d'origine.
  final Widget? recherche;

  /// Groupe de la barre latérale — première partie du fil d'Ariane.
  final String groupe;

  /// Écran courant — seconde partie du fil d'Ariane.
  final String ecran;

  /// Nombre d'enregistrements non synchronisés (à envoyer + refusés), badge du bouton « Synchroniser ».
  final int enAttente;

  /// Dont refusés par le serveur : le badge passe au rouge (ticket H2, EF3).
  final int refuses;

  /// Ouvre la modale « Synchronisation » (ticket H2). `null` : bouton inerte (aucun moteur branché).
  final VoidCallback? onSynchroniser;

  /// Ticket H13 (B2) — synchronisation de fermeture : envoie ce qui attend encore et rend le nombre
  /// d'enregistrements restés à envoyer. `null` = aucune tentative (la confirmation suit [enAttente]).
  final Future<int> Function()? avantFermeture;

  final VoidCallback onBasculerMenu;
  final bool menuOuvert;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Ticket H1 — `h-16 … px-md lg:px-lg` du web : 64 px de haut, 24 px de marge sur un poste de bureau.
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.lg),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        children: [
          // 1. Bascule du menu.
          IconButton(
            key: const Key('bascule-menu'),
            onPressed: onBasculerMenu,
            // Web : icône `menu_open` 22 px `text-outline`, TOUJOURS la même, title « Afficher/Masquer la barre
            // latérale ».
            iconSize: 22,
            color: AgriColors.outline,
            icon: const Icon(SymbolesAgri.menu_open),
            tooltip: 'Afficher/Masquer la barre latérale',
          ),
          const SizedBox(width: AgriSpacing.xs),

          // 2. Fil d'Ariane — « Groupe > Écran », comme la maquette.
          Flexible(
            child: Text(
              // ⚠️ Groupe vide = écran hors barre latérale (« Mon Profil ») :
              // la maquette n'y affiche que le nom de l'écran.
              groupe.isEmpty ? ecran : '$groupe > $ecran',
              key: const Key('fil-ariane'),
              overflow: TextOverflow.ellipsis,
              // Web : `text-brand-emerald font-bold text-xs truncate`.
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandEmerald,
              ),
            ),
          ),

          const Spacer(),

          // 3. Recherche.
          //
          // ⚠️ LA RECHERCHE GLOBALE DE LA MAQUETTE PARCOURT TOUS SES ÉCRANS ;
          // le poste n'en embarque qu'une poignée. Le champ est donc présent et
          // à sa place, mais annonce sa portée au lieu de promettre une
          // recherche qu'il ne peut pas rendre.
          if (recherche != null) recherche! else SizedBox(
            width: 220,
            height: 34,
            child: TextField(
              key: const Key('recherche-globale'),
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: InputDecoration(
                hintText: 'Recherche (application web)',
                hintStyle: const TextStyle(fontSize: 11.5),
                prefixIcon: const Icon(SymbolesAgri.search, size: 16),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                enabled: false,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(width: AgriSpacing.md),

          // 3 bis. Ticket EX7 (EF8) — « Exercice 2027 ▾ », à gauche du bouton « Synchroniser » (`app.blade.php`).
          if (selecteurExercice != null) ...[
            selecteurExercice!,
            const SizedBox(width: AgriSpacing.sm),
          ],

          // 4. Bouton « Synchroniser » (ticket H2, même place et même gabarit qu'au web, entre la recherche
          // et la cloche). Il remplace la pastille non cliquable et le bouton du pied de la barre latérale,
          // inatteignable quand celle-ci débordait.
          //
          // ⚠️ SON BADGE COMPTE CE QUI N'EST PAS ENCORE AU SERVEUR, pas un état décoratif : c'est le seul
          // chiffre qui dise à l'animalier si sa journée est partie.
          _boutonSynchroniser(),
          const SizedBox(width: AgriSpacing.sm),

          // 5. Cloche de notifications, avec son compteur et son menu des
          // quatre plus récentes (`dd-notif` de la maquette).
          //
          // ⚠️ SANS SOURCE BRANCHÉE (`onNotifications` nul), AUCUN COMPTEUR : un
          // « 0 » ferait croire à une boîte vide alors qu'elle est simplement
          // inaccessible. Avec une source, « 0 » est vrai et le badge disparaît.
          //
          // Les onglets « Toutes / Non lues » de la maquette ne sont pas repris :
          // la cloche du web (`notification-bell.blade.php`, maître) n'en a pas.
          // Ticket U14 : panneau du Blade, titre, « Marquer comme lue », relu
          // toutes les 30 s.
          _cloche(context),

          const SizedBox(width: AgriSpacing.sm),

          // 5 bis. Menu du compte (`dd-profile` de la maquette).
          //
          // Ticket H1 — menu du compte complet, dans l'ordre du web (`app.blade.php`) : Mon Profil, Aide & À
          // Propos, Contactez l'Éditeur, Paramètres, séparateur, Déconnexion.
          _compte(),
          const SizedBox(width: AgriSpacing.sm),
          const VerticalDivider(indent: 14, endIndent: 14, width: 1),
          const SizedBox(width: AgriSpacing.xs),

          // 6. Commandes de fenêtre — ajout assumé, voir le docblock.
          IconButton(
            key: const Key('fenetre-reduire'),
            iconSize: 18,
            color: AgriColors.outline,
            icon: const Icon(SymbolesAgri.remove),
            tooltip: 'Réduire',
            onPressed: FenetrePoste.reduire,
          ),
          IconButton(
            key: const Key('fenetre-fermer'),
            iconSize: 18,
            color: AgriColors.errorDeep,
            icon: const Icon(SymbolesAgri.close),
            tooltip: 'Fermer AgriERP',
            onPressed: () => _confirmerFermeture(context),
          ),
        ],
      ),
    );
  }

  Widget _cloche(BuildContext context) {
    final cle = const Key('cloche-notifications');

    if (onNotifications == null) {
      return IconButton(
        key: cle,
        iconSize: 20,
        color: AgriColors.outline,
        icon: const Icon(SymbolesAgri.notifications_none),
        tooltip: "Notifications — sur l'application web",
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Les notifications vivent sur l'application web : la "
                'synchronisation ne les descend pas au poste.',
              ),
            ),
          );
        },
      );
    }

    return _Cloche(
      cle: cle,
      nonLues: nonLues ?? 0,
      recentes: recentes,
      onNotifications: onNotifications!,
      onMarquerLue: onMarquerLue,
    );
  }

  Widget _compte() {
    final nom = nomUtilisateur;

    final contenu = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          SymbolesAgri.account_circle,
          size: 22,
          color: AgriColors.brandForest,
        ),
        if (nom != null && nom.isNotEmpty) ...[
          const SizedBox(width: AgriSpacing.xs),
          Text(
            nom,
            key: const Key('compte-nom'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.w600,
              color: AgriColors.brandForest,
            ),
          ),
        ],
        if (_entreesCompte.isNotEmpty)
          const Icon(
            SymbolesAgri.expand_more,
            size: 16,
            color: AgriColors.brandForest,
          ),
      ],
    );

    final entrees = _entreesCompte;
    if (entrees.isEmpty) return contenu;

    return PopupMenuButton<String>(
      key: const Key('menu-compte'),
      tooltip: 'Compte',
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        side: const BorderSide(color: AgriColors.outlineVariant),
      ),
      padding: EdgeInsets.zero,
      onSelected: (valeur) => entrees.firstWhere((e) => e.$1 == valeur).$5(),
      itemBuilder: (_) => [
        for (final (valeur, cle, icone, libelle, _) in entrees) ...[
          // Web : `<div class="border-t border-outline-variant">` avant « Déconnexion ».
          if (valeur == 'deconnexion') const PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            key: Key(cle),
            value: valeur,
            child: Row(
              children: [
                Icon(icone, size: 16, color: valeur == 'deconnexion' ? AgriColors.errorDeep : null),
                const SizedBox(width: AgriSpacing.xs),
                // ⚠️ `Flexible` : le menu est borné à 280 px, un libellé plus long
                // que la police de test ne doit pas déborder.
                Flexible(
                  child: Text(
                    libelle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: valeur == 'deconnexion' ? AgriColors.errorDeep : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: contenu,
    );
  }

  /// Entrées du menu du compte, dans l'ordre de la maquette (`dd-profile`) :
  /// Mon Profil, Aide & À Propos — puis Contactez l'Éditeur, Paramètres et
  /// Déconnexion quand leurs écrans existeront. Une entrée sans rappel n'est
  /// pas proposée : un lien mort serait pire qu'un lien absent.
  List<(String, String, IconData, String, VoidCallback)> get _entreesCompte => [
    if (onMonProfil != null)
      (
        'profil',
        'menu-compte-profil',
        SymbolesAgri.person,
        'Mon Profil',
        onMonProfil!,
      ),
    if (onAide != null)
      ('aide', 'menu-compte-aide', SymbolesAgri.help, 'Aide & À Propos', onAide!),
    if (onContact != null)
      (
        'contact',
        'menu-compte-contact',
        SymbolesAgri.support_agent,
        "Contactez l'Éditeur",
        onContact!,
      ),
    if (onParametres != null)
      ('parametres', 'menu-compte-parametres', SymbolesAgri.settings, 'Paramètres', onParametres!),
    if (onDeconnexion != null)
      ('deconnexion', 'menu-compte-deconnexion', SymbolesAgri.logout, 'Déconnexion', onDeconnexion!),
  ];

  /// Badge sur le modèle de celui de la cloche (`notification-bell.blade.php`) : 16 px, 9 px gras, plafonné à
  /// « 9+ ». Rouge s'il y a au moins un refus à corriger, émeraude sinon ; absent à 0 (PRD, EF3).
  Widget _boutonSynchroniser() {
    final badge = enAttente > 9 ? '9+' : '$enAttente';

    return InkWell(
      key: const Key('bouton-synchroniser'),
      onTap: onSynchroniser,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Tooltip(
        message: 'Synchroniser',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(SymbolesAgri.sync, size: 22, color: AgriColors.outline),
            ),
            if (enAttente > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  key: const Key('bouton-synchroniser-badge'),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: refuses > 0 ? AgriColors.errorRed : AgriColors.brandEmerald,
                    borderRadius: BorderRadius.circular(AgriRadius.full),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Ticket H13 — pendant l'envoi de fermeture (borné à 15 s), une modale dit ce qui se passe : sans elle,
  /// le clic sur ✕ semblerait sans effet.
  Future<int> _synchroniserAvantFermeture(BuildContext context) async {
    final navigateur = Navigator.of(context);
    var ouverte = true;
    afficherModale<void>(
      context: context,
      fermableParVoile: false,
      constructeur: (_) => const ModaleAgri(
        key: Key('modale-envoi-fermeture'),
        titre: 'Synchronisation avant fermeture',
        largeur: LargeurModale.sm,
        contenu: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: Text(
                'Envoi des enregistrements en attente…',
                style: TextStyle(fontSize: AgriTypography.xs),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() => ouverte = false);
    try {
      return await avantFermeture!();
    } finally {
      if (ouverte) navigateur.pop();
    }
  }

  /// ⚠️ FERMER SE CONFIRME QUAND UNE SAISIE ATTEND ENCORE. Quitter avec des
  /// journées non transmises ne les perd pas — elles restent en base locale —
  /// mais l'animalier doit le savoir, sans quoi il croira son travail parti.
  Future<void> _confirmerFermeture(BuildContext context) async {
    var restants = enAttente;
    if (restants > 0 && avantFermeture != null) {
      restants = await _synchroniserAvantFermeture(context);
      if (!context.mounted) return;
    }

    if (restants == 0) {
      await FenetrePoste.fermer();
      return;
    }

    // ⚠️ CONFIRMATION HORS MAQUETTE, AU GABARIT DE LA MAQUETTE. La fenêtre
    // du poste est sans cadre système (ticket F0.23) : ce dialogue n'a pas
    // d'équivalent dans le prototype, qui est une page web. Il emprunte donc
    // le gabarit `max-w-sm` des confirmations plutôt que d'introduire une
    // troisième apparence de boîte de dialogue.
    final confirme = await afficherModale<bool>(
      context: context,
      constructeur: (contexte) => ModaleAgri(
        key: const Key('modale-fermeture'),
        titre: 'Quitter AgriERP ?',
        largeur: LargeurModale.sm,
        contenu: Text(
          '$restants enregistrement(s) attendent encore d\'être transmis. '
          'Ils restent enregistrés sur ce poste et partiront à la prochaine '
          'synchronisation.',
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            libelle: 'Quitter',
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );

    if (confirme == true) await FenetrePoste.fermer();
  }
}

/// 🔴→✅ Ticket U14 — LA CLOCHE DU WEB (`livewire/shared/notification-bell.blade.php`), élément par élément :
///  - le bouton `notifications` (24 px, `text-outline`) et son badge rouge de 16 px plafonné à « 9+ » ;
///  - le panneau `w-80` aligné à droite : « Notifications » (`font-bold text-xs text-brand-forest`), les QUATRE plus
///    récentes (`limit(4)`), chacune avec son TITRE (`text-xs font-semibold`, `text-error-deep` si non lue) et
///    « il y a … » (`text-[10px] text-outline`), plus le bouton `check_circle` « Marquer comme lue » d'une non lue ;
///    sans notification, « Aucune notification pour le moment. » (`text-[11px]`, centré) ; en pied « Voir toutes les
///    notifications ».
///  - cliquer une notification ne mène nulle part (le web n'a pas de lien sur la ligne) : seul le pied ouvre le Centre.
///
/// Le panneau est un `MenuAnchor` (superposition reconstruite avec la barre) : quand le socle relit la barre toutes
/// les 30 s (`wire:poll.30s`), un panneau OUVERT se met à jour, comme au web — un menu surgissant figé à l'ouverture
/// garderait « il y a 1 minute » indéfiniment.
class _Cloche extends StatefulWidget {
  const _Cloche({
    required this.cle,
    required this.nonLues,
    required this.recentes,
    required this.onNotifications,
    required this.onMarquerLue,
  });

  final Key cle;
  final int nonLues;
  final List<ApercuNotification> recentes;
  final VoidCallback onNotifications;
  final Future<void> Function(String id)? onMarquerLue;

  @override
  State<_Cloche> createState() => _ClocheState();
}

class _ClocheState extends State<_Cloche> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final n = widget.nonLues;
    final quatre = widget.recentes.take(4).toList();

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            side: const BorderSide(color: AgriColors.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          key: const Key('cloche-panneau'),
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                child: const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
              // `max-h-64 overflow-y-auto`.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 256),
                // `primary: false` : le panneau de `MenuAnchor` défile déjà sur le contrôleur principal.
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (quatre.isEmpty)
                        const Padding(
                          key: Key('cloche-vide'),
                          padding: EdgeInsets.symmetric(vertical: AgriSpacing.lg),
                          child: Text(
                            'Aucune notification pour le moment.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: AgriColors.outline,
                            ),
                          ),
                        ),
                      for (var i = 0; i < quatre.length; i++)
                        _ligne(i, quatre[i]),
                    ],
                  ),
                ),
              ),
              InkWell(
                key: const Key('cloche-voir-toutes'),
                onTap: () {
                  _menu.close();
                  widget.onNotifications();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AgriColors.outlineVariant),
                    ),
                  ),
                  child: const Text(
                    'Voir toutes les notifications',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: 'Notifications',
        child: InkWell(
          key: widget.cle,
          borderRadius: BorderRadius.circular(AgriRadius.full),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  SymbolesAgri.notifications,
                  size: 24,
                  color: AgriColors.outline,
                ),
              ),
              if (n > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    key: const Key('cloche-compteur'),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AgriColors.errorRed,
                      borderRadius: BorderRadius.circular(AgriRadius.full),
                    ),
                    child: Text(
                      // Plafond du web : « 9+ » (`notification-bell.blade.php`), pas « 99+ ».
                      n > 9 ? '9+' : '$n',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// `notif-item px-md py-sm border-b … flex items-start justify-between gap-xs`.
  Widget _ligne(int i, ApercuNotification a) {
    final marquer = widget.onMarquerLue;
    return Container(
      key: Key('cloche-notif-$i'),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.titre,
                  key: Key('cloche-titre-$i'),
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.w600,
                    color: a.lue ? AgriColors.onSurface : AgriColors.errorDeep,
                  ),
                ),
                Text(
                  a.dateTexte,
                  key: Key('cloche-date-$i'),
                  style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ],
            ),
          ),
          if (!a.lue && marquer != null) ...[
            const SizedBox(width: AgriSpacing.xs),
            Tooltip(
              message: 'Marquer comme lue',
              child: InkWell(
                key: Key('cloche-lue-$i'),
                onTap: () => marquer(a.id),
                child: const Icon(
                  SymbolesAgri.check_circle,
                  size: 16,
                  color: AgriColors.brandEmerald,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
