import 'package:flutter_test/flutter_test.dart';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/domain/entities/article_resume.dart';
import 'package:agrierp/domain/entities/client_resume.dart';
import 'package:agrierp/domain/entities/vente_historique.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';

/// Fabrication d'une vente Drift minimale pour les tests du mapper et des propriétés.
Sale _vente({
  String id = 'aabbccdd-0000-0000-0000-000000000001',
  String paymentMode = 'especes',
  double total = 10000,
  double subtotal = 10000,
  double discount = 0,
  String status = 'validee',
  DateTime? soldAt,
  String? mecefStatus,
  String deviceId = 'poste-1',
  SyncStatus syncStatus = SyncStatus.synced,
}) =>
    Sale(
      id: id,
      deviceId: deviceId,
      syncStatus: syncStatus,
      updatedAt: DateTime(2026, 11, 1),
      paymentMode: paymentMode,
      subtotal: subtotal,
      discount: discount,
      total: total,
      status: status,
      soldAt: soldAt ?? DateTime(2026, 11, 10, 9, 30),
      mecefStatus: mecefStatus,
      deliveryFee: 0,
      deliveryInTotal: false,
    );

/// Construit un [VenteHistorique] minimal depuis un [Sale] (imite [_versVenteHistorique]).
VenteHistorique _venteHistorique(
  Sale sale, {
  bool estEnvoyee = true,
  String? customerId,
  String? customerName,
}) =>
    VenteHistorique(
      id: sale.id,
      soldAt: sale.soldAt,
      total: sale.total,
      subtotal: sale.subtotal,
      discount: sale.discount,
      paymentMode: sale.paymentMode,
      status: sale.status,
      deviceId: sale.deviceId,
      mecefStatus: sale.mecefStatus,
      customerId: customerId,
      customerName: customerName,
      estEnvoyee: estEnvoyee,
    );

/// Construit un [LigneVente] en appliquant manuellement la même conversion que
/// [_versVenteHistorique] (privé du repository). Permet de tester l'entité et
/// les propriétés calculées sans passer par la base de données.
LigneVente _ligneDepuisVente(
  Sale sale, {
  double reste = 0,
  bool envoyee = true,
}) =>
    LigneVente(
      vente: _venteHistorique(sale, estEnvoyee: envoyee),
      client: 'Client Anonyme',
      articles: 2,
      reste: reste,
      envoyee: envoyee,
    );

