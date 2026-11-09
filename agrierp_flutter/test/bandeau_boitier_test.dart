import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/mecef/passerelle_boitier.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/features/ventes/bandeau_boitier.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/transmission_boitier.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MECEF-2 — l'indicateur du boîtier (Paramètres > Facturation normalisée, caisse). ⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER.
class _Passerelle implements PasserelleBoitier {
  _Passerelle(this.etat);
  EtatBoitier etat;

  @override
  Future<EtatBoitier> verifier() async => etat;

  @override
  Future<InfoBoitier?> informations() async =>
      etat.pret ? const InfoBoitier(nim: 'ED04000623', ifu: '3201910768821', compteur: '12', compteurVentes: '7', brut: {}) : null;

  @override
  Future<ResultatFacturation> facturer(Map<String, Object?> charge) async => const BoitierInjoignable();
}

void main() {
  late AppDatabase db;
  late _Passerelle passerelle;
  late TransmissionBoitier service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    passerelle = _Passerelle(EtatBoitier.injoignable);
    service = TransmissionBoitier(caisse: CaisseRepository(database: db, deviceId: 'poste-test'), database: db, passerelle: passerelle);
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: 'mecef.mode', value: 'boitier'));
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: 'mecef.actif', value: '1'));
  });
  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester t, {bool compact = false}) async {
    await t.runAsync(() async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BandeauBoitier(service: service, compact: compact)))));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
  }

  testWidgets('boîtier injoignable : un état en français, SANS rouge ni fenêtre d alerte', (t) async {
    await afficher(t);

    final etat = t.widget<Text>(find.byKey(const Key('boitier-etat')));
    expect(etat.data, 'Boîtier injoignable');
    expect(etat.style?.color, isNot(AgriColors.errorRed));
    expect(etat.style?.color, isNot(AgriColors.errorDeep));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('boîtier prêt : « Boîtier prêt » puis les informations de l appareil au clic sur Vérifier', (t) async {
    passerelle.etat = const EtatBoitier(pret: true, message: 'Boîtier prêt');
    await afficher(t);
    expect(find.text('Boîtier prêt'), findsOneWidget);

    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('boitier-verifier')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();

    expect(find.textContaining('NIM ED04000623'), findsOneWidget);
  });

  testWidgets('la version de la caisse est compacte : pas de bouton de transmission', (t) async {
    await afficher(t, compact: true);
    expect(find.byKey(const Key('boitier-transmettre')), findsNothing);
    expect(find.byKey(const Key('boitier-etat')), findsOneWidget);
  });

  testWidgets('hors mode boîtier : rien n est affiché', (t) async {
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: 'mecef.mode', value: 'emecef'));
    await afficher(t);
    expect(find.byKey(const Key('bandeau-boitier')), findsNothing);
  });

  testWidgets('sans service (navigateur, poste sans boîtier) : rien n est affiché', (t) async {
    TransmissionBoitier.courant = null;
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BandeauBoitier())));
    expect(find.byKey(const Key('bandeau-boitier')), findsNothing);
  });
}
