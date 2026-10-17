/// Écrans du client Desktop, et leur équivalent dans la maquette.
enum EcranPoste {
  /// Première entrée de la barre de la maquette, seule du groupe PILOTAGE.
  ///
  /// ⚠️ `dashboard.html` figure dans LES QUATRE listes de `RBAC_PAGE_MAP` :
  /// le tableau de bord est ouvert à tous les rôles, ce n'est pas un oubli de
  /// restriction.
  tableauDeBord('dashboard.html'),

  /// ⚠️ ENTRÉE RÉELLE DE LA BARRE DE LA MAQUETTE. Celle-ci ne liste AUCUNE
  /// fiche d'espèce : elles s'ouvrent depuis « Gestion Élevage ». Le poste
  /// reproduit ce chemin plutôt que d'ajouter cinq entrées que la maquette n'a
  /// pas — ce serait un ajout de structure.
  gestionElevage('gestion-elevage.html'),

  /// ⚠️ `elevage-dashboard.html` figure dans la liste de l'animalier ET dans
  /// celle de l'admin — pas dans celles du caissier ni du comptable.
  dashboardElevage('elevage-dashboard.html'),

  /// ⚠️⚠️ **PRESENT DANS LA MAQUETTE, ABSENT DE `RBAC_PAGE_MAP`** — verifie :
  /// `suivi-reproduction.html` n'apparait dans AUCUNE des quatre listes de
  /// `common.js`, exactement comme `saisie-depenses.html`. Applique telle
  /// quelle, la carte n'ouvre donc l'ecran qu'a `admin`, dont la liste vaut
  /// `null`.
  ///
  /// ⚠️ C'est contre-intuitif : la barre laterale de la maquette place
  /// « Suivi Reproduction » dans PRODUCTION ELEVAGE & SOINS, groupe de
  /// l'animalier, et c'est lui qui palpe les lapines. Rien n'est invente ici —
  /// la restriction decoule de la carte. **ARBITRAGE CLIENT** : faut-il
  /// ajouter la page a la liste de l'animalier ?
  suiviReproduction('suivi-reproduction.html'),

  /// ⚠️⚠️ **ÉCRAN PRÉSENT DANS LA MAQUETTE ET ABSENT DE `RBAC_PAGE_MAP`**
  /// — vérifié : `animal-details.html` n'apparaît dans AUCUNE des quatre listes de
  /// `common.js`. Appliquée telle quelle, la carte ne l'ouvre donc qu'à `admin`,
  /// comme `suivi-reproduction.html` qui y mène.
  ///
  /// ⚠️ C'est contre-intuitif : la fiche d'un reproducteur sert d'abord à
  /// l'animalier. Rien n'est inventé — la restriction découle de la carte.
  /// **ARBITRAGE CLIENT**, avec les autres écrans absents de la carte. Laravel
  /// exige `view-elevage` pour cette fiche, ce qui l'ouvrirait à l'animalier.
  ///
  /// ⚠️ **Écran à paramètre** : il s'ouvre sur UN sujet, depuis une référence du
  /// Suivi Reproduction. Il n'a donc pas d'entrée dans la barre latérale.
  ficheSujet('animal-details.html'),

  /// ⚠️ Le hub, et non ses trois pages : la barre latérale de la maquette ne
  /// porte qu'une entrée. `soins-vaccins-hub.html` et ses trois pages
  /// (`vms-registre`, `vms-calendrier`, `vms-suivi`) figurent toutes dans la
  /// liste de l'animalier — contrairement à `suivi-reproduction.html`.
  soinsEtVaccins('soins-vaccins-hub.html'),

