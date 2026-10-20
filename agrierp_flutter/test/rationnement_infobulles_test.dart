import 'dart:io';

import 'package:agrierp/features/elevage/fiche_categories_vue.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// 🔴→✅ Ticket U14 (relevé de la revue des écrans U11–U13) — tableau « Rationnement » des fiches Lapins et Porcs : au
/// web, l'effectif CALCULÉ de chaque ligne est un champ grisé (`<input disabled>`) avec son info-bulle « Calculé
/// automatiquement : … » ; le poste écrivait le nombre nu, sans l'explication. Les info-bulles sont LUES dans le Blade
/// (ligne par ligne, libellé de la catégorie → `title`) et comparées à la configuration de chaque fiche du poste.
void main() {
  Map<String, String> infobullesDuBlade(String vue) {
    final source = File('$dossierLaravel/resources/views/livewire/elevage/$vue.blade.php').readAsStringSync();
    return {
      for (final m in RegExp(
        r'<td class="px-md py-xs font-bold text-brand-forest">([^<]+)</td>\s*(?:\{\{--.*?--\}\}\s*)?'
        r'<td[^>]*><input id="cat-eff-[a-z]+"[^>]*title="([^"]+)"',
        dotAll: true,
      ).allMatches(source))
        m[1]!.trim(): m[2]!,
    };
  }

  Map<String, String> infobullesDuPoste(ConfigFicheCategories c) => {
    for (final MapEntry(:key, :value) in c.libellesRation.entries) value: c.infobullesRation[key]!,
  };

  final saut = File('$dossierLaravel/resources/views/livewire/elevage/fiche-lapins.blade.php').existsSync()
      ? null
      : 'SAUT : vues Blade absentes ($dossierLaravel)';

  test('U14 — Lapins : l info-bulle de chaque effectif calculé est celle du Blade', () {
    final web = infobullesDuBlade('fiche-lapins');
    expect(web, hasLength(3), reason: 'Reproducteur, Jeune, Sous-mères');
    expect(infobullesDuPoste(FicheLapinsScreen.config), web);
  }, skip: saut);

  test('U14 — Porcs : l info-bulle de chaque effectif calculé est celle du Blade', () {
    final web = infobullesDuBlade('fiche-porcs');
    expect(web, hasLength(3), reason: 'Porcelet, Porc Marchand, Reproducteur');
    expect(infobullesDuPoste(FichePorcsScreen.config), web);
  }, skip: saut);
}
