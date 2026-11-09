import 'dart:convert';

import 'package:agrierp/core/mecef/facture_mecef.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// MECEF-2 — PARITÉ EXÉCUTÉE de la facture normalisée : le VRAI `MecefFactureBuilder` + `ChargeBoitierEltrade` du serveur (base
/// SQLite en mémoire, migrations réelles) et leur transposition Dart (`FactureMecef`) reçoivent les MÊMES ventes et doivent rendre
/// la MÊME charge (en ligne ET boîtier) ou le MÊME refus (message mot pour mot). Rien n'est recopié : les cas sont une donnée
/// JSON jouée des deux côtés. Sans PHP ni dépôt Laravel, les tests sont SAUTÉS AVEC LEUR RAISON.
///
/// Décision B0 (option A) : la charge se construit AU POSTE — c'est ce test qui garantit qu'elle est celle du serveur.
const _script = r'''<?php
use App\Models\{CompanySetting, Customer, Product, ProductCategory, Sale, SaleLine, CreditNote};
use App\Services\Mecef\{MecefFactureBuilder, ChargeBoitierEltrade};
use App\Exceptions\MecefFactureInvalideException;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
$cat = ProductCategory::create(['label' => 'Test', 'is_active' => true]);
$emetteur = ['ifu' => '3202601234567', 'operateur_id' => '7', 'operateur_nom' => 'Caissière Test'];
$n = 0;
$sortie = [];
foreach ($in as $c) {
    $n++;
    CompanySetting::current()->update(['tva_enabled' => $c['tva_active']]);
    App\Services\TvaSettingService::oublier();
    $client = $c['nom_client'] !== null ? Customer::firstOrCreate(['name' => $c['nom_client']], ['is_active' => true]) : null;
    $vente = Sale::create([
        'customer_id' => $client?->id, 'payment_mode' => $c['mode'], 'subtotal' => $c['sous_total'], 'discount' => $c['remise'],
        'total' => $c['total'], 'delivery_fee' => $c['frais'], 'delivery_in_total' => $c['livraison'], 'status' => 'validee',
        'facture_type' => 'normalisee', 'client_nom_facture' => $c['nom_facture'], 'client_ifu' => $c['ifu'], 'aib_taux' => $c['aib'],
        'mecef_uid' => 'UID-ORIGINE',
    ]);
    $produits = [];
    foreach ($c['lignes'] as $i => $l) {
        $p = Product::create(['sku' => "P$n-$i", 'name' => $l['nom'], 'category_id' => $cat->id, 'unit' => $l['unite'], 'pricing_mode' => 'fourchette',
            'price_min' => 1, 'price_max' => 999999, 'tva_rate' => $l['taux'], 'stock_qty' => 100, 'is_active' => true]);
        $produits[] = $p;
        SaleLine::create(['sale_id' => $vente->id, 'product_id' => $p->id, 'qty' => $l['qte'], 'unit_price' => $l['qte'] > 0 ? $l['montant'] / $l['qte'] : 0,
            'manual_total_amount' => $l['montant'], 'is_manual_price' => true]);
    }
    $vente = $vente->fresh('lines');
    try {
        if ($c['avoir'] !== null) {
            $a = $c['avoir'];
            $p = Product::create(['sku' => "A$n", 'name' => $a['nom'], 'category_id' => $cat->id, 'unit' => $a['unite'], 'pricing_mode' => 'fourchette',
                'price_min' => 1, 'price_max' => 999999, 'tva_rate' => $a['taux'], 'stock_qty' => 100, 'is_active' => true]);
            $note = CreditNote::create(['credit_note_number' => "AV-$n", 'sale_id' => $vente->id, 'product_id' => $p->id, 'qty' => $a['qte'], 'amount' => $a['montant'], 'reason' => 'x', 'decision' => 'reintegre', 'status' => 'traite']);
            $enLigne = (new MecefFactureBuilder)->pourAvoir($note->fresh(), $emetteur);
        } else {
            $enLigne = (new MecefFactureBuilder)->pourVente($vente, $emetteur);
        }
        $boitier = (new ChargeBoitierEltrade)->depuisChargeEnLigne($enLigne, 'V1', $c['vendeur']);
        $sortie[] = ['ok' => true, 'en_ligne' => $enLigne, 'boitier' => $boitier];
    } catch (MecefFactureInvalideException $e) {
        $sortie[] = ['ok' => false, 'motif' => $e->getMessage()];
    }
}
echo json_encode($sortie);
''';

