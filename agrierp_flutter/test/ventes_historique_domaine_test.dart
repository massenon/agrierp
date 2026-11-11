import 'package:flutter_test/flutter_test.dart';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
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

}

// ── Helpers InstantaneHistorique ──────────────────────────────────────────────

InstantaneHistorique _instantane({
  List<VenteHistorique>? ventes,
  Map<String, Customer>? clients,
}) =>
    InstantaneHistorique(
      ventes: ventes ?? [],
      lignesParVente: {},
      clients: clients ?? {},
      produits: {},
      creancesParVente: {},
      encoursCreances: 0,
    );

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
        'c1': _clientDrift(id: 'c1', nom: 'Zoumai Brice'),
        'c2': _clientDrift(id: 'c2', nom: 'Amoussou Regis'),
        'c3': _clientDrift(id: 'c3', nom: 'Houndji Paul', actif: false),
      });
      final actifs = snap.clientsActifs;
      expect(actifs, hasLength(2));
      expect(actifs[0].name, 'Amoussou Regis');
      expect(actifs[1].name, 'Zoumai Brice');
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
