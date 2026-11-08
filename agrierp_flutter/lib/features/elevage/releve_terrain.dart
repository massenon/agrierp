/// Ticket RELEVES-1 — RÈGLES PURES de l'onglet « Relevés de terrain » (Paramètres Élevage) : types, validation, calculs
/// et résumé des valeurs. Transposition de `App\Services\Elevage\ReleveTerrainService` (le web est le maître).
///
/// ⚠️ **PARITÉ EXÉCUTÉE** (`test/releve_terrain_parite_php_test.dart`) : durée observée, taux de fertilité et
/// d'éclosion, résumé des valeurs et messages de refus sont comparés au VRAI PHP. Un calcul modifié d'un seul côté
/// fait rougir ce test. « — » (`null`) = donnée manquante : JAMAIS « 0 ».
library;

class ReleveTerrain {
  ReleveTerrain._();

  static const aValider = 'a_valider';
  static const valide = 'valide';

  static const statuts = {aValider: 'À valider', valide: 'Validé'};

  static const incubationRegle = 'incubation_regle';
  static const incubationLot = 'incubation_lot';
  static const delaiRegle = 'delai_regle';
  static const poissonMarque = 'poisson_marque';
  static const poissonBareme = 'poisson_bareme';
  static const poissonTemperature = 'poisson_temperature';
  static const poissonDensite = 'poisson_densite';

  /// type → famille (sous-onglet), dans l'ordre du serveur.
  static const familles = {
    incubationRegle: 'incubation',
    incubationLot: 'incubation',
    delaiRegle: 'provende',
    poissonMarque: 'technicien',
    poissonBareme: 'technicien',
    poissonTemperature: 'technicien',
    poissonDensite: 'technicien',
  };

  static const typesLibelles = {
    incubationRegle: "Règle d'incubation",
    incubationLot: 'Relevé de lot',
    delaiRegle: 'Règle du délai fournisseur',
    poissonMarque: 'Marque de granulés',
    poissonBareme: 'Barème du fabricant',
    poissonTemperature: "Température de l'eau",
    poissonDensite: "Densité d'empoissonnement",
  };

  static const modes = {
    'couveuse_artificielle': 'Couveuse artificielle',
    'couvaison_naturelle': 'Couvaison naturelle (sous poule ou pintade)',
  };

  static const modesDelai = {
    'constate': 'Le plus long des 5 derniers délais',
    'manuel': 'Valeurs saisies',
  };

  static const nbBons = 5;
  static const critiqueDepart = 3;
  static const alerteDepart = 7;
  static const margeDefaut = 4;

  // ── Affichage ───────────────────────────────────────────────────────────────────────────────────────

  /// `ReleveTerrainService::nb` : entier sans décimale, sinon 2 décimales utiles à la virgule, « — » si absent.
  static String nb(Object? v) {
    if (v == null || v == '') return '—';
    final f = v is num ? v.toDouble() : double.parse(v.toString());
    if (f == f.truncateToDouble()) return f.truncate().toString();
    var t = f.toStringAsFixed(2).replaceAll('.', ',');
    t = t.replaceFirst(RegExp(r'0+$'), '');
    return t.replaceFirst(RegExp(r',$'), '');
  }

