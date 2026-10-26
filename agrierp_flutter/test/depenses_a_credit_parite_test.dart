import 'dart:io';

import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fidelite_libelles_test.dart' show chainesDe;
import 'php_laravel.dart';

/// Tickets DEP6 et DEP7 — PARITÉ Blade ↔ Dart de la modale « Nouvelle Dépense » : libellés, ordre des champs, messages et
/// constantes lus dans le web (`saisie-depenses.blade.php`, `SaisieDepenseAction`, `Expense`), jamais recopiés ici.
void main() {
  String? lire(String relatif) {
    final f = File('$dossierLaravel/$relatif');
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  final blade = lire('resources/views/livewire/achats/saisie-depenses.blade.php');
  final action = lire('app/Actions/SaisieDepenseAction.php');
  final modele = lire('app/Models/Expense.php');
  final composant = lire('app/Livewire/Achats/SaisieDepenses.php');
  final saut = blade == null || action == null || modele == null || composant == null
      ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
      : null;
  final poste = [
    'lib/features/achats/saisie_depenses_screen.dart',
    'lib/features/achats/modale_depense.dart',
    'lib/features/achats/depenses_repository.dart',
  ].map((f) => chainesDe(File(f).readAsStringSync())).join('\n');

  test('⚠️ DEP6 — « Centre de Coût * » : astérisque, « -- Sélectionner -- », et le message du web mot pour mot', () {
    expect(blade!, contains('>Centre de Coût *</label>'));
    final centre = blade.substring(blade.indexOf('wire:model="costCenterId"'), blade.indexOf('@error(\'costCenterId\')'));
    expect(centre, contains('-- Sélectionner --'));
    expect(centre, isNot(contains('-- Aucun --')));
    expect(RegExp("const MESSAGE_CENTRE_OBLIGATOIRE = '([^']+)';").firstMatch(action!)![1], DepensesRepository.messageCentreObligatoire);
    expect(poste, contains('Centre de Coût *'));
  }, skip: saut);

  test('⚠️ DEP7 — « Règlement * » : libellés des options, messages et aide identiques au web', () {
    final reglements = {
      for (final m in RegExp(r"'(\w+)' => '([^']+)',").allMatches(modele!.substring(modele.indexOf('REGLEMENTS'), modele.indexOf('REGLEMENTS') + 250)))
        m[1]!: m[2]!,
    };
    expect(DepensesRepository.reglements, reglements);
    expect(blade!, contains('>Règlement *</label>'));
    for (final nom in ['MESSAGE_CREDIT_SANS_FOURNISSEUR', 'MESSAGE_CREDIT_SANS_PIECE']) {
      expect(RegExp("const $nom = '([^']+)';").firstMatch(action!)![1], switch (nom) {
        'MESSAGE_CREDIT_SANS_FOURNISSEUR' => DepensesRepository.messageCreditSansFournisseur,
        _ => DepensesRepository.messageCreditSansPiece,
      });
    }
    final aide = RegExp(r'data-aide-credit>([^<]+)</p>').firstMatch(blade)![1]!.replaceAll('&#039;', "'").trim();
    expect(poste, contains(aide));
    expect(composant!, contains("'Dépense archivée — dette fournisseur annulée et charge annulée.'"));
    expect(DepensesRepository.toastArchiveeACredit, 'Dépense archivée — dette fournisseur annulée et charge annulée.');
  }, skip: saut);

  test('l\'ordre des champs de la modale : Date, Mode, Compte, Centre *, Fournisseur, Règlement *, Bénéficiaire', () {
    final dans = ['Date de la Transaction *', 'Mode de Paiement *', 'Compte de Trésorerie Débité *', 'Centre de Coût *', 'Fournisseur', 'Règlement *', 'Bénéficiaire'];
    final web = [for (final t in dans) blade!.indexOf('>$t</label>')];
    expect(web.every((p) => p >= 0), isTrue, reason: '$web');
    expect(web, [...web]..sort());
    final modale = File('lib/features/achats/modale_depense.dart').readAsStringSync();
    final entete = modale.substring(modale.indexOf('final entete = <Widget>['));
    final dart = [for (final f in ['_champDate()', '_champMode()', '_champCompte()', '_champCentre()', '_champFournisseur()', '_champReglement()', '_champBeneficiaire()']) entete.indexOf(f)];
    expect(dart.every((p) => p >= 0), isTrue, reason: '$dart');
    expect(dart, [...dart]..sort());
    // À crédit, ni mode ni compte (`@unless($this->aCredit)`).
    expect(blade!, contains(r'@unless($this->aCredit)'));
    expect(entete, contains('if (!_aCredit) ...[_champMode(), _champCompte()]'));
  }, skip: saut);

  test('⚠️ le tableau et le détail : « À crédit » en colonne Mode, « Règlement : … » avant « Saisie par »', () {
    expect(blade!, contains("\$expense->on_credit ? 'À crédit'"));
    final ecran = File('lib/features/achats/saisie_depenses_screen.dart').readAsStringSync();
    expect(ecran, contains("d.onCredit ? 'À crédit'"));
    final ordre = [for (final t in ['· Bénéficiaire :', '· Règlement :', '· Saisie par :']) blade.indexOf(t)];
    expect(ordre, [...ordre]..sort());
    expect(ordre.every((p) => p >= 0), isTrue);
    final detail = ecran.substring(ecran.indexOf('Widget _detail('));
    final dart = [for (final t in ['· Bénéficiaire :', '· Règlement :', '· Saisie par :']) detail.indexOf(t)];
    expect(dart, [...dart]..sort());
    expect(dart.every((p) => p >= 0), isTrue);
  }, skip: saut);

  test('⚠️ parité EXÉCUTÉE — `Expense::libelleReglement` du serveur = `DepensesRepository.libelleReglement`', () {
    final sortie = executerPhp(
      '<?php\n$amorceApplication\n\$o = []; foreach ([[false,"payee"],[true,"en_attente"],[true,"payee"],[false,"en_attente"]] as [\$c,\$s]) { \$o[(\$c?"1":"0")."|".\$s] = App\\Models\\Expense::libelleReglement(\$c, \$s); } echo json_encode(\$o);',
      <String>[],
      application: true,
    ) as Map<String, dynamic>;
    for (final (credit, statut) in [(false, 'payee'), (true, 'en_attente'), (true, 'payee'), (false, 'en_attente')]) {
      expect(DepensesRepository.libelleReglement(aCredit: credit, statut: statut), sortie['${credit ? 1 : 0}|$statut']);
    }
  }, skip: sautSansPhp());
}