  /// ⚠️⚠️ **QUATRIÈME ÉCRAN PRÉSENT DANS LA MAQUETTE ET ABSENT DE
  /// `RBAC_PAGE_MAP`** — vérifié : `parametres-elevage.html` n'apparaît dans
  /// AUCUNE des quatre listes de `common.js`, comme `suivi-reproduction.html`,
  /// `saisie-depenses.html` et `gestion-stocks.html`. Appliquée telle quelle,
  /// la carte n'ouvre donc l'écran qu'à `admin`, dont la liste vaut `null`.
  ///
  /// ⚠️ Ici, la restriction se défend : ces quatre référentiels fixent la
  /// ration servie et le protocole sanitaire de toute la ferme. Mais l'écran
  /// est en LECTURE SEULE au poste — le priver à l'animalier revient à lui
  /// cacher la règle qu'il applique. **ARBITRAGE CLIENT**, avec les trois
  /// autres pages absentes de la carte.
  parametresElevage('parametres-elevage.html'),
  ficheElevage('fiche-lapins.html'),
  fichePondeuses('fiche-volailles-pondeuses.html'),
  fichePorcs('fiche-porcs.html'),
  ficheReproducteurs('fiche-volailles-reproducteurs.html'),
  ficheEscargots('fiche-escargots.html'),

  /// ⚠️ Le HUB de vente, dont la caisse est le premier onglet. La barre
  /// latérale de la maquette ouvre `ventes-devis.html`, jamais
  /// `pos-interface.html` directement.
  ventesEtDevis('ventes-devis.html'),

  /// ⚠️ `creances-clients.html` figure dans la liste du caissier — c'est lui
  /// qui encaisse et qui relance.
  clientsEtCreances('creances-clients.html'),
  caisse('pos-interface.html'),

  /// ⚠️⚠️ **PRESENT DANS LA MAQUETTE, ABSENT DE `RBAC_PAGE_MAP`.** Verifie :
  /// `saisie-depenses.html` n'apparait dans AUCUNE des quatre listes de
  /// `common.js`. La consequence de la carte, appliquee telle quelle, est que
  /// seul `admin` (dont la liste vaut `null`, donc sans restriction) y accede —
  /// et c'est aussi le choix le plus prudent : saisir une depense decaisse la
  /// caisse et passe une ecriture SYSCOHADA.
  ///
  /// Rien n'est invente ici : la restriction decoule de la carte. **ARBITRAGE
  /// CLIENT** : faut-il ouvrir cet ecran au caissier sur le terrain ?
  /// ⚠️ Le HUB d'achat, et non ses trois pages : la barre latérale de la
  /// maquette ne porte qu'une entrée. `achats-commandes.html` charge
  /// `enregistrer-achat`, `liste-achats` et `bons-commande` en `<iframe>`.
  ///
  /// ⚠️⚠️ **CINQUIÈME ÉCRAN ABSENT DE `RBAC_PAGE_MAP`** — vérifié :
  /// `achats-commandes.html` n'apparaît dans aucune des quatre listes de
  /// `common.js`. Ici la restriction à `admin` se défend : un achat décaisse
  /// la caisse, entre de la marchandise au stock et passe une écriture.
  achatsEtCommandes('achats-commandes.html'),

  /// ⚠️ Le HUB fournisseurs — `fournisseurs.html` charge `ajouter-fournisseur`,
  /// `fiches-fournisseurs` et `dettes-fournisseurs` en `<iframe>`.
  ///
  /// ⚠️⚠️ **SIXIÈME ÉCRAN ABSENT DE `RBAC_PAGE_MAP`** : `fournisseurs.html`
  /// n'apparaît dans aucune des quatre listes de `common.js`.
  fournisseurs('fournisseurs.html'),

  /// ⚠️⚠️ **UNE FACTURE EST UNE VENTE** : `facturation.html` liste `sales`
  /// avec leur statut de normalisation MeCeF, il n'existe pas de table
  /// `invoices`.
  ///
  /// ⚠️ **CELUI-CI FIGURE BIEN DANS `RBAC_PAGE_MAP`**, dans la liste du
  /// CAISSIER — c'est lui qui encaisse, donc lui qui facture. Écrit d'abord
  /// « septième écran absent de la carte » par extrapolation des six
  /// précédents, corrigé par le test des permissions qui a vu la liste du
  /// caissier s'allonger. Six écrans manquent à la carte ; celui-là n'en fait
  /// pas partie.
  facturation('facturation.html'),

  /// ⚠️ Le HUB RH — `personnel-stages.html` charge cinq pages en `<iframe>` :
  /// registres employés et stagiaires, feuille de pointage, paie, attestations.
  ///
  /// ⚠️ VÉRIFIÉ DANS `RBAC_PAGE_MAP`, et pas extrapolé cette fois : la page
  /// n'apparaît dans aucune des quatre listes de `common.js` (voir le ticket
  /// F0.47, où l'extrapolation s'était trompée).
  personnelEtStages('personnel-stages.html'),