Map<String, Object?> _cas({
  required List<Map<String, Object?>> lignes,
  required num total,
  num? sousTotal,
  num remise = 0,
  String mode = 'especes',
  bool livraison = false,
  num frais = 0,
  String? nomFacture = 'AMOUSSOU Régis',
  String? nomClient,
  String? ifu,
  String? aib,
  bool tvaActive = true,
  Map<String, Object?>? avoir,
  String vendeur = 'Caissière Test',
}) => {
  'lignes': lignes,
  'total': total,
  'sous_total': sousTotal ?? lignes.fold<num>(0, (s, l) => s + (l['montant'] as num)),
  'remise': remise,
  'mode': mode,
  'livraison': livraison,
  'frais': frais,
  'nom_facture': nomFacture,
  'nom_client': nomClient,
  'ifu': ifu,
  'aib': aib,
  'tva_active': tvaActive,
  'avoir': avoir,
  'vendeur': vendeur,
};

Map<String, Object?> _l(String nom, double qte, num montant, {double taux = 18, String unite = 'u'}) =>
    {'nom': nom, 'unite': unite, 'qte': qte, 'montant': montant, 'taux': taux};

VenteMecef _vente(Map<String, Object?> c) => VenteMecef(
  lignes: [
    for (final l in (c['lignes'] as List).cast<Map>())
      LigneMecef(nom: l['nom'] as String, unite: l['unite'] as String, quantite: (l['qte'] as num).toDouble(), montant: (l['montant'] as num).toDouble(), tauxProduit: (l['taux'] as num).toDouble()),
  ],
  remise: (c['remise'] as num).toDouble(),
  total: (c['total'] as num).toDouble(),
  modePaiement: c['mode'] as String,
  livraisonIncluse: c['livraison'] as bool,
  fraisLivraison: (c['frais'] as num).toDouble(),
  clientNomFacture: c['nom_facture'] as String?,
  nomClient: c['nom_client'] as String?,
  clientIfu: c['ifu'] as String?,
  aibTaux: c['aib'] as String?,
);

