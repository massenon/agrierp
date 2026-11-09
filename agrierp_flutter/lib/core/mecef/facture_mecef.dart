/// MECEF-2 — LA FACTURE NORMALISÉE AU POSTE : transposition en Dart de `App\Services\Mecef\MecefFactureBuilder` (vente `FV`,
/// avoir `FA`) ET de `App\Services\Mecef\ChargeBoitierEltrade` (traduction vers le schéma `bill.spec.json` du pilote Eltrade CC300).
///
/// DÉCISION B0 (client, 09/11/2026) : OPTION A — la charge se construit AU POSTE, pas au serveur, parce que le poste est hors
/// ligne d'abord : la facture doit sortir du boîtier même sans serveur. UN SEUL arrondi ([arrondi], la moitié vers le haut), des
/// prix ENTIERS, les mêmes libellés, groupes de taxe et AIB que le serveur. La règle n'est PAS recopiée « à peu près » : la
/// PARITÉ est EXÉCUTÉE contre le vrai PHP (`test/charge_boitier_parite_php_test.dart`).
///
/// ⚠️ Fonctions PURES : aucune base, aucun réseau, aucune horloge. Les refus portent le MÊME message français que le serveur
/// ([FactureMecefInvalide]).
library;

/// Une vente ou un avoir qui ne peut pas être exprimé en facture (taux de TVA inconnu, montant nul…) : message français,
/// celui de `MecefFactureInvalideException`.
class FactureMecefInvalide implements Exception {
  const FactureMecefInvalide(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Une ligne de vente telle que le constructeur la lit : montant = `manual_total_amount` (SOURCE DE VÉRITÉ), jamais `unit_price`.
class LigneMecef {
  const LigneMecef({required this.nom, required this.unite, required this.quantite, required this.montant, required this.tauxProduit});

  final String nom;
  final String unite;
  final double quantite;
  final double montant;

  /// Taux de TVA du produit (18, 0…), AVANT la règle « exploitation non assujettie ».
  final double tauxProduit;
}

/// Ce que le constructeur lit d'une vente (`sales` + `sale_lines` + produits + client).
class VenteMecef {
  const VenteMecef({
    required this.lignes,
    required this.remise,
    required this.total,
    required this.modePaiement,
    this.livraisonIncluse = false,
    this.fraisLivraison = 0,
    this.clientNomFacture,
    this.nomClient,
    this.clientIfu,
    this.aibTaux,
  });

  final List<LigneMecef> lignes;
  final double remise;
  final double total;
  final String modePaiement;
  final bool livraisonIncluse;
  final double fraisLivraison;
  final String? clientNomFacture;
  final String? nomClient;
  final String? clientIfu;
  final String? aibTaux;
}

/// Un avoir : le produit retourné, la quantité, le montant crédité ; le client et l'AIB sont ceux de la facture d'origine.
class AvoirMecef {
  const AvoirMecef({required this.nomProduit, required this.unite, required this.quantite, required this.montant, required this.tauxProduit, required this.vente});

  final String nomProduit;
  final String unite;
  final double quantite;
  final double montant;
  final double tauxProduit;

  /// La facture d'origine (client, IFU, AIB, mode de paiement).
  final VenteMecef vente;
}

class FactureMecef {
  const FactureMecef._();

  static const modesPaiement = {
    'especes': 'ESPECES',
    'mobile_money': 'MOBILEMONEY',
    'virement': 'VIREMENT',
    'credit': 'CREDIT',
    'avance': 'AUTRE',
  };

  static const groupesTaxe = {'0': 'A', '18': 'B'};

  static const nomMax = 60;

  static const libelleLivraison = 'Frais de livraison';

  /// Modes de paiement du boîtier : « V » virement, « C » carte, « M » mobile money, « D » chèque, « E » espèces, « A » autre.
  static const modesBoitier = {'ESPECES': 'E', 'MOBILEMONEY': 'M', 'VIREMENT': 'V', 'CARTE': 'C', 'CHEQUE': 'D', 'AUTRE': 'A'};

  /// Longueur maximale de `seller_name` dans le schéma du pilote.
  static const vendeurMax = 30;

  /// L'UNIQUE ARRONDI de montant : au FCFA le plus proche, la moitié vers le haut (PHP `round(…, 0, PHP_ROUND_HALF_UP)`).
  static int arrondi(num montant) {
    final x = montant.toDouble();
    return x >= 0 ? (x + 0.5).floor() : -((-x + 0.5).floor());
  }

  /// `TvaSettingService::tauxPour` : 0 si l'exploitation n'est pas assujettie.
  static double tauxPour(double tauxProduit, {required bool tvaActive}) => tvaActive ? tauxProduit : 0.0;

  /// `VatDeclarationService::tauxDeLaLivraison` : le taux (fraction) de la ligne de plus grand montant ; à égalité, le plus haut.
  static double tauxDeLaLivraison(List<LigneMecef> lignes, {required bool tvaActive}) {
    double? meilleur;
    var taux = 0.0;
    for (final l in lignes) {
      final ttc = l.montant;
      final t = tauxPour(l.tauxProduit, tvaActive: tvaActive) / 100;
      if (meilleur == null || ttc > meilleur || (ttc == meilleur && t > taux)) {
        meilleur = ttc;
        taux = t;
      }
    }
    return taux;
  }

  /// `MecefFactureBuilder::pourVente` — la charge « en ligne » (champs de l'API e-MECeF) d'une vente.
  static Map<String, Object?> pourVente(VenteMecef vente, {required Map<String, String> emetteur, required bool tvaActive}) {
    if (vente.lignes.isEmpty) {
      throw const FactureMecefInvalide('Facture sans ligne : rien à normaliser.');
    }

    final lignes = [
      for (final l in vente.lignes) (nom: l.nom, unite: l.unite, qte: l.quantite, montant: arrondi(l.montant), taux: l.tauxProduit),
    ];

    // 2. Remise : répartie au prorata, somme exacte.
    final montants = [for (final l in lignes) l.montant];
    final somme = montants.fold<int>(0, (a, b) => a + b);
    final remise = _min(_max(0, arrondi(vente.remise)), somme);
    final parts = _repartir(remise, montants);

    final nets = [for (var i = 0; i < lignes.length; i++) lignes[i].montant - parts[i]];

    // 3. Frais de livraison inclus dans la vente : une ligne, quantité 1.
    final livraison = vente.livraisonIncluse ? _max(0, arrondi(vente.fraisLivraison)) : 0;

    // 4. Écart d'arrondi entre le total de la vente et la somme des lignes.
    final cible = arrondi(vente.total);
    final sommeNets = nets.fold<int>(0, (a, b) => a + b);
    final ecart = cible - (sommeNets + livraison);

    if (ecart != 0) {
      if (ecart.abs() > lignes.length + (livraison > 0 ? 1 : 0)) {
        throw FactureMecefInvalide('Total de la vente ($cible FCFA) différent de la somme de ses lignes (${sommeNets + livraison} FCFA) : facture non transmise.');
      }
      final absorbante = _indexDuPlusGrand(nets);
      if (nets[absorbante] + ecart < 0) {
        throw const FactureMecefInvalide("Écart d'arrondi impossible à absorber : facture non transmise.");
      }
      nets[absorbante] += ecart;
    }

    final items = <Map<String, Object?>>[];
    for (var i = 0; i < lignes.length; i++) {
      if (nets[i] <= 0) continue; // ligne entièrement remisée : rien à déclarer (la DGI exige un prix > 0).
      final l = lignes[i];
      items.add(_ligne(l.nom, l.unite, l.qte, nets[i], l.taux, parts[i] > 0 ? l.montant : null, tvaActive: tvaActive));
    }

    if (livraison > 0) {
      // Même taux que l'écriture comptable et la Déclaration de TVA : un seul calcul (`tauxDeLaLivraison`).
      final tauxLivraison = _arrondiDecimales(tauxDeLaLivraison(vente.lignes, tvaActive: tvaActive) * 100, 2);
      items.add(_ligne(libelleLivraison, '', 1.0, livraison, tauxLivraison, null, tvaActive: tvaActive));
    }

    final total = nets.fold<int>(0, (a, b) => a + b) + livraison;

    if (total <= 0 || items.isEmpty) {
      throw const FactureMecefInvalide('Facture de montant nul : rien à normaliser.');
    }

    return _enveloppe('FV', emetteur, vente, items, total, null);
  }

  /// `MecefFactureBuilder::pourAvoir` — [reference] est la référence de la facture d'origine (côté boîtier : « NIM-TC »).
  static Map<String, Object?> pourAvoir(AvoirMecef avoir, {required String? reference, required Map<String, String> emetteur, required bool tvaActive}) {
    if (reference == null || reference.isEmpty) {
      throw const FactureMecefInvalide("Avoir sans facture d'origine normalisée : référence DGI absente.");
    }
    final montant = arrondi(avoir.montant);
    if (montant <= 0 || avoir.quantite <= 0) {
      throw const FactureMecefInvalide('Avoir de montant nul : rien à normaliser.');
    }
    final items = [_ligne(avoir.nomProduit, avoir.unite, avoir.quantite, montant, avoir.tauxProduit, null, tvaActive: tvaActive)];

    return _enveloppe('FA', emetteur, avoir.vente, items, montant, reference);
  }

  /// `ChargeBoitierEltrade::depuisChargeEnLigne` — renomme, ne recalcule RIEN : schéma `bill.spec.json` du pilote
  /// (`products` / `tax` / `payments` / `vt` ou `rt` + `rn` / `aib` = `"1%"` · `"5%"` · `"N/A"` / `seller_id` / `seller_name`).
  static Map<String, Object?> versBoitier(Map<String, Object?> enLigne, {required String vendeurId, required String vendeurNom}) {
    final charge = <String, Object?>{
      'vt': enLigne['type'],
      'seller_id': vendeurId,
      'seller_name': _sousChaine(vendeurNom, vendeurMax),
    };

    var resultat = charge;
    if (enLigne['type'] == 'FA') {
      charge.remove('vt');
      // `['rt' => 'FA', 'rn' => reference] + $charge` : `rt` et `rn` d'abord, puis le reste.
      resultat = {'rt': 'FA', 'rn': '${enLigne['reference'] ?? ''}', ...charge};
    }

    final client = (enLigne['client'] as Map?) ?? const {};
    final ifu = client['ifu'];
    if (ifu != null && '$ifu'.isNotEmpty && '$ifu' != '0') resultat['buyer_ifu'] = '$ifu';
    final nom = client['name'];
    if (nom != null && '$nom'.isNotEmpty && '$nom' != '0') resultat['buyer_name'] = '$nom';

    resultat['aib'] = switch (enLigne['aib']) {
      'B' => '5%',
      'A' => '1%',
      _ => 'N/A',
    };

    resultat['payments'] = [
      for (final p in (enLigne['payment'] as List).cast<Map>()) {'mode': modesBoitier[p['name']] ?? 'A', 'amount': p['amount']},
    ];

    resultat['products'] = [
      for (final i in (enLigne['items'] as List).cast<Map>())
        {
          'label': i['name'],
          'tax': i['taxGroup'],
          'price': i['price'],
          'items': i['quantity'],
          if (i['originalPrice'] != null) ...{
            'original_price': i['originalPrice'],
            'price_change_explanation': '${i['priceModification'] ?? 'Remise'}',
          },
        },
    ];

    return resultat;
  }

  // ── Pièces privées (mêmes noms qu'au serveur) ───────────────────────────────────────────────────────────────────────

  static int _min(int a, int b) => a < b ? a : b;

  static int _max(int a, int b) => a > b ? a : b;

  /// `round($x, $n)` de PHP (moitié vers le haut, en valeur absolue).
  static double _arrondiDecimales(double x, int n) {
    var f = 1.0;
    for (var i = 0; i < n; i++) {
      f *= 10;
    }
    final v = x * f;
    final r = v >= 0 ? (v + 0.5).floorToDouble() : -((-v + 0.5).floorToDouble());
    return r / f;
  }

  /// Répartit un montant ENTIER au prorata de poids entiers, méthode du plus fort reste (somme exacte, égalité tranchée par
  /// l'ordre des lignes).
  static List<int> _repartir(int montant, List<int> poids) {
    final somme = poids.fold<int>(0, (a, b) => a + b);
    final parts = List<int>.filled(poids.length, 0);
    if (montant <= 0 || somme <= 0) return parts;

    final restes = List<int>.filled(poids.length, 0);
    for (var i = 0; i < poids.length; i++) {
      parts[i] = (montant * poids[i]) ~/ somme;
      restes[i] = (montant * poids[i]) % somme;
    }
    final reliquat = montant - parts.fold<int>(0, (a, b) => a + b);
    final ordre = List<int>.generate(poids.length, (i) => i)
      ..sort((a, b) {
        final c = restes[b].compareTo(restes[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final i in ordre.take(reliquat)) {
      parts[i]++;
    }
    return parts;
  }

  static int _indexDuPlusGrand(List<int> nets) {
    int? meilleur;
    for (var i = 0; i < nets.length; i++) {
      if (meilleur == null || nets[i] > nets[meilleur]) meilleur = i;
    }
    return meilleur ?? 0;
  }

  /// `number_format($x, 2, '.', '')` puis `rtrim(rtrim(…, '0'), '.')`.
  static String _cleTaux(double taux) {
    var s = taux.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  static Map<String, Object?> _ligne(String nom, String unite, double qte, int net, double tauxProduit, int? montantAvantRemise, {required bool tvaActive}) {
    final taux = tauxPour(tauxProduit, tvaActive: tvaActive);
    final cle = _cleTaux(taux);
    final groupe = groupesTaxe[cle.isEmpty ? '0' : cle];

    if (groupe == null) {
      throw FactureMecefInvalide('Taux de TVA de ${cle.replaceAll('.', ',')} % non pris en charge par e-MECeF (article « $nom ») : seuls 0 % (exonéré) et 18 % le sont.');
    }

    // Quantité en millièmes (3 décimales au plus) : toute l'arithmétique qui suit est ENTIÈRE.
    final milliemes = (qte * 1000).round();
    if (milliemes <= 0) {
      throw FactureMecefInvalide("Quantité nulle pour l'article « $nom » : rien à normaliser.");
    }

    final int prix;
    final Object quantite;
    final int? original;
    final String suffixe;
    if ((net * 1000) % milliemes == 0) {
      // Prix unitaire ENTIER et prix × quantité = montant de la ligne.
      prix = (net * 1000) ~/ milliemes;
      quantite = milliemes % 1000 == 0 ? milliemes ~/ 1000 : milliemes / 1000;
      original = montantAvantRemise == null ? null : arrondi(montantAvantRemise * 1000 / milliemes);
      suffixe = '';
    } else {
      // La division ne tombe pas juste : quantité 1 au montant de la ligne, la quantité réelle est dans le libellé.
      prix = net;
      quantite = 1;
      original = montantAvantRemise;
      var reelle = (milliemes / 1000).toStringAsFixed(3).replaceAll('.', ',');
      reelle = reelle.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r',$'), '');
      suffixe = ' ($reelle${unite.isNotEmpty ? ' $unite' : ''})';
    }

    final ligne = <String, Object?>{'name': _tronquer(nom, suffixe), 'price': prix, 'quantity': quantite, 'taxGroup': groupe};
    if (original != null) {
      ligne['originalPrice'] = original;
      ligne['priceModification'] = 'Remise';
    }
    return ligne;
  }

  /// Sous-chaîne en CARACTÈRES (`mb_substr`), jamais en unités UTF-16.
  static String _sousChaine(String s, int longueur) {
    final c = s.runes.toList();
    return c.length <= longueur ? s : String.fromCharCodes(c.take(longueur));
  }

  static int _longueur(String s) => s.runes.length;

  /// Libellé = nom + suffixe, borné à [nomMax] caractères : c'est le NOM qu'on rogne, jamais le suffixe.
  static String _tronquer(String nom, String suffixe) {
    if (_longueur(suffixe) >= nomMax) return _sousChaine('$nom$suffixe', nomMax);
    return _sousChaine(nom, nomMax - _longueur(suffixe)) + suffixe;
  }

  static bool _vide(String? s) => s == null || s.isEmpty || s == '0';

  static Map<String, Object?> _enveloppe(String type, Map<String, String> emetteur, VenteMecef vente, List<Map<String, Object?>> items, int total, String? reference) {
    // `$sale->client_nom_facture ?: ($sale->customer?->name ?? 'Client Anonyme')`
    final nomClient = !_vide(vente.clientNomFacture) ? vente.clientNomFacture! : (vente.nomClient ?? 'Client Anonyme');
    final client = <String, Object?>{'name': nomClient};
    // IFU vide = client sans IFU (particulier) : le champ est omis.
    if (vente.clientIfu != null && vente.clientIfu!.isNotEmpty) client['ifu'] = vente.clientIfu;

    final charge = <String, Object?>{
      'ifu': emetteur['ifu'],
      'type': type,
      'client': client,
      'operator': {'id': emetteur['operateur_id'], 'name': emetteur['operateur_nom']},
      'items': items,
      'payment': [
        {'name': modesPaiement[vente.modePaiement] ?? 'AUTRE', 'amount': total},
      ],
    };

    final aib = switch (vente.aibTaux) {
      '5%' => 'B',
      '1%' => 'A',
      _ => null,
    };
    if (aib != null) charge['aib'] = aib;
    if (reference != null) charge['reference'] = reference;
    return charge;
  }
}