  /// ⚠️ Le HUB administratif — `administration.html` charge trois pages en
  /// `<iframe>` : courriers, archivage, documents administratifs.
  ///
  /// ⚠️ Vérifié dans `RBAC_PAGE_MAP` : absent des quatre listes.
  administrationEtDocument('administration.html'),

  /// ⚠️ Le HUB comptable — `comptabilite-hub.html` n'est PAS fait d'onglets
  /// mais de neuf CARTES DE NAVIGATION, chacune ouvrant une page.
  ///
  /// ⚠️ `comptabilite-hub.html` n'apparaît dans aucune des quatre listes de
  /// `RBAC_PAGE_MAP` — vérifié. En revanche `journal-comptable.html`,
  /// `rapport-bilan.html` et `cloture-exercice.html` figurent bien dans celle
  /// du COMPTABLE : c'est le hub qui manque à la carte, pas ses pages.
  comptabilite('comptabilite-hub.html'),

  /// ⚠️ Le HUB des paramètres — `parametres-hub.html` charge SIX pages en
  /// `<iframe>` : rôles & permissions, données de l'entreprise, modules
  /// actifs, gestion des utilisateurs, modes de paiement, audit logs.
  ///
  /// ⚠️⚠️ **NI LE HUB NI SES SIX PAGES N'APPARAISSENT DANS `RBAC_PAGE_MAP`** —
  /// vérifié, `grep` à zéro résultat sur les sept noms de fichier. La règle du
  /// prototype s'applique donc telle quelle : seul `admin`, dont la liste vaut
  /// `null`, y accède. C'est le comportement attendu pour un écran qui montre
  /// la matrice des droits et le journal d'audit de la ferme.
  parametresGeneraux('parametres-hub.html'),
  saisieDepenses('saisie-depenses.html'),

  /// ⚠️⚠️ **TROISIEME PAGE PRESENTE DANS LA MAQUETTE ET ABSENTE DE
  /// `RBAC_PAGE_MAP`** — verifie : `gestion-stocks.html` n'apparait dans
  /// AUCUNE des quatre listes de `common.js`, comme `saisie-depenses.html` et
  /// `suivi-reproduction.html`. Seul `admin` y accede, sa liste valant `null`.
  ///
  /// ⚠️ Trois ecrans hors carte, tous des ecrans de SAISIE qui engagent la
  /// ferme (une depense decaisse, une saillie ouvre un cycle, un ajustement
  /// corrige un stock). **ARBITRAGE CLIENT** : la carte doit-elle etre
  /// completee, ou ces ecrans rester reserves a l'administrateur ?
  gestionStocks('gestion-stocks.html'),

  /// ⚠️ Le HUB du catalogue, dont « Voir le Catalogue » et « Seuils d'Alerte »
  /// sont les deux onglets. Absent lui aussi de `RBAC_PAGE_MAP` — quatrieme
  /// page dans ce cas, mais la seule des quatre qui soit en LECTURE SEULE.
  catalogueProduits('catalogue-produits.html'),

  /// ⚠️⚠️ **LE SEUL ÉCRAN DU POSTE QUE LA CARTE RÉSERVE EXPLICITEMENT.**
  /// `rapports-exports.html` figure dans la liste `comptable` de
  /// `RBAC_PAGE_MAP` — avec ses six pages (`rapport-recettes-depenses`,
  /// `rapport-tresorerie`, `rapport-creances`, `rapport-dettes`,
  /// `rapport-elevage-synth`, `rapport-stocks-synth`) — et dans **aucune** des
  /// trois autres. Y accèdent donc le comptable et l'admin (liste `null`).
  ///
  /// ⚠️ Contrairement aux six écrans absents de la carte, **il n'y a rien à
  /// arbitrer ici** : la carte est explicite, et la restriction se défend
  /// d'elle-même — ce sont les états financiers de la ferme.
  rapportsEtExports('rapports-exports.html'),

