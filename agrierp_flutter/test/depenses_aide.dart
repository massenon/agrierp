import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:drift/drift.dart';

/// Ticket DEP4 — aide commune des tests de « Saisie des Dépenses » à plusieurs lignes : le plan de charge du décor et
/// la dépense à UNE ligne (la forme de l'ancienne dépense, pour les tests qui ne s'intéressent pas aux lignes).

/// Comptes de charge (classe 6) du décor : 601 « Achats de marchandises », 605 « Énergie », 614 « Transports »,
/// 628 « Autres charges » ; et un compte de classe 5 (531, caisse) qui ne doit JAMAIS être proposé à une ligne.
const compte601 = '60100000-0000-4000-8000-000000000601';
const compte602 = '60200000-0000-4000-8000-000000000602';
const compte605 = '60500000-0000-4000-8000-000000000605';
const compte614 = '61400000-0000-4000-8000-000000000614';
const compte628 = '62800000-0000-4000-8000-000000000628';
const compte531 = '53100000-0000-4000-8000-000000000531';

/// Ticket DEP6 — le CENTRE DE COÛT est obligatoire à la saisie : le centre « Général » du décor (id fixe), semé avec le plan.
const centreGeneral = 'ce000000-0000-4000-8000-000000000001';

/// Insère le plan de charge du décor et le centre de coût « Général » (idempotent).
Future<void> semerPlanDeCharge(AppDatabase db) async {
  await db
      .into(db.costCenters)
      .insert(
        CostCentersCompanion.insert(id: centreGeneral, label: 'Général', type: 'filiere'),
        mode: InsertMode.insertOrIgnore,
      );
  for (final (id, code, libelle, classe) in [
    (compte601, '601', 'Achats de marchandises', 6),
    (compte602, '602', 'Produits vétérinaires', 6),
    (compte605, '605', 'Énergie', 6),
    (compte614, '614', 'Transports', 6),
    (compte628, '628', 'Autres charges', 6),
    (compte531, '531', 'Caisse', 5),
  ]) {
    await db
        .into(db.chartOfAccounts)
        .insert(
          ChartOfAccountsCompanion.insert(id: id, code: code, label: libelle, accountClass: Value(classe)),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

extension DepenseAUneLigne on DepensesRepository {
  /// Une dépense à UNE ligne : l'ancienne forme (un libellé, un compte, un montant), écrite par le même chemin que la
  /// modale (`enregistrer`, une seule transaction).
  Future<Expense> enregistrerUneLigne({
    required DateTime date,
    required String libelle,
    required num montant,
    required String? compteTresorerieId,
    String compteChargeId = compte601,
    String modePaiement = 'caisse',
    String? centreCoutId = centreGeneral,
    String? idEnModification,
  }) => enregistrer(
    date: date,
    modePaiement: modePaiement,
    compteTresorerieId: compteTresorerieId,
    centreCoutId: centreCoutId,
    lignes: [LigneSaisie(libelle: libelle, compteChargeId: compteChargeId, montant: montant.round().toString())],
    idEnModification: idEnModification,
  );
}