void main() {
  final saut = sautSansPhp();
  const emetteur = {'ifu': '3202601234567', 'operateur_id': '7', 'operateur_nom': 'Caissière Test'};

  final cas = <Map<String, Object?>>[
    _cas(lignes: [_l("Plaquette d'œufs", 2, 11800)], total: 11800),
    _cas(lignes: [_l('Œufs', 2.5, 7000), _l('Maïs', 10, 2000, taux: 0, unite: 'kg')], total: 8000, remise: 1000, mode: 'mobile_money', ifu: '8888888888888', aib: '5%'),
    // Quantité décimale qui ne divise pas le montant : quantité 1 et quantité réelle dans le libellé.
    _cas(lignes: [_l('Provende croissance', 2.5, 7001, unite: 'kg')], total: 7001),
    _cas(lignes: [_l('Provende', 0.75, 1000, unite: 'kg')], total: 1000),
    // Remise impaire répartie au plus fort reste sur trois lignes.
    _cas(lignes: [_l('A', 1, 3333), _l('B', 1, 3333), _l('C', 1, 3334)], total: 9998, remise: 2, aib: '1%'),
    _cas(lignes: [_l('A', 3, 9000), _l('B', 1, 1000, taux: 0)], total: 6000, remise: 4000),
    // Ligne entièrement remisée : rien à déclarer pour elle.
    _cas(lignes: [_l('A', 1, 1000), _l('B', 1, 5000)], total: 5000, remise: 1000),
    // Frais de livraison inclus : une ligne, quantité 1, taux de la ligne principale.
    _cas(lignes: [_l('Poulet', 2, 8000)], total: 9500, livraison: true, frais: 1500),
    _cas(lignes: [_l('Maïs', 5, 3000, taux: 0), _l('Œufs', 1, 2900)], total: 6400, livraison: true, frais: 500),
    // Écart d'arrondi (1 FCFA) absorbé par la plus grosse ligne ; trop grand : refus.
    _cas(lignes: [_l('A', 1, 1000), _l('B', 1, 3000)], total: 4001),
    _cas(lignes: [_l('A', 1, 1000), _l('B', 1, 3000)], total: 3999),
    _cas(lignes: [_l('A', 1, 1000), _l('B', 1, 3000)], total: 4010),
    // TVA : taux non pris en charge ; exploitation non assujettie (tout en A).
    _cas(lignes: [_l('Article spécial', 1, 1000, taux: 5.5)], total: 1000),
    _cas(lignes: [_l('Taxable', 1, 1180)], total: 1180, tvaActive: false),
    _cas(lignes: [_l('Taxable', 1, 1180, taux: 10)], total: 1180, tvaActive: false),
    // Client : nom de facture vide -> nom du client -> anonyme ; IFU vide = omis.
    _cas(lignes: [_l('A', 1, 1000)], total: 1000, nomFacture: '', nomClient: 'KPOGNON'),
    _cas(lignes: [_l('A', 1, 1000)], total: 1000, nomFacture: null),
    _cas(lignes: [_l('A', 1, 1000)], total: 1000, ifu: ''),
    _cas(lignes: [_l('A', 1, 1000)], total: 1000, aib: 'N/A'),
    // Modes de règlement : connus, crédit, avance, inconnu.
    for (final m in ['especes', 'mobile_money', 'virement', 'credit', 'avance']) _cas(lignes: [_l('A', 1, 1000)], total: 1000, mode: m),
    // Libellés longs (nom rogné, suffixe gardé), accents et caractères hors plan de base.
    _cas(lignes: [_l('Très long nom de produit ' * 4, 1, 1000)], total: 1000),
    _cas(lignes: [_l('Très long nom de produit ' * 4, 2.5, 7001, unite: 'kg')], total: 7001),
    _cas(lignes: [_l('Œufs de pintade élevés en plein air à Ikpinlè — catégorie extra 🥚🥚', 1, 1000)], total: 1000),
    // Vendeur long (30 caractères au plus).
    _cas(lignes: [_l('A', 1, 1000)], total: 1000, vendeur: 'Un vendeur au nom vraiment beaucoup trop long pour le boîtier'),
    // Montants décimaux : l'arrondi (moitié vers le haut) sur les lignes, la remise et le total.
    _cas(lignes: [_l('Demi', 1, 1000.5), _l('Bas', 1, 999.49)], total: 2000, remise: 0.5),
    _cas(lignes: [_l('Demi', 2, 2001.5)], total: 2002),
    _cas(lignes: [_l('Demi', 1, 1499.5, taux: 0)], total: 1499.5),
    // Refus : sans ligne, montant nul.
    _cas(lignes: [], total: 0),
    _cas(lignes: [_l('A', 1, 0)], total: 0),
    // Avoirs.
    _cas(lignes: [_l('Œufs', 2, 11800)], total: 11800, aib: '5%', ifu: '8888888888888', avoir: {'nom': 'Œufs', 'unite': 'u', 'qte': 1, 'montant': 5900, 'taux': 18}),
    _cas(lignes: [_l('Œufs', 2, 11800)], total: 11800, avoir: {'nom': 'Maïs', 'unite': 'kg', 'qte': 2.5, 'montant': 1251, 'taux': 0}),
    _cas(lignes: [_l('Œufs', 2, 11800)], total: 11800, avoir: {'nom': 'Œufs', 'unite': 'u', 'qte': 1, 'montant': 0, 'taux': 18}),
    _cas(lignes: [_l('Œufs', 2, 11800)], total: 11800, tvaActive: false, avoir: {'nom': 'Œufs', 'unite': 'u', 'qte': 1, 'montant': 5900, 'taux': 18}),
  ];

  Map<String, Object?> local(Map<String, Object?> c) {
    try {
      final vente = _vente(c);
      final Map<String, Object?> enLigne;
      final a = c['avoir'] as Map<String, Object?>?;
      final tva = c['tva_active'] as bool;
      if (a != null) {
        enLigne = FactureMecef.pourAvoir(
          AvoirMecef(nomProduit: a['nom'] as String, unite: a['unite'] as String, quantite: (a['qte'] as num).toDouble(), montant: (a['montant'] as num).toDouble(), tauxProduit: (a['taux'] as num).toDouble(), vente: vente),
          reference: 'UID-ORIGINE',
          emetteur: emetteur,
          tvaActive: tva,
        );
      } else {
        enLigne = FactureMecef.pourVente(vente, emetteur: emetteur, tvaActive: tva);
      }
      final boitier = FactureMecef.versBoitier(enLigne, vendeurId: 'V1', vendeurNom: c['vendeur'] as String);
      return {'ok': true, 'en_ligne': jsonDecode(jsonEncode(enLigne)), 'boitier': jsonDecode(jsonEncode(boitier))};
    } on FactureMecefInvalide catch (e) {
      return {'ok': false, 'motif': e.message};
    }
  }

  test('⚠️⚠️ même charge en ligne, même charge du boîtier, même refus (message) : le serveur et le poste', () {
    final attendu = (executerPhp(_script, cas, application: true) as List).cast<Map>();

    expect(attendu, hasLength(cas.length));
    expect(attendu.where((r) => r['ok'] == true).length, greaterThan(20), reason: 'le jeu doit produire de vraies factures');
    expect(attendu.where((r) => r['ok'] == false).length, greaterThanOrEqualTo(5), reason: "et de vrais refus");
    expect(attendu.any((r) => r['ok'] == true && (r['boitier'] as Map).containsKey('rt')), isTrue, reason: 'et des avoirs');

    for (var i = 0; i < cas.length; i++) {
      expect(local(cas[i]), equals(Map<String, Object?>.from(attendu[i])), reason: 'cas $i : ${jsonEncode(cas[i])}');
    }
  }, skip: saut);

  test('l\'arrondi est UN : la moitié vers le haut, jamais d\'entier ailleurs', () {
    expect(FactureMecef.arrondi(0.5), 1);
    expect(FactureMecef.arrondi(2.5), 3);
    expect(FactureMecef.arrondi(1499.4), 1499);
    expect(FactureMecef.arrondi(1499.5), 1500);
    expect(FactureMecef.arrondi(0), 0);
  });
}