  /// ⚠️⚠️ **OUVERT À TOUT RÔLE — DÉCISION DU COMMANDITAIRE (ticket F0.57).**
  /// `mon-profil.html` est dans AUCUNE des quatre listes de `RBAC_PAGE_MAP` :
  /// appliquée telle quelle, la carte ne l'aurait ouvert qu'à `admin`, et le
  /// caissier se serait vu refuser son propre profil. Laravel range le profil
  /// parmi les routes « réellement universelles » (`routes/web.php`) ; le
  /// commanditaire a tranché dans ce sens. La règle vit dans [_universels], pas
  /// dans la carte, qui reste recopiée du prototype sans retouche.
  ///
  /// ⚠️ Cela ne vaut que pour cet écran : `notifications`, `aide-a-propos` et
  /// `contact-editeur` ont été ajoutés par extension, voir leurs entrées.
  monProfil('mon-profil.html'),

  /// ⚠️⚠️ **OUVERT À TOUT RÔLE — EXTENSION DE LA DÉCISION SUR LE PROFIL, FAITE
  /// PAR LE DÉVELOPPEUR ET À CONFIRMER (ticket F0.59).** `notifications.html`
  /// est, comme `mon-profil.html`, dans AUCUNE liste de `RBAC_PAGE_MAP`. Le
  /// commanditaire a tranché pour le profil seulement ; mais la cloche figure
  /// dans la barre de TOUS les rôles, et la lui laisser sans écran derrière
  /// serait un défaut visible. Le risque est faible : le serveur ne sert que les
  /// notifications que l'utilisateur du jeton peut voir (`visibleTo`). Retirer
  /// l'écran de [PermissionsPoste._universels] suffit à revenir en arrière.
  notifications('notifications.html'),

  /// ⚠️⚠️ **OUVERT À TOUT RÔLE — MÊME EXTENSION QUE `notifications`, À CONFIRMER
  /// (ticket F0.60).** `aide-a-propos.html` est dans AUCUNE liste de
  /// `RBAC_PAGE_MAP` ; Laravel la range parmi les cinq routes « réellement
  /// universelles ». C'est une page de documentation, sans donnée : la refuser
  /// au caissier ne protégerait rien. Retirer l'écran de
  /// [PermissionsPoste._universels] suffit à revenir en arrière.
  aideEtAPropos('aide-a-propos.html'),

  /// ⚠️⚠️ **OUVERT À TOUT RÔLE — MÊME EXTENSION QUE `notifications` ET
  /// `aide-a-propos`, À CONFIRMER (ticket F0.62).** `contact-editeur.html` est
  /// dans AUCUNE liste de `RBAC_PAGE_MAP` ; Laravel la range parmi les cinq
  /// routes « réellement universelles ». Un caissier qui rencontre un défaut doit
  /// pouvoir le signaler : lui fermer cette porte le priverait du seul canal vers
  /// l'éditeur. Le serveur identifie l'expéditeur par son jeton. Retrait :
  /// [PermissionsPoste._universels].
  contactEditeur('contact-editeur.html'),

  /// ⚠️ Hors maquette : la surface web n'a ni file locale ni poste à régler.
  /// Ces deux-là ne figurent donc dans AUCUNE liste de `RBAC_PAGE_MAP` — leur
  /// règle est décidée ici, et dite (voir [_horsMaquette]).
  synchronisation(null),
  parametres(null);

  const EcranPoste(this.page);

  /// Fichier correspondant du prototype, `null` si l'écran n'y existe pas.
  final String? page;
}

/// Contrôle d'accès par rôle, transposé de `RBAC_PAGE_MAP`
/// (`prototype_html/assets/js/common.js`).
///
/// ⚠️ **LA CARTE EST RECOPIÉE TELLE QUELLE, PAS RÉINTERPRÉTÉE.** Le projet
/// porte une incohérence connue et documentée sur le nombre de rôles — le CDC
/// en annonce 7, l'énumération 6, la matrice 5, et `RBAC_PAGE_MAP` en
/// implémente 4. Cette contradiction ne doit PAS être résolue sans accord du
/// client : trancher arbitrairement serait une régression, pas un nettoyage.
/// On s'en tient donc aux 4 rôles de la carte.
///
/// ⚠️⚠️ **UN RÔLE INCONNU DE LA CARTE N'EST PAS RESTREINT** — c'est exactement
/// ce que fait le prototype (`var allowedPages = RBAC_PAGE_MAP[role]; if
/// (allowedPages) { … }` : sans entrée, aucune vérification n'a lieu). La
/// fidélité comportementale l'impose, MAIS la conséquence doit être dite : un
/// utilisateur portant l'un des rôles du CDC absents de la carte accéderait à
/// tout. **ARBITRAGE CLIENT REQUIS** — soit la carte est complétée, soit le
/// refus par défaut est acté. Le résoudre ici sans mandat reviendrait à
/// choisir à la place du client sur une question de sécurité.
class PermissionsPoste {
  const PermissionsPoste._();

