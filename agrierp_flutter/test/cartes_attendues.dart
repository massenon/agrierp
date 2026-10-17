import 'structure_maquette.g.dart';

/// Nombre de cartes d'indicateur attendu d'un écran porté — ticket F0.54.
///
/// ⚠️⚠️ **POURQUOI CE FICHIER EXISTE PLUTÔT QU'UN `cartesMaquette[page]!` DANS
/// CHAQUE TEST.** Le relevé de la maquette fait foi par défaut. Mais le poste
/// s'en écarte parfois **volontairement**, et le ticket F0.53 vient de montrer
/// ce qui arrive quand un tel écart n'est expliqué qu'en commentaire dans
/// l'écran : il **ressemble** à une décision consignée sans en être une, et le
/// contrôle qui devrait le signaler se tait.
///
/// Un écart au nombre de cartes se déclare donc ICI, avec sa raison, et nulle
/// part ailleurs.
///
/// ⚠️ Deux contrôles gardent cette liste honnête (`cartes_attendues_test.dart`) :
/// une entrée doit désigner une page réelle, et elle doit **réellement
/// différer** de la maquette — une entrée qui répète le relevé est une
/// exemption morte qui masquerait le jour où l'écran, lui, dérive.
const ecartsAssumes = <String, (int, String)>{
  // ── `facturation.html` : 3 cartes dans la maquette, 4 au poste ────────────
  'facturation.html': (
    4,
    "⚠️⚠️ UNE CARTE DE PLUS, ET C'EST TOUT LE SUJET DU TICKET 14.80. La "
        "maquette compte « Factures (mois) », « Statut Transmise » et « En "
        "attente ». Le poste ajoute « Erreur MeCeF » : « erreur » veut dire que "
        "la DGI a REFUSÉ, « en attente » que personne n'a encore essayé parce "
        "que la vente n'a pas quitté ce poste. Les additionner masquerait lequel "
        "des deux problèmes se pose — et c'est précisément le trou fiscal que le "
        "ticket 14.80 a dû combler.",
  ),

  // ── `archivage-documents.html` : 2 cartes dans la maquette, 3 au poste ────
  // (recalibré au ticket F0.79 : la raison d'avant décrivait une scission « Expirés » /
  // « À renouveler » qui n'existe plus ; le nombre, lui, reste 3)
  'archivage-documents.html': (
    3,
    "⚠️ UNE CARTE DE PLUS : « Expirés ». Les deux cartes de la maquette sont "
        "portées avec ses libellés (« Documents archivés », « Expirant sous "
        "30j »), « Expirant sous 30j » comptant, comme le serveur (15.24), les "
        "documents actifs « Bientôt expiré » (1 à 30 jours). La maquette n'a "
        "aucune carte pour les documents DÉJÀ expirés (échéance atteinte ou "
        "dépassée) : un agrément vétérinaire périmé expose la ferme "
        "aujourd'hui, alors qu'un bail qui expire dans trois semaines se "
        "planifie. Les confondre dans un seul compteur ferait passer le premier "
        "pour le second. L'ancienne carte « À renouveler » (seuil de 60 jours) "
        "est retirée (F0.79) : ni la maquette ni le serveur n'ont ce seuil.",
  ),

  // ── `documents-administratifs.html` : 2 cartes dans la maquette, 3 au poste ─
  // (ticket F0.80 ; DÉCISION PROVISOIRE DU LEAD, à confirmer par le client)
  'documents-administratifs.html': (
    3,
    "⚠️ UNE CARTE DE PLUS : « En attente ». Les deux cartes de la maquette sont "
        "portées avec ses libellés : « Modèles disponibles » vaut « — » (le poste "
        "n'a aucun catalogue de modèles, le serveur non plus : « 0 » dirait que "
        "la ferme n'en possède aucun) et « Générés (mois) » compte, comme la page "
        "web, les documents ACTIFS dont la date tombe dans le mois courant. "
        "« En attente » compte les documents actifs en attente de signature : la "
        "maquette n'a pas ce chiffre, mais un document non signé est la seule "
        "alerte de cet écran et le serveur porte le statut. Les anciennes cartes "
        "« Documents » et « Signés » (absentes de la maquette) sont retirées. "
        "AJOUT ASSUMÉ, à faire valider.",
  ),

  // ── `grand-livre.html` : 3 cartes à liseré dans le relevé, 4 au poste ─────
  // (ticket F0.85)
  'grand-livre.html': (
    4,
    "⚠️ LE RELEVÉ COMPTE 3 CARTES, LA MAQUETTE EN MONTRE 4. L'extracteur ne compte que les cartes à "
        "`border-l-4` : « Solde Final » (`bg-accent-yellow/10 border-accent-yellow/30`, sans liseré) "
        "lui échappe, alors qu'elle est bien la quatrième carte de la page, avec « Solde d'Ouverture », "
        "« Total Débit Période » et « Total Crédit Période ». La page web du serveur la rend aussi "
        "(`x-kpi-card` jaune). Le poste la porte avec `CarteKpi` (liseré jaune) : la teinte de fond de "
        "la maquette n'est pas reproduite, `CarteKpi` n'ayant pas cette variante. Pas d'ajout du "
        "poste : un relevé incomplet, pas un écart de contenu.",
  ),

  // ── `balance-generale.html` : 2 cartes à liseré dans le relevé, 3 au poste ──
  // (ticket F0.86)
  'balance-generale.html': (
    3,
    "⚠️ LE RELEVÉ COMPTE 2 CARTES, LA MAQUETTE EN MONTRE 3. L'extracteur ne compte que les cartes à "
        "`border-l-4` : « Écart (doit être 0) » (`bal-ecart-card`, bordure et fond teintés en vert ou "
        "en rouge par le script, sans liseré) lui échappe, alors qu'elle est la troisième carte de la "
        "page, avec « Total Débits (Soldes Finaux) » et « Total Crédits (Soldes Finaux) ». La page web "
        "du serveur la rend aussi. Le poste la porte avec `CarteKpi` (liseré et valeur verts si "
        "équilibrée, rouges sinon) : la teinte de fond de la maquette n'est pas reproduite. Pas "
        "d'ajout du poste : un relevé incomplet, comme `grand-livre.html`. "
        "⚠️ ÉCART ASSUMÉ SUR LA VALEUR (ticket F0.88, arbitrage client du 13/10/2026) : un écart "
        "NON NUL s'écrit avec ses centimes (« -0,40 F », virgule décimale, espace des milliers), "
        "là où le web écrit `number_format(\$ecart, 0)` — un écart de 0,40 F y paraissait « 0 F » "
        "en rouge sous le bandeau « Balance Déséquilibrée ». Un écart nul reste « 0 F » ; seuil "
        "d'équilibre inchangé (|écart| < 0,01, Laravel) ; signe = débits − crédits.",
  ),

  // ── `feuille-pointage.html` : 3 cartes dans la maquette, 4 au poste ───────
  'feuille-pointage.html': (
    4,
    "⚠️ UNE QUATRIÈME CARTE, PROPRE AU POSTE : « À pointer ». Elle compte les "
        "employés non encore pointés ET, en légende, les pointages qui "
        "attendent d'être envoyés. La maquette n'en a pas besoin — sur le web, "
        "un pointage saisi est un pointage parti. Au poste, il peut dormir des "
        "jours dans la file : c'est exactement ce que l'offline-first doit "
        "rendre visible. Addition défendable, jamais consignée avant ce ticket.",
  ),
};