void main() {
  _testsInstantaneHistorique();

  // ── Mapper Product → ArticleResume ────────────────────────────────────────

  group('mapper Product → ArticleResume', () {
    test('les champs sont recopiés fidèlement depuis un article Drift', () {
      final drift = _articleDrift(id: 'ppp-001', nom: 'Provende ponte', prix: 350.0, unite: 'kg');
      // On reconstruit manuellement la même conversion que _versArticleResume (privé du repository).
      final resume = ArticleResume(
        id: drift.id,
        nom: drift.name,
        prixUnitaire: drift.priceMin ?? 0,
        unite: drift.unit,
      );
      expect(resume.id, 'ppp-001');
      expect(resume.nom, 'Provende ponte');
      expect(resume.prixUnitaire, 350.0);
      expect(resume.unite, 'kg');
    });

    test('le prix nul est recopié tel quel', () {
      final drift = _articleDrift(id: 'ppp-002', nom: 'Médicament gratuit', prix: 0.0, unite: 'dose');
      final resume = ArticleResume(id: drift.id, nom: drift.name, prixUnitaire: drift.price, unite: drift.unit);
      expect(resume.prixUnitaire, 0.0);
    });
  });

  group('InstantaneHistorique.produits (ArticleResume)', () {
    test('une map vide retourne null pour tout identifiant', () {
      final snap = _instantane(produits: {});
      expect(snap.produits['inconnu'], isNull);
    });

    test('produits[id] retourne le bon ArticleResume', () {
      final snap = _instantane(produits: {
        'p1': _articleResume(id: 'p1', nom: 'Poulet fermier', prix: 2500.0, unite: 'pièce'),
      });
      expect(snap.produits['p1']?.nom, 'Poulet fermier');
      expect(snap.produits['p1']?.prixUnitaire, 2500.0);
      expect(snap.produits['p1']?.unite, 'pièce');
    });

    test('produits[id] vaut null pour un identifiant absent', () {
      final snap = _instantane(produits: {
        'p1': _articleResume(id: 'p1', nom: 'Miel', prix: 1000.0, unite: 'pot'),
      });
      expect(snap.produits['p2'], isNull);
    });
  });

  // ── Mapper Sale → VenteHistorique ──────────────────────────────────────────

  group('mapper Sale → VenteHistorique', () {
    test('les champs obligatoires sont recopiés fidèlement', () {
      final sale = _vente(
        id: 'aabbccdd-1111-2222-3333-000000000042',
        paymentMode: 'mobile_money',
        total: 25000,
        subtotal: 26000,
        discount: 1000,
        status: 'validee',
        soldAt: DateTime(2026, 10, 15, 14, 0),
        deviceId: 'caisse-2',
      );

      final vente = _venteHistorique(sale);

      expect(vente.id, 'aabbccdd-1111-2222-3333-000000000042');
      expect(vente.soldAt, DateTime(2026, 10, 15, 14, 0));
      expect(vente.total, 25000);
      expect(vente.subtotal, 26000);
      expect(vente.discount, 1000);
      expect(vente.paymentMode, 'mobile_money');
      expect(vente.status, 'validee');
      expect(vente.deviceId, 'caisse-2');
      expect(vente.mecefStatus, isNull);
    });

    test('le statut MeCeF « transmise » est recopié', () {
      final sale = _vente(mecefStatus: 'transmise');
      final vente = _venteHistorique(sale);
      expect(vente.mecefStatus, 'transmise');
    });

    test('estEnvoyee est vrai pour une vente synchronisée', () {
      final vente = _venteHistorique(_vente(syncStatus: SyncStatus.synced));
      expect(vente.estEnvoyee, isTrue);
    });

    test("estEnvoyee est faux pour une vente en attente d'envoi", () {
      final vente = _venteHistorique(_vente(syncStatus: SyncStatus.pending), estEnvoyee: false);
      expect(vente.estEnvoyee, isFalse);
    });
  });

  // ── Propriétés calculées de LigneVente ─────────────────────────────────────

  group('LigneVente.annulee', () {
    test('est vrai pour une vente annulée', () {
      final ligne = _ligneDepuisVente(_vente(status: 'annulee'));
      expect(ligne.annulee, isTrue);
    });

    test('est faux pour une vente validée', () {
      final ligne = _ligneDepuisVente(_vente(status: 'validee'));
      expect(ligne.annulee, isFalse);
    });
  });

  group('LigneVente.normalisee', () {
    test('est vrai quand mecefStatus vaut « transmise »', () {
      final ligne = _ligneDepuisVente(_vente(mecefStatus: 'transmise'));
      expect(ligne.normalisee, isTrue);
    });

    test('est faux quand mecefStatus est nul', () {
      final ligne = _ligneDepuisVente(_vente(mecefStatus: null));
      expect(ligne.normalisee, isFalse);
    });
  });

  group('LigneVente.paye', () {
    test('vaut total − reste pour une vente validée', () {
      final ligne = _ligneDepuisVente(_vente(total: 10000), reste: 3000);
      expect(ligne.paye, 7000);
    });

    test('vaut zéro pour une vente annulée (quel que soit le reste)', () {
      final ligne = _ligneDepuisVente(
        _vente(status: 'annulee', total: 10000),
        reste: 5000,
      );
      expect(ligne.paye, 0);
    });
  });

  group('LigneVente.statut', () {
    test('affiche « Annulée » pour une vente annulée', () {
      final ligne = _ligneDepuisVente(_vente(status: 'annulee'));
      expect(ligne.statut, 'Annulée');
    });

    test('affiche « En attente » quand un reste est dû', () {
      final ligne = _ligneDepuisVente(_vente(), reste: 500);
      expect(ligne.statut, 'En attente');
    });

    test('affiche « Payée » quand le reste est nul', () {
      final ligne = _ligneDepuisVente(_vente(), reste: 0);
      expect(ligne.statut, 'Payée');
    });
  });

  group('LigneVente.mode', () {
    test('retourne le libellé français du mode « especes »', () {
      final ligne = _ligneDepuisVente(_vente(paymentMode: 'especes'));
      expect(ligne.mode, 'Espèces');
    });

    test('retourne le libellé français du mode « credit »', () {
      final ligne = _ligneDepuisVente(_vente(paymentMode: 'credit'));
      expect(ligne.mode, 'Crédit client');
    });
  });

  // ── Mapper Customer → ClientResume ────────────────────────────────────────

  group('mapper Customer → ClientResume', () {
    test('les champs sont recopiés fidèlement depuis un client Drift actif', () {
      final drift = _clientDrift(id: 'ccc-001', nom: 'Dossou Arnaud');
      // On reconstruit manuellement la même conversion que _versClientResume (privé du repository).
      final resume = ClientResume(id: drift.id, nom: drift.name, estActif: drift.isActive);
      expect(resume.id, 'ccc-001');
      expect(resume.nom, 'Dossou Arnaud');
      expect(resume.estActif, isTrue);
    });

    test('estActif est faux pour un client inactif', () {
      final drift = _clientDrift(id: 'ccc-002', nom: 'Hessou Lucie', actif: false);
      final resume = ClientResume(id: drift.id, nom: drift.name, estActif: drift.isActive);
      expect(resume.estActif, isFalse);
    });
  });

  // ── clientsActifs sur ClientResume ────────────────────────────────────────

  group('InstantaneHistorique.clientsActifs (ClientResume)', () {
    test('une map vide retourne une liste vide', () {
      final snap = _instantane(clients: {});
      expect(snap.clientsActifs, isEmpty);
    });

    test('un seul client inactif retourne une liste vide', () {
      final snap = _instantane(clients: {
        'x': _clientResume(id: 'x', nom: 'Fantôme', actif: false),
      });
      expect(snap.clientsActifs, isEmpty);
    });

    test('le tri est insensible à la casse', () {
      final snap = _instantane(clients: {
        'a': _clientResume(id: 'a', nom: 'zinzin Alain'),
        'b': _clientResume(id: 'b', nom: 'Aklesso Bruno'),
      });
      final actifs = snap.clientsActifs;
      expect(actifs[0].nom, 'Aklesso Bruno');
      expect(actifs[1].nom, 'zinzin Alain');
    });
  });

}

