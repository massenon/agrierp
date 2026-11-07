// Garde-fou — le hub « Comptabilité » reprend la cible du client (07/11/2026) : NEUF cartes, dans cet ordre, titre et
// description exacts, lus dans le Blade du web (maître) ET comparés à la liste ci-dessous ; mêmes textes au poste.
import 'dart:io';

import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

const _cible = <(String, String)>[
  ('Plan Comptable', 'Comptes SYSCOHADA (Classes 1 à 7)'),
  ('Journal Comptable', 'Écritures Débit/Crédit, saisie manuelle'),
  ('Grand Livre', 'Écritures par compte, solde progressif'),
  ('Balance Générale', 'Soldes de tous les comptes utilisés'),
  ('États Financiers', 'Bilan, Résultat, Flux de Trésorerie, Notes Annexes'),
  ('Clôture Périodique & Annuelle', "Clôture mensuelle, bascule d'exercice, report à nouveau"),
  ('Comptabilité Analytique', 'Marges réelles par filière (Cuniculture, Aviculture, Porciculture)'),
  ('Déclaration TVA', 'TVA Collectée / Déductible, taux 18% ou exonéré'),
  ('Rapprochement Bancaire', 'Pointage Grand Livre / Relevé Banque et Mobile Money'),
];

void main() {
  test('le poste porte les neuf cartes du client : titre et description, dans l ordre', () {
    expect(
      [for (final p in PageComptable.cartesDuClient) (p.libelle, p.description)],
      _cible,
    );
  });

  test('le Blade du web (maître) porte les mêmes neuf cartes, dans le même ordre', () {
    final blade = File(
      '$dossierLaravel/resources/views/livewire/comptabilite/comptabilite-hub.blade.php',
    );
    if (!blade.existsSync()) {
      markTestSkipped('Dépôt Laravel introuvable (AGRIERP_LARAVEL).');
      return;
    }
    final trouvees = RegExp(
      r'<p class="text-sm font-bold text-brand-forest">(.*?)</p>\s*<p class="text-\[11px\] text-outline">(.*?)</p>',
      dotAll: true,
    ).allMatches(blade.readAsStringSync()).map((m) => (m.group(1)!.replaceAll('&amp;', '&'), m.group(2)!.replaceAll('&amp;', '&'))).toList();

    expect(trouvees.take(9).toList(), _cible);
  });
}