/// Écarts CONSTATÉS et NON JUSTIFIÉS — des manques, pas des décisions.
///
/// ⚠️⚠️ **DEUX LISTES, PARCE QUE CE SONT DEUX CHOSES.** [ecartsAssumes] dit
/// « nous avons décidé de nous écarter de la maquette, voici pourquoi ».
/// Celle-ci dit « l'écran ne fait pas ce que la maquette demande, et nous ne
/// l'avons pas encore corrigé ». Les ranger ensemble reviendrait à blanchir un
/// défaut en décision — exactement le glissement que le ticket F0.53 a trouvé
/// sur les libellés, où quinze décisions n'existaient qu'en commentaire.
///
/// Une entrée ici est une **dette ouverte**. Elle se solde en portant les
/// cartes manquantes, pas en réécrivant sa raison.
const ecartsATraiter = <String, (int, String)>{
  // ⚠️ `documents-administratifs.html` en est SORTI au ticket F0.80 : ses deux cartes sont
  // portées avec les libellés de la maquette (« Modèles disponibles » = « — », « Générés
  // (mois) »), et la troisième est un écart ASSUMÉ (voir `ecartsAssumes`).

  // ── Comptabilité : les indicateurs ont été REGROUPÉS SUR LE HUB ───────────
  //
  // ⚠️⚠️ Les quatre cartes de l'écran (« Écritures reçues », « Total Débit »,
  // « Total Crédit », « Écritures incomplètes ») sont rendues sur le HUB, pas
  // sur les pages. Ouvrir « Journal Comptable » n'affiche donc aucun
  // indicateur là où la maquette en montre trois — dont deux qui portent
  // exactement les mêmes chiffres, un cran plus haut.
  //
  // ⚠️ Le hub lui-même échappe au contrôle : `comptabilite-hub.html` n'a jamais
  // été passé à l'extracteur de structure. Ses quatre cartes ne sont donc
  // comparées à rien.
  //
  // Ce n'est pas un oubli mais un DÉPLACEMENT, et il demande un arbitrage :
  // remonter les indicateurs sur chaque page, ou acter le regroupement.
};

/// Nombre de cartes attendu pour [page] : le relevé de la maquette, l'écart
/// assumé, ou le manque constaté — dans cet ordre de priorité.
int cartesAttendues(String page) =>
    ecartsAssumes[page]?.$1 ??
    ecartsATraiter[page]?.$1 ??
    cartesMaquette[page]!;

/// Écarts assumés au niveau d'un PANNEAU d'onglet — clé `page.html#panneau`.
///
/// ⚠️⚠️ **LE TOTAL SEUL AURAIT LAISSÉ PASSER `elevage-dashboard`.** L'écran
/// rendait 11 cartes contre 15 relevées ; l'écart réel n'était pas « quatre en
/// moins » mais **−4, −3 et +3 sur trois onglets différents**, qui se
/// compensaient presque. Sans relevé par panneau, un tel écran passe pour
/// approximativement conforme alors qu'il ne l'est nulle part.
const ecartsPanneaux = <String, (int, String)>{
  'elevage-dashboard.html#dash-tab-sanitaire': (
    3,
    "⚠️ TROIS CARTES QUE LA MAQUETTE N'A PAS. Son onglet sanitaire n'affiche "
        "qu'un tableau de morbidité. Le poste y ajoute « Traitements du Mois », "
        "« Coût Sanitaire du Mois » et « Traitement le Plus Fréquent » — trois "
        "chiffres qu'il détient réellement, `veterinary_records` étant tirée. "
        "AJOUT ASSUMÉ, à faire valider : il enrichit l'écran mais s'écarte de "
        "la maquette, et rien ne le signalait avant ce ticket.",
  ),
};

/// Nombre de cartes attendu pour un panneau d'onglet.
int cartesAttenduesPanneau(String page, String panneau) =>
    ecartsPanneaux['$page#$panneau']?.$1 ?? cartesParPanneau[page]![panneau]!;
