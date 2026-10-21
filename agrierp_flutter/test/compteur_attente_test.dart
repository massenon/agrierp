import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket H2 — LE COMPTEUR « EN ATTENTE » COUVRE EXACTEMENT LES TABLES ENVOYÉES.
///
/// 🔴 Le compteur était une liste tenue à la main, complétée table par table (F0.35, F0.45, F0.48, F0.78…) :
/// huit tables envoyées y manquaient (produits, fournisseurs, clients, règlements, avances, imputations, retours,
/// remboursements). Un client créé hors ligne affichait « 0 en attente », et la confirmation de fermeture laissait
/// quitter sans prévenir.
///
/// ⚠️ CE TEST LIT LE SOURCE de `SyncEngine._pousser` (comme `conformite_portage_test`) : c'est le seul moyen de
/// garantir que la PROCHAINE table rendue envoyable ne sera pas oubliée du compteur — l'oubli ne lève aucune
/// erreur, seul le chiffre est faux.
void main() {
  test('tablesEnvoyees == tables lues en `pending` par _pousser', () {
    final source = File('lib/core/sync/sync_engine.dart').readAsStringSync();
    final debut = source.indexOf('Future<(int, int, List<String>)> _pousser()');
    final fin = source.indexOf('_financiersAcquittes = 0;', debut);
    expect(debut, greaterThan(0));
    expect(fin, greaterThan(debut));
    final corps = source.substring(debut, fin);

    final lues = RegExp(r'_db\.select\(\s*_db\.(\w+),?\s*\)')
        .allMatches(corps)
        .map((m) => m.group(1)!)
        .map((camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (l) => '_${l.group(0)!.toLowerCase()}'))
        .toSet();

    // Ticket H8b (19/10/2026) : + `infirmary_records` et `veterinary_calendar_events`, saisies au poste (D-H8).
    // Ticket H9b (19/10/2026) : + les cinq tables des Paramètres Élevage (rations, prophylaxie, provendes,
    // numérotation, entreprise pour le délai du rappel des soins), modifiables au poste (D-H9).
    // Tickets AV1 / AV2 (21/10/2026) : + `credit_notes` et `quotes` (ticket DEV), demandes de retour client et « marquer comme traité ».
    expect(lues, hasLength(31), reason: 'trente et une tables envoyées (BS1 : les bandes ; BS3 : les reproducteurs ; AV1 : les avoirs ; DEV : les devis) : $lues');
    expect(AppDatabase.tablesEnvoyees.toSet(), lues);
  });
}