  /// `null` signifie « aucune restriction », comme `'admin': null` dans la
  /// carte du prototype.
  static const Map<String, List<String>?> carte = {
    'admin': null,
    'caissier': [
      'dashboard.html',
      'ventes-devis.html',
      'creances-clients.html',
      'facturation.html',
      'pos-interface.html',
      'historique-ventes.html',
      'devis.html',
      'retours-avoirs.html',
      'liste-clients.html',
      'suivi-dettes.html',
      'relances-clients.html',
      'historique-avances.html',
      'profile-client.html',
    ],
    'animalier': [
      'dashboard.html',
      'gestion-elevage.html',
      'soins-vaccins-hub.html',
      'elevage-dashboard.html',
      'gestion-bandes.html',
      'transformation.html',
      'enregistrer-sujets.html',
      'fiche-lapins.html',
      'fiche-volailles.html',
      'fiche-volailles-pondeuses.html',
      'fiche-volailles-reproducteurs.html',
      'fiche-porcs.html',
      'fiche-escargots.html',
      'vms-registre.html',
      'vms-calendrier.html',
      'vms-suivi.html',
    ],
    'comptable': [
      'dashboard.html',
      'journal-comptable.html',
      'rapport-bilan.html',
      'cloture-exercice.html',
      'comptabilite-analytique.html',
      'rapports-exports.html',
      'rapport-recettes-depenses.html',
      'rapport-tresorerie.html',
      'rapport-mensuel.html',
      'rapport-creances.html',
      'rapport-dettes.html',
      'rapport-elevage-synth.html',
      'rapport-stocks-synth.html',
    ],
  };

  /// Écrans ouverts à tout rôle authentifié, hors de la carte du prototype.
  static const _universels = {
    EcranPoste.monProfil,
    EcranPoste.notifications,
    EcranPoste.aideEtAPropos,
    EcranPoste.contactEditeur,
  };

  static bool autorise(String role, EcranPoste ecran) {
    final page = ecran.page;

    if (page == null) return _horsMaquette(role, ecran);

    // Écrans universels décidés par le commanditaire : ni carte, ni rôle.
    if (_universels.contains(ecran)) return true;

    // Rôle absent de la carte : aucune restriction, comme le prototype.
    if (!carte.containsKey(role)) return true;

    final pages = carte[role];

    // `null` = accès total (admin).
    if (pages == null) return true;

    return pages.contains(page);
  }

  /// Règle des deux écrans absents de la maquette.
  ///
  /// ⚠️ **LA SYNCHRONISATION EST OUVERTE À TOUS LES RÔLES.** Chaque rôle
  /// produit des saisies qui n'existent que sur ce poste tant qu'elles ne sont
  /// pas parties. La réserver à l'administrateur emprisonnerait les ventes du
  /// caissier sur la machine jusqu'à son passage — c'est-à-dire exactement le
  /// travail perdu que l'offline-first doit éviter.
  ///
  /// ⚠️ **LES PARAMÈTRES DU POSTE SONT RÉSERVÉS À L'ADMINISTRATEUR.** Y changer
  /// l'adresse du serveur couperait la ferme de sa base ; ce n'est pas un
  /// geste de comptoir.
  static bool _horsMaquette(String role, EcranPoste ecran) => switch (ecran) {
    EcranPoste.synchronisation => true,
    EcranPoste.parametres => role == 'admin',
    _ => true,
  };

  /// Écrans réellement accessibles, dans l'ordre de la barre latérale.
  static List<EcranPoste> ecransDe(String role) =>
      EcranPoste.values.where((e) => autorise(role, e)).toList();
}
