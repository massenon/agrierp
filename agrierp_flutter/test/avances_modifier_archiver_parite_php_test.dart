import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket VC-4 — PARITÉ EXÉCUTÉE : le VRAI `CustomerAdvanceService::modifier` / `archiver` du serveur (précédés des règles du
/// formulaire web `saveAdvance`, avec `lang/fr/validation.php`) et `ClientsCreancesRepository.modifierAvance` / `archiverAvance`
/// du poste reçoivent les mêmes gestes sur les mêmes avances et doivent refuser avec les MÊMES messages, sous les MÊMES champs.
///
/// Rien n'est recopié : un motif changé au web fait rougir ce test. Les cas s'enchaînent dans le même ordre des deux côtés (une
/// modification ou un archivage réussi change l'état de l'avance pour les cas suivants, de part et d'autre).
const _c1 = 'a1000000-0000-4000-8000-000000000001';
const _c2 = 'a1000000-0000-4000-8000-000000000002';
const _inconnu = 'ffffffff-0000-4000-8000-000000000000';
const _t1 = 'b1000000-0000-4000-8000-000000000001';

// Avances : comptabilisée (compte de trésorerie), ancienne (jamais comptabilisée), entamée, soldée, archivée.
const _compta = 'e1000000-0000-4000-8000-000000000001';
const _ancienne = 'e1000000-0000-4000-8000-000000000002';
const _entamee = 'e1000000-0000-4000-8000-000000000003';
const _soldee = 'e1000000-0000-4000-8000-000000000004';
const _archivee = 'e1000000-0000-4000-8000-000000000005';

const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Services\CustomerAdvanceService;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

foreach ($in['clients'] as $i => $id) {
    (new Customer())->forceFill(['id' => $id, 'name' => 'Client '.($i + 1), 'is_active' => true])->save();
}
(new App\Models\TreasuryAccount())->forceFill(['id' => $in['compte'], 'label' => 'Caisse', 'account_code' => '531', 'type' => 'caisse', 'balance' => 0, 'is_active' => true])->save();
foreach ($in['avances'] as $a) {
    (new CustomerAdvance())->forceFill([
        'id' => $a['id'], 'customer_id' => $in['clients'][0], 'treasury_account_id' => $a['compte'], 'amount' => $a['montant'],
        'amount_used' => $a['utilise'], 'advance_date' => '2026-10-01', 'is_active' => $a['active'],
    ])->save();
}

// Les règles de `HistoriqueAvances::saveAdvance` (modification).
$regles = [
    'customerId' => ['required', 'exists:customers,id'],
    'amount' => ['required', 'numeric', 'min:1'],
    'advanceDate' => ['required', 'date'],
];

$sortie = [];
foreach ($in['cas'] as $c) {
    $service = app(CustomerAdvanceService::class);
    try {
        if ($c['op'] === 'modifier') {
            $v = Validator::make(['customerId' => $c['client'], 'amount' => $c['montant'], 'advanceDate' => $c['date']], $regles);
            if ($v->fails()) {
                $sortie[] = (object) array_map(fn ($m) => $m[0], $v->errors()->toArray());
                continue;
            }
            $service->modifier(CustomerAdvance::findOrFail($c['avance']), $c['client'], (float) $c['montant'], $c['date']);
        } else {
            $service->archiver(CustomerAdvance::findOrFail($c['avance']));
        }
        $sortie[] = (object) [];
    } catch (ValidationException $e) {
        $sortie[] = (object) array_map(fn ($m) => $m[0], $e->errors());
    }
}
echo json_encode($sortie);
''';

Map<String, dynamic> _modifier(
  String nom,
  String avance, {
  String client = _c1,
  String montant = '40000',
  String? date = '2026-10-01',
}) => {'nom': nom, 'op': 'modifier', 'avance': avance, 'client': client, 'montant': montant, 'date': date};

Map<String, dynamic> _archiver(String nom, String avance) => {'nom': nom, 'op': 'archiver', 'avance': avance};

void main() {
  final saut = sautSansPhp();

  test('⚠️ chaque refus du poste est celui du web, mot pour mot, sous le même champ', () async {
    final cas = [
      _modifier('client vide', _compta, client: ''),
      _modifier('client inconnu', _compta, client: _inconnu),
      _modifier('montant vide', _compta, montant: ''),
      _modifier('montant nul', _compta, montant: '0'),
      _modifier('montant sous un franc', _compta, montant: '0.5'),
      _modifier('montant non numérique', _compta, montant: 'abc'),
      _modifier('date vide', _compta, date: null),
      _modifier('tout vide', _compta, client: '', montant: '', date: null),
      _modifier('comptabilisée : montant changé', _compta, montant: '50000'),
      _modifier('comptabilisée : client changé', _compta, client: _c2),
      _modifier('comptabilisée : date changée', _compta, date: '2026-10-02'),
      _modifier('comptabilisée : saisie identique', _compta),
      _modifier('entamée : montant changé', _entamee, montant: '30000'),
      _modifier('entamée : client changé', _entamee, client: _c2),
      _modifier('entamée : date changée (permise)', _entamee, date: '2026-10-03'),
      _modifier('ancienne : tout change', _ancienne, client: _c2, montant: '55000', date: '2026-10-04'),
      _modifier('archivée', _archivee, montant: '90000'),
      _archiver('archiver : comptabilisée avec un reste', _compta),
      _archiver('archiver : entamée avec un reste', _entamee),
      _archiver('archiver : ancienne avec un reste', _ancienne),
      _archiver('archiver : soldée', _soldee),
      _archiver('archiver : soldée, une seconde fois', _soldee),
    ];

    final web = (executerPhp(
      _script,
      {
        'clients': [_c1, _c2],
        'compte': _t1,
        'avances': [
          {'id': _compta, 'compte': _t1, 'montant': 40000, 'utilise': 0, 'active': true},
          {'id': _ancienne, 'compte': null, 'montant': 40000, 'utilise': 0, 'active': true},
          {'id': _entamee, 'compte': null, 'montant': 40000, 'utilise': 10000, 'active': true},
          {'id': _soldee, 'compte': null, 'montant': 40000, 'utilise': 40000, 'active': true},
          {'id': _archivee, 'compte': null, 'montant': 40000, 'utilise': 40000, 'active': false},
        ],
        'cas': cas,
      },
      application: true,
    ) as List)
        .map((e) => (e as Map).cast<String, String>())
        .toList();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final (id, nom) in [(_c1, 'Client 1'), (_c2, 'Client 2')]) {
      await db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: nom, isActive: const Value(true)));
    }
    for (final (id, compte, utilise, active) in [
      (_compta, _t1, 0.0, true),
      (_ancienne, null, 0.0, true),
      (_entamee, null, 10000.0, true),
      (_soldee, null, 40000.0, true),
      (_archivee, null, 40000.0, false),
    ]) {
      await db.into(db.customerAdvances).insert(
        CustomerAdvancesCompanion.insert(
          id: id,
          customerId: _c1,
          amount: 40000,
          amountUsed: Value(utilise),
          advanceDate: Value(DateTime(2026, 10, 1)),
          isActive: Value(active),
          treasuryAccountId: Value(compte),
        ),
      );
    }
    final depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');

    final ecarts = <String>[];
    for (var i = 0; i < cas.length; i++) {
      final c = cas[i];
      Map<String, String> poste;
      try {
        if (c['op'] == 'modifier') {
          await depot.modifierAvance(
            c['avance'] as String,
            clientId: c['client'] as String,
            montant: c['montant'] as String,
            date: c['date'] == null ? null : DateTime.parse(c['date'] as String),
          );
        } else {
          await depot.archiverAvance(c['avance'] as String);
        }
        poste = {};
      } on SaisieAvanceRefusee catch (e) {
        poste = e.erreurs;
      }
      if (poste.toString() != web[i].toString()) ecarts.add('${c['nom']} : poste $poste, web ${web[i]}');
    }
    expect(ecarts, isEmpty);
  }, skip: saut);
}
