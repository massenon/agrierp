import 'package:flutter/material.dart';

import '../fenetre/fenetre_poste.dart';
import '../theme/agri_tokens.dart';
import 'modale_agri.dart';

/// Aperçu d'une notification pour le menu de la cloche.
///
/// ⚠️ Défini ICI, pas dans `features/notifications` : `core/` ne dépend pas des
/// écrans. L'appelant convertit ses lignes.
class ApercuNotification {
  const ApercuNotification({
    required this.message,
    required this.dateTexte,
    required this.lue,
    required this.critique,
  });

  final String message;
  final String dateTexte;
  final bool lue;
  final bool critique;
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
    this.menuOuvert = true,
    this.nomUtilisateur,
    this.onMonProfil,
    this.onAide,
    this.onContact,
    this.nonLues,
    this.recentes = const [],
    this.onNotifications,
  });

  /// Nombre de notifications non lues. `null` : le poste ne sait pas (aucune
  /// source branchée) — la cloche se contente alors d'expliquer où elles vivent.
  final int? nonLues;

  /// Les plus récentes, la plus récente d'abord — quatre au plus sont montrées.
  final List<ApercuNotification> recentes;

  /// Ouvre le Centre de Notifications. `null` : pas de source branchée.
  final VoidCallback? onNotifications;

  /// Nom affiché à côté de l'icône de compte. `null` : aucune session.
  final String? nomUtilisateur;

  /// Ouvre « Mon Profil ». `null` : le rôle n'y a pas accès, l'entrée n'est
  /// pas proposée (premier niveau du RBAC ; l'écran se garde lui-même).
  final VoidCallback? onMonProfil;

  /// Ouvre « Aide & À Propos ». `null` : entrée non proposée.
  final VoidCallback? onAide;

  /// Ouvre « Contactez l'Éditeur ». `null` : entrée non proposée.
  final VoidCallback? onContact;

  /// Groupe de la barre latérale — première partie du fil d'Ariane.
  final String groupe;

  /// Écran courant — seconde partie du fil d'Ariane.
  final String ecran;

  /// Nombre d'enregistrements en attente d'envoi, pour l'indicateur Sync.
  final int enAttente;

  final VoidCallback onBasculerMenu;
  final bool menuOuvert;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
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
            iconSize: 20,
            color: AgriColors.brandForest,
            icon: Icon(menuOuvert ? Icons.menu_open : Icons.menu),
            tooltip: menuOuvert ? 'Replier le menu' : 'Déplier le menu',
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
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.w600,
                color: AgriColors.brandForest,
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
          SizedBox(
            width: 220,
            height: 34,
            child: TextField(
              key: const Key('recherche-globale'),
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: InputDecoration(
                hintText: 'Recherche (application web)',
                hintStyle: const TextStyle(fontSize: 11.5),
                prefixIcon: const Icon(Icons.search, size: 16),
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

          // 4. Indicateur Sync.
          //
          // ⚠️ IL COMPTE CE QUI ATTEND D'ÊTRE ENVOYÉ, pas un état décoratif :
          // c'est le seul chiffre qui dise à l'animalier si sa journée est
          // partie.
          _pastilleSync(),
          const SizedBox(width: AgriSpacing.md),

          // 5. Cloche de notifications, avec son compteur et son menu des
          // quatre plus récentes (`dd-notif` de la maquette).
          //
          // ⚠️ SANS SOURCE BRANCHÉE (`onNotifications` nul), AUCUN COMPTEUR : un
          // « 0 » ferait croire à une boîte vide alors qu'elle est simplement
          // inaccessible. Avec une source, « 0 » est vrai et le badge disparaît.
          //
          // ⚠️ ÉCART ASSUMÉ : les onglets « Toutes / Non lues » du menu de la
          // maquette ne sont pas repris — le Centre de Notifications porte déjà
          // ces filtres, à un clic.
          _cloche(context),

          const SizedBox(width: AgriSpacing.sm),

          // 5 bis. Menu du compte (`dd-profile` de la maquette).
          //
          // ⚠️ SEULE « MON PROFIL » Y FIGURE POUR L'INSTANT : « Aide & À Propos »
          // et « Contactez l'Éditeur » arrivent avec leurs écrans, « Paramètres »
          // et « Déconnexion » avec leur propre ticket (aucune déconnexion n'est
          // câblée au poste — voir RAPPORT_CHROME.md). Une entrée vers un écran
          // qui n'existe pas serait un lien mort.
          _compte(),
          const SizedBox(width: AgriSpacing.sm),
          const VerticalDivider(indent: 14, endIndent: 14, width: 1),
          const SizedBox(width: AgriSpacing.xs),

          // 6. Commandes de fenêtre — ajout assumé, voir le docblock.
          IconButton(
            key: const Key('fenetre-reduire'),
            iconSize: 18,
            color: AgriColors.outline,
            icon: const Icon(Icons.remove),
            tooltip: 'Réduire',
            onPressed: FenetrePoste.reduire,
          ),
          IconButton(
            key: const Key('fenetre-fermer'),
            iconSize: 18,
            color: AgriColors.errorDeep,
            icon: const Icon(Icons.close),
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
        icon: const Icon(Icons.notifications_none),
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

    final n = nonLues ?? 0;

    return PopupMenuButton<String>(
      key: cle,
      tooltip: 'Notifications',
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        side: const BorderSide(color: AgriColors.outlineVariant),
      ),
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      onSelected: (_) => onNotifications!(),
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            'Notifications',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        if (recentes.isEmpty)
          const PopupMenuItem<String>(
            key: Key('cloche-vide'),
            enabled: false,
            child: Text(
              'Aucune notification pour le moment.',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ),
        for (var i = 0; i < recentes.length && i < 4; i++)
          PopupMenuItem<String>(
            key: Key('cloche-notif-$i'),
            value: 'n$i',
            child: SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recentes[i].message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: recentes[i].lue
                          ? FontWeight.normal
                          : FontWeight.w600,
                      color: recentes[i].critique && !recentes[i].lue
                          ? AgriColors.errorDeep
                          : AgriColors.onSurface,
                    ),
                  ),
                  Text(
                    recentes[i].dateTexte,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const PopupMenuItem<String>(
          key: Key('cloche-voir-toutes'),
          value: 'toutes',
          child: Center(
            child: Text(
              'Voir toutes les notifications',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandEmerald,
              ),
            ),
          ),
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.notifications_none,
              size: 22,
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
                  n > 99 ? '99+' : '$n',
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
    );
  }

  Widget _compte() {
    final nom = nomUtilisateur;

    final contenu = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.account_circle,
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
            Icons.expand_more,
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
        for (final (valeur, cle, icone, libelle, _) in entrees)
          PopupMenuItem<String>(
            key: Key(cle),
            value: valeur,
            child: Row(
              children: [
                Icon(icone, size: 16),
                const SizedBox(width: AgriSpacing.xs),
                // ⚠️ `Flexible` : le menu est borné à 280 px, un libellé plus long
                // que la police de test ne doit pas déborder.
                Flexible(
                  child: Text(
                    libelle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AgriTypography.xs),
                  ),
                ),
              ],
            ),
          ),
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
        Icons.person,
        'Mon Profil',
        onMonProfil!,
      ),
    if (onAide != null)
      ('aide', 'menu-compte-aide', Icons.help, 'Aide & À Propos', onAide!),
    if (onContact != null)
      (
        'contact',
        'menu-compte-contact',
        Icons.support_agent,
        "Contactez l'Éditeur",
        onContact!,
      ),
  ];

  Widget _pastilleSync() {
    final aEnvoyer = enAttente > 0;

    return Container(
      key: const Key('pastille-sync'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: aEnvoyer
            ? AgriColors.accentYellow.withValues(alpha: 0.22)
            : AgriColors.brandEmerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            aEnvoyer ? Icons.sync_problem : Icons.sync,
            size: 14,
            color: aEnvoyer ? AgriColors.brandForest : AgriColors.brandEmerald,
          ),
          const SizedBox(width: 4),
          Text(
            aEnvoyer ? 'Sync · $enAttente en attente' : 'Sync',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: aEnvoyer
                  ? AgriColors.brandForest
                  : AgriColors.brandEmerald,
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ FERMER SE CONFIRME QUAND UNE SAISIE ATTEND ENCORE. Quitter avec des
  /// journées non transmises ne les perd pas — elles restent en base locale —
  /// mais l'animalier doit le savoir, sans quoi il croira son travail parti.
  Future<void> _confirmerFermeture(BuildContext context) async {
    if (enAttente == 0) {
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
          '$enAttente enregistrement(s) attendent encore d\'être transmis. '
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