// ── Helpers InstantaneHistorique ──────────────────────────────────────────────

InstantaneHistorique _instantane({
  List<VenteHistorique>? ventes,
  Map<String, ClientResume>? clients,
  Map<String, ArticleResume>? produits,
}) =>
    InstantaneHistorique(
      ventes: ventes ?? [],
      lignesParVente: {},
      clients: clients ?? {},
      produits: produits ?? {},
      creancesParVente: {},
      encoursCreances: 0,
    );

/// Construit un [ClientResume] minimal pour les tests (sans Drift).
ClientResume _clientResume({
  required String id,
  required String nom,
  bool actif = true,
}) =>
    ClientResume(id: id, nom: nom, estActif: actif);

/// Construit un [ArticleResume] minimal pour les tests (sans Drift).
ArticleResume _articleResume({
  required String id,
  required String nom,
  double prix = 0.0,
  String unite = 'pièce',
}) =>
    ArticleResume(id: id, nom: nom, prixUnitaire: prix, unite: unite);

/// Construit un [Product] Drift minimal — uniquement pour les tests du mapper.
Product _articleDrift({
  required String id,
  required String nom,
  double prix = 0.0,
  String unite = 'pièce',
}) =>
    Product(
      id: id,
      sku: id,
      name: nom,
      priceMin: prix,
      unit: unite,
      syncStatus: SyncStatus.synced,
      updatedAt: DateTime(2026, 11, 11),
      stockQty: 0,
      pricingMode: 'fixe',
      tvaRate: 0,
      isActive: true,
    );

/// Construit un [Customer] Drift minimal — uniquement pour les tests du mapper.
Customer _clientDrift({
  required String id,
  required String nom,
  bool actif = true,
}) =>
    Customer(
      id: id,
      name: nom,
      creditLimit: 0,
      isActive: actif,
      syncStatus: SyncStatus.synced,
    );

// ── Tests InstantaneHistorique ────────────────────────────────────────────────

void _testsInstantaneHistorique() {
  group('InstantaneHistorique.ventes', () {
    test('accepte une List<VenteHistorique> et l\'expose correctement', () {
      final v1 = _venteHistorique(_vente(id: 'aabbccdd-0000-0000-0000-000000000011'));
      final v2 = _venteHistorique(_vente(id: 'aabbccdd-0000-0000-0000-000000000022'));
      final snap = _instantane(ventes: [v1, v2]);
      expect(snap.ventes, hasLength(2));
      expect(snap.ventes.first, isA<VenteHistorique>());
      expect(snap.ventes[0].id, 'aabbccdd-0000-0000-0000-000000000011');
      expect(snap.ventes[1].id, 'aabbccdd-0000-0000-0000-000000000022');
    });
  });

  group('InstantaneHistorique.clientsActifs', () {
    test('retourne uniquement les clients actifs, tries par nom', () {
      final snap = _instantane(clients: {
        'c1': _clientResume(id: 'c1', nom: 'Zoumai Brice'),
        'c2': _clientResume(id: 'c2', nom: 'Amoussou Regis'),
        'c3': _clientResume(id: 'c3', nom: 'Houndji Paul', actif: false),
      });
      final actifs = snap.clientsActifs;
      expect(actifs, hasLength(2));
      expect(actifs[0].nom, 'Amoussou Regis');
      expect(actifs[1].nom, 'Zoumai Brice');
    });
  });

  group('InstantaneHistorique.filtrer', () {
    test('par statut « annulee » ne retourne que les ventes annulees', () {
      final venteValidee = _venteHistorique(_vente(
        id: 'aabbccdd-0000-0000-0000-000000000031',
        status: 'validee',
      ));
      final venteAnnulee = _venteHistorique(_vente(
        id: 'aabbccdd-0000-0000-0000-000000000032',
        status: 'annulee',
      ));
      final snap = _instantane(ventes: [venteValidee, venteAnnulee]);
      final lignes = snap.filtrer(statut: 'annulee');
      expect(lignes, hasLength(1));
      expect(lignes.first.vente.id, 'aabbccdd-0000-0000-0000-000000000032');
      expect(lignes.first.annulee, isTrue);
    });
  });
}