  static String _dateFr(Object? d) {
    if (d == null || d == '') return '—';
    final x = DateTime.parse(d.toString());
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(x.day)}/${deux(x.month)}/${x.year}';
  }

  static String _texte(Object? v) => (v == null || v.toString().isEmpty) ? '—' : v.toString();

  /// Résumé lisible des valeurs d'une ligne (colonne « Valeurs ») : celui du web, mot pour mot.
  static String resume(String type, Map<String, dynamic> d) {
    final parties = switch (type) {
      incubationRegle => [
        '${nb(d['duree_jours'])} j',
        'éclosion J${nb(d['eclosion_min'])} à J${nb(d['eclosion_max'])}',
        modes[d['mode']] ?? '—',
        'mirages ${(d['mirages'] is List && (d['mirages'] as List).isNotEmpty) ? 'J${(d['mirages'] as List).join(', J')}' : '—'}',
        'éclosoir ${d['transfert_jour'] != null ? 'J${nb(d['transfert_jour'])}' : '—'}',
        'œufs conservés ≤ ${nb(d['conservation_max_jours'])} j',
      ],
      incubationLot => () {
        final c = calculsLot(d);
        return [
          'mise le ${_dateFr(d['mise_date'])}',
          modes[d['mode']] ?? '—',
          'mis ${nb(d['oeufs_mis'])}',
          'fertiles ${nb(d['oeufs_fertiles'])}',
          'éclos ${nb(d['oeufs_eclos'])}',
          'durée observée ${c.dureeJours == null ? '—' : '${c.dureeJours} j'}',
          'fertilité ${c.tauxFertilite == null ? '—' : '${nb(c.tauxFertilite)} %'}',
          'éclosion ${c.tauxEclosion == null ? '—' : '${nb(c.tauxEclosion)} %'}',
        ];
      }(),
      delaiRegle => [
        modesDelai[d['mode']] ?? '—',
        'critique ${nb(d['critique_jours'])} j',
        'alerte ${nb(d['alerte_jours'])} j',
        'marge ${nb(d['marge_jours'])} j',
      ],
      poissonMarque => [d['marque'] == null || d['marque'] == '' ? '—' : d['marque'].toString()],
      poissonBareme => [
        if (d['poids_max_g'] == null)
          'plus de ${nb(d['poids_min_g'])} g'
        else if (((d['poids_min_g'] as num?) ?? 0).toDouble() == 0.0)
          'moins de ${nb(d['poids_max_g'])} g'
        else
          '${nb(d['poids_min_g'])} à ${nb(d['poids_max_g'])} g',
        '${nb(d['biomasse_min_pct'])} à ${nb(d['biomasse_max_pct'])} % de la biomasse par jour',
        'granulé : ${_texte(d['granule'])}',
        'protéine : ${d['proteine_pct'] != null ? '${nb(d['proteine_pct'])} %' : '—'}',
      ],
      poissonTemperature => [
        'optimale ${nb(d['optimale_min'])} à ${nb(d['optimale_max'])} °C',
        'réduire la ration sous ${nb(d['reduire_sous'])} °C',
      ],
      poissonDensite => [d['densite'] != null ? '${nb(d['densite'])} ${d['unite'] ?? ''}' : '— (à renseigner)'],
      _ => <String>[],
    };
    return parties.join(' · ').trim();
  }

  // ── Calculs ─────────────────────────────────────────────────────────────────────────────────────────

  static DateTime? _jour(Object? v) {
    if (v == null || v.toString().isEmpty) return null;
    final x = DateTime.tryParse(v.toString());
    return x == null ? null : DateTime.utc(x.year, x.month, x.day);
  }

  static double _arrondi1(double v) => (v * 10).round() / 10;

  /// `ReleveTerrainService::calculsLot` : durée observée (premier éclos − mise en incubation, en jours), taux de
  /// fertilité (fertiles ÷ mis) et d'éclosion (éclos ÷ fertiles), en % à 1 décimale. Donnée manquante ou
  /// dénominateur nul : `null` (« — »), jamais « 0 ».
  static CalculsLot calculsLot(Map<String, dynamic> d) {
    final mise = _jour(d['mise_date']);
    final premier = _jour(d['premier_eclos_date']);
    final mis = (d['oeufs_mis'] as num?)?.toInt();
    final fertiles = (d['oeufs_fertiles'] as num?)?.toInt();
    final eclos = (d['oeufs_eclos'] as num?)?.toInt();
    return CalculsLot(
      dureeJours: mise != null && premier != null ? premier.difference(mise).inDays : null,
      tauxFertilite: (mis != null && fertiles != null && mis > 0) ? _arrondi1(fertiles / mis * 100) : null,
      tauxEclosion: (fertiles != null && eclos != null && fertiles > 0) ? _arrondi1(eclos / fertiles * 100) : null,
    );
  }

  // ── Validation (mêmes messages que le web) ──────────────────────────────────────────────────────────

  static const _attributs = {
    'data.duree_jours': "durée d'incubation",
    'data.eclosion_min': "premier jour d'éclosion",
    'data.eclosion_max': "dernier jour d'éclosion",
    'data.mode': 'mode',
    'data.mirages': 'jours de mirage',
    'data.transfert_jour': "jour de transfert à l'éclosoir",
    'data.conservation_max_jours': 'conservation maximale des œufs',
    'data.mise_date': 'date de mise en incubation',
    'data.oeufs_mis': 'œufs mis',
    'data.oeufs_fertiles': 'œufs fertiles',
    'data.oeufs_eclos': 'œufs éclos',
    'data.premier_eclos_date': 'date du premier éclos',
    'data.dernier_eclos_date': 'date du dernier éclos',
    'data.marge_jours': 'marge de sécurité',
    'data.critique_jours': 'délai critique',
    'data.alerte_jours': "délai d'alerte",
    'data.marque': 'marque',
    'data.poids_min_g': 'poids minimal',
    'data.poids_max_g': 'poids maximal',
    'data.biomasse_min_pct': '% de biomasse minimal',
    'data.biomasse_max_pct': '% de biomasse maximal',
    'data.granule': 'taille du granulé',
    'data.proteine_pct': 'protéine',
    'data.optimale_min': 'température optimale minimale',
    'data.optimale_max': 'température optimale maximale',
    'data.reduire_sous': 'seuil de réduction de la ration',
    'data.densite': 'densité',
    'data.unite': 'unité',
  };

  static String? _t(Object? v) {
    if (v == null || v is List || v is Map) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  static String _fr(num v) {
    final t = v.toDouble().toStringAsFixed(2).replaceAll('.', ',').replaceFirst(RegExp(r'0+$'), '');
    return t.replaceFirst(RegExp(r',$'), '');
  }

  static num? _nombre(Object? v, Map<String, String> e, String cle, num min, num max) {
    var t = _t(v);
    if (t == null) return null;
    t = t.replaceAll(',', '.').replaceAll(' ', '');
    final f = double.tryParse(t);
    if (f == null || f < min || f > max) {
      e[cle] = 'Le champ ${_attributs[cle]} doit être un nombre compris entre ${_fr(min)} et ${_fr(max)}.';
      return null;
    }
    return f == f.truncateToDouble() ? f.truncate() : (f * 100).round() / 100;
  }

  static int? _entier(Object? v, Map<String, String> e, String cle, int min, int max) {
    final t = _t(v);
    if (t == null) return null;
    if (!RegExp(r'^\d+$').hasMatch(t) || int.parse(t) < min || int.parse(t) > max) {
      e[cle] = 'Le champ ${_attributs[cle]} doit être un nombre entier compris entre $min et $max.';
      return null;
    }
    return int.parse(t);
  }

  static T? _requis<T>(T? valeur, Map<String, String> e, String cle) {
    if (valeur == null && !e.containsKey(cle)) e[cle] = 'Le champ ${_attributs[cle]} est obligatoire.';
    return valeur;
  }

  static String? _date(Object? v, Map<String, String> e, String cle) {
    final t = _t(v);
    if (t == null) return null;
    final dix = t.length >= 10 ? t.substring(0, 10) : t;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dix);
    DateTime? d;
    if (m != null) {
      d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (d.year != int.parse(m[1]!) || d.month != int.parse(m[2]!) || d.day != int.parse(m[3]!)) d = null;
    }
    if (d == null) {
      e[cle] = 'Le champ ${_attributs[cle]} doit être une date valide (AAAA-MM-JJ).';
      return null;
    }
    return dix;
  }

  /// Valide et NORMALISE une saisie (mêmes règles et mêmes messages que `ReleveTerrainService::normaliser`, hors
  /// vérifications de base — unicité, règle d'espèce — que fait le dépôt). Clés d'erreur : `label`, `species_code`,
  /// `data.x`. `especeFixe` : espèce imposée par le type (poissons-chats, délai).
  static ResultatReleve normaliser(String type, {required String? label, String? especeCode, required Map<String, dynamic> data}) {
    final e = <String, String>{};
    if (!familles.containsKey(type)) return const ResultatReleve.refus({'type': 'Type de relevé inconnu.'});

    final lib = (label ?? '').trim();
    if (lib.isEmpty) {
      e['label'] = 'Le libellé est obligatoire.';
    } else if (lib.length > 150) {
      e['label'] = 'Le libellé ne peut pas dépasser 150 caractères.';
    }
    var espece = _t(especeCode);
    Map<String, dynamic> d = {};

    switch (type) {
      case incubationRegle:
        d = _regleIncubation(data, e);
        if (espece == null || !RegExp(r'^[a-z0-9_-]{2,40}$').hasMatch(espece)) {
          e['species_code'] = "L'espèce est obligatoire (lettres minuscules, chiffres, tiret).";
        }
      case incubationLot:
        d = _lotIncubation(data, e);
        if (espece == null) e['species_code'] = "L'espèce est obligatoire.";
      case delaiRegle:
        d = _regleDelai(data, e);
        espece = null;
      case poissonMarque:
        final marque = _t(data['marque']);
        if (marque != null && marque.length > 100) e['data.marque'] = 'La marque ne peut pas dépasser 100 caractères.';
        d = {'marque': marque};
        espece = 'poisson_chat';
      case poissonBareme:
        d = _baremePoisson(data, e);
        espece = 'poisson_chat';
      case poissonTemperature:
        d = _temperaturePoisson(data, e);
        espece = 'poisson_chat';
      case poissonDensite:
        final densite = _nombre(data['densite'], e, 'data.densite', 0, 100000);
        final unite = _t(data['unite']);
        d = {'densite': densite, 'unite': unite};
        if (unite != null && unite.length > 30) e['data.unite'] = "L'unité ne peut pas dépasser 30 caractères.";
        espece = 'poisson_chat';
    }

    if (e.isNotEmpty) return ResultatReleve.refus(e);
    return ResultatReleve.ok(label: lib, especeCode: espece, data: d);
  }

  static Map<String, dynamic> _regleIncubation(Map<String, dynamic> b, Map<String, String> e) {
    final duree = _requis(_entier(b['duree_jours'], e, 'data.duree_jours', 1, 60), e, 'data.duree_jours');
    final min = _requis(_entier(b['eclosion_min'], e, 'data.eclosion_min', 1, 60), e, 'data.eclosion_min');
    final max = _requis(_entier(b['eclosion_max'], e, 'data.eclosion_max', 1, 60), e, 'data.eclosion_max');
    if (duree != null && min != null && min > duree) {
      e['data.eclosion_min'] = "Le premier jour d'éclosion ne peut pas dépasser la durée d'incubation.";
    }
    if (duree != null && max != null && max < duree) {
      e['data.eclosion_max'] = "Le dernier jour d'éclosion ne peut pas être inférieur à la durée d'incubation.";
    }
    final mode = _t(b['mode']);
    if (!modes.containsKey(mode ?? '')) e['data.mode'] = "Choisissez un mode d'incubation.";

    final mirages = b['mirages'] ?? [];
    final jours = mirages is List
        ? mirages.map((x) => x.toString()).toList()
        : mirages.toString().trim().split(RegExp(r'[\s,;]+')).where((x) => x.isNotEmpty).toList();
    var ok = jours.isNotEmpty && jours.length <= 3;
    final liste = <int>[];
    for (final j in jours) {
      final n = num.tryParse(j);
      if (n == null || n != n.truncate() || n.truncate() < 1 || (duree != null && n.truncate() >= duree)) {
        ok = false;
        break;
      }
      liste.add(n.truncate());
    }
    for (var i = 1; ok && i < liste.length; i++) {
      ok = liste[i] > liste[i - 1];
    }
    if (!ok) e['data.mirages'] = "Les jours de mirage doivent être 1 à 3 entiers croissants, tous inférieurs à la durée d'incubation.";

    final transfert = _entier(b['transfert_jour'], e, 'data.transfert_jour', 1, 60);
    if (transfert != null && ok && duree != null && (transfert <= liste.last || transfert >= duree)) {
      e['data.transfert_jour'] = "Le jour de transfert doit se situer après le dernier mirage et avant la fin de l'incubation.";
    }
    final conservation = _requis(_entier(b['conservation_max_jours'], e, 'data.conservation_max_jours', 1, 30), e, 'data.conservation_max_jours');
    return {
      'duree_jours': duree,
      'eclosion_min': min,
      'eclosion_max': max,
      'mode': mode,
      'mirages': ok ? liste : <int>[],
      'transfert_jour': transfert,
      'conservation_max_jours': conservation,
    };
  }

  static Map<String, dynamic> _lotIncubation(Map<String, dynamic> b, Map<String, String> e) {
    final mise = _requis(_date(b['mise_date'], e, 'data.mise_date'), e, 'data.mise_date');
    final mode = _t(b['mode']);
    if (!modes.containsKey(mode ?? '')) e['data.mode'] = "Choisissez un mode d'incubation.";
    final mis = _entier(b['oeufs_mis'], e, 'data.oeufs_mis', 1, 1000000);
    final fertiles = _entier(b['oeufs_fertiles'], e, 'data.oeufs_fertiles', 0, 1000000);
    final eclos = _entier(b['oeufs_eclos'], e, 'data.oeufs_eclos', 0, 1000000);
    if (mis != null && fertiles != null && fertiles > mis) e['data.oeufs_fertiles'] = 'Les œufs fertiles ne peuvent pas dépasser les œufs mis.';
    if (fertiles != null && eclos != null && eclos > fertiles) e['data.oeufs_eclos'] = 'Les œufs éclos ne peuvent pas dépasser les œufs fertiles.';
    final premier = _date(b['premier_eclos_date'], e, 'data.premier_eclos_date');
    final dernier = _date(b['dernier_eclos_date'], e, 'data.dernier_eclos_date');
    if (mise != null && premier != null && premier.compareTo(mise) < 0) {
      e['data.premier_eclos_date'] = 'Le premier éclos ne peut pas précéder la mise en incubation.';
    }
    if (premier != null && dernier != null && dernier.compareTo(premier) < 0) {
      e['data.dernier_eclos_date'] = 'Le dernier éclos ne peut pas précéder le premier.';
    }
    return {
      'mise_date': mise,
      'mode': mode,
      'oeufs_mis': mis,
      'oeufs_fertiles': fertiles,
      'oeufs_eclos': eclos,
      'premier_eclos_date': premier,
      'dernier_eclos_date': dernier,
    };
  }

  static Map<String, dynamic> _regleDelai(Map<String, dynamic> b, Map<String, String> e) {
    final mode = _t(b['mode']);
    if (!modesDelai.containsKey(mode ?? '')) e['data.mode'] = 'Choisissez comment fixer les seuils.';
    final marge = _requis(_entier(b['marge_jours'], e, 'data.marge_jours', 0, 30), e, 'data.marge_jours');
    final critique = _requis(_entier(b['critique_jours'], e, 'data.critique_jours', 0, 60), e, 'data.critique_jours');
    final alerte = _requis(_entier(b['alerte_jours'], e, 'data.alerte_jours', 0, 90), e, 'data.alerte_jours');
    if (critique != null && alerte != null && alerte < critique) {
      e['data.alerte_jours'] = "Le délai d'alerte ne peut pas être inférieur au délai critique.";
    }
    return {'mode': mode, 'marge_jours': marge, 'critique_jours': critique, 'alerte_jours': alerte};
  }

  static Map<String, dynamic> _baremePoisson(Map<String, dynamic> b, Map<String, String> e) {
    final min = _requis(_nombre(b['poids_min_g'], e, 'data.poids_min_g', 0, 100000), e, 'data.poids_min_g');
    final max = _nombre(b['poids_max_g'], e, 'data.poids_max_g', 0, 100000);
    if (min != null && max != null && max <= min) {
      e['data.poids_max_g'] = 'Le poids maximal doit dépasser le poids minimal (laissez vide pour « sans limite »).';
    }
    final bmin = _requis(_nombre(b['biomasse_min_pct'], e, 'data.biomasse_min_pct', 0, 100), e, 'data.biomasse_min_pct');
    final bmax = _requis(_nombre(b['biomasse_max_pct'], e, 'data.biomasse_max_pct', 0, 100), e, 'data.biomasse_max_pct');
    if (bmin != null && bmax != null && bmax < bmin) {
      e['data.biomasse_max_pct'] = 'Le % de biomasse maximal ne peut pas être inférieur au minimal.';
    }
    final granule = _t(b['granule']);
    if (granule != null && granule.length > 30) e['data.granule'] = 'La taille du granulé ne peut pas dépasser 30 caractères.';
    return {
      'poids_min_g': min,
      'poids_max_g': max,
      'biomasse_min_pct': bmin,
      'biomasse_max_pct': bmax,
      'granule': granule,
      'proteine_pct': _nombre(b['proteine_pct'], e, 'data.proteine_pct', 0, 100),
    };
  }

  static Map<String, dynamic> _temperaturePoisson(Map<String, dynamic> b, Map<String, String> e) {
    final min = _requis(_nombre(b['optimale_min'], e, 'data.optimale_min', 0, 45), e, 'data.optimale_min');
    final max = _requis(_nombre(b['optimale_max'], e, 'data.optimale_max', 0, 45), e, 'data.optimale_max');
    if (min != null && max != null && max < min) {
      e['data.optimale_max'] = 'La température optimale maximale ne peut pas être inférieure à la minimale.';
    }
    final sous = _requis(_nombre(b['reduire_sous'], e, 'data.reduire_sous', 0, 45), e, 'data.reduire_sous');
    if (min != null && sous != null && sous > min) {
      e['data.reduire_sous'] = "Le seuil de réduction de la ration ne peut pas dépasser la température optimale minimale.";
    }
    return {'optimale_min': min, 'optimale_max': max, 'reduire_sous': sous};
  }

  /// Règle en vigueur du délai fournisseur, à partir de la ligne de règle et des propositions « 5 bons » par
  /// fournisseur (`ReleveTerrainService::regleEnVigueur`) : `constate` seulement si la règle est VALIDÉE, en mode
  /// « le plus long des 5 » et qu'au moins un fournisseur a 5 bons ; `manuel` si validée en valeurs saisies ;
  /// `depart` sinon (3 j / 7 j tant que rien n'est validé).
  static RegleDelai regleEnVigueur({String? statut, Map<String, dynamic>? data, required List<int> propositions}) {
    final d = data ?? const {};
    var critique = (d['critique_jours'] as num?)?.toInt() ?? critiqueDepart;
    var alerte = (d['alerte_jours'] as num?)?.toInt() ?? alerteDepart;
    final marge = (d['marge_jours'] as num?)?.toInt() ?? margeDefaut;
    final mode = d['mode'] ?? 'constate';
    var source = 'depart';
    if (statut == valide) {
      if (mode == 'manuel') {
        source = 'manuel';
      } else if (propositions.isNotEmpty) {
        critique = propositions.reduce((a, b) => a > b ? a : b);
        alerte = critique + marge;
        source = 'constate';
      }
    }
    return RegleDelai(critique: critique, alerte: alerte, source: source, marge: marge, statut: statut);
  }
}

class CalculsLot {
  const CalculsLot({this.dureeJours, this.tauxFertilite, this.tauxEclosion});

  final int? dureeJours;
  final double? tauxFertilite;
  final double? tauxEclosion;
}

class RegleDelai {
  const RegleDelai({required this.critique, required this.alerte, required this.source, required this.marge, this.statut});

  final int critique;
  final int alerte;

  /// `constate` · `manuel` · `depart`.
  final String source;
  final int marge;
  final String? statut;
}

/// Résultat d'une validation : valeurs normalisées OU erreurs (clés `label`, `species_code`, `data.x`).
class ResultatReleve {
  const ResultatReleve.ok({required String this.label, this.especeCode, required Map<String, dynamic> this.data}) : erreurs = const {};

  const ResultatReleve.refus(this.erreurs) : label = null, especeCode = null, data = null;

  final String? label;
  final String? especeCode;
  final Map<String, dynamic>? data;
  final Map<String, String> erreurs;

  bool get valide => erreurs.isEmpty;
}
