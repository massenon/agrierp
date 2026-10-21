import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket ENV1 — LA PASTILLE DE RECHERCHE GLOBALE du topbar, UN SEUL composant (champ actif de
/// `RechercheGlobaleChamp`, champ inerte de la barre sans source).
///
/// Transposition de `livewire/shared/global-search.blade.php` :
/// ```html
/// <div class="hidden md:flex items-center gap-xs bg-surface-zebra border border-outline-variant rounded-full
///             px-md py-xs w-64 focus-within:ring-2 focus-within:ring-brand-emerald">
///   <span class="material-symbols-outlined text-outline text-[16px]">search</span>
///   <input class="bg-transparent outline-none text-xs w-full placeholder:text-outline">
///   <button class="text-outline hover:text-error-deep"><span … text-[14px]>close</span></button>
/// ```
/// ⚠️⚠️ **LA HAUTEUR N'EST PAS UN CHIFFRE : ELLE SORT DES CLASSES.** Le poste dessinait 32 px « à l'œil » ; le web
/// en fait 44, parce que l'`<input>` n'a ni `border-0` ni `p-0` et garde la base de `@tailwindcss/forms`
/// (bordure 1 px `#6b7280`, `padding: .5rem .75rem`) à l'interligne `text-xs` (16 px). Le widget empile les MÊMES
/// termes (trait, `py-xs`, boîte du champ) et n'écrit aucune hauteur : `recherche_globale_mesure_test.dart` la
/// mesure et la recompte depuis le Blade et le CSS compilé.
///
/// ⚠️ ÉCART HÉRITÉ DU WEB, PAS INVENTÉ : la boîte intérieure du champ (trait gris carré dans la pastille ronde,
/// bleue au focus) est ce que le navigateur dessine. Si le client la trouve disgracieuse, la corriger D'ABORD au
/// web (`border-0 p-0 focus:ring-0` sur l'input), puis ici : la hauteur redeviendra celle de la pastille seule.
class CadreRechercheGlobale extends StatelessWidget {
  const CadreRechercheGlobale({
    super.key,
    required this.controleur,
    required this.focus,
    required this.indice,
    this.onChange,
    this.onEffacer,
    this.actif = true,
    this.cleSaisie = const Key('recherche-globale-saisie'),
  });

  final TextEditingController controleur;
  final FocusNode focus;
  final String indice;
  final ValueChanged<String>? onChange;

  /// Appelé après l'effacement du texte par le bouton `close`.
  final VoidCallback? onEffacer;

  /// `false` : champ inerte (aucune recherche branchée).
  final bool actif;
  final Key cleSaisie;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('recherche-globale'),
      width: AgriChamps.largeurRechercheGlobale,
      child: ListenableBuilder(
        listenable: focus,
        builder: (context, _) {
          final enFocus = focus.hasFocus;
          return DecoratedBox(
            key: const Key('recherche-globale-pastille'),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              borderRadius: BorderRadius.circular(AgriRadius.full),
              border: const Border.fromBorderSide(BorderSide(color: AgriColors.outlineVariant)),
              // `focus-within:ring-2` : une ombre pleine, qui ne prend pas de place.
              boxShadow: enFocus
                  ? const [BoxShadow(color: AgriColors.brandEmerald, spreadRadius: AgriChamps.anneauFocus)]
                  : null,
            ),
            child: Padding(
              // Trait de la pastille (`border`) + `px-md py-xs`.
              padding: const EdgeInsets.symmetric(
                horizontal: AgriChamps.bordure + AgriSpacing.md,
                vertical: AgriChamps.bordure + AgriSpacing.xs,
              ),
              child: Row(
                children: [
                  const Icon(SymbolesAgri.search, size: AgriChamps.iconeRecherche, color: AgriColors.outline),
                  const SizedBox(width: AgriSpacing.xs),
                  Expanded(child: _boite(enFocus)),
                  ListenableBuilder(
                    listenable: controleur,
                    builder: (context, _) => controleur.text.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: AgriSpacing.xs),
                            child: GestureDetector(
                              key: const Key('recherche-globale-effacer'),
                              onTap: () {
                                controleur.clear();
                                onEffacer?.call();
                              },
                              child: const Icon(
                                SymbolesAgri.close,
                                size: AgriChamps.iconeEffacerRecherche,
                                color: AgriColors.outline,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// L'`<input>` : `text-xs` (13,6 px, interligne 16), `bg-transparent`, base des formulaires autour.
  Widget _boite(bool enFocus) {
    return DecoratedBox(
      key: const Key('recherche-globale-boite'),
      decoration: BoxDecoration(
        border: Border.all(color: enFocus ? AgriColors.infoBlue : AgriChamps.bordureChampBrut),
      ),
      child: Padding(
        // Trait du champ (`border-width: 1px`) + `padding: .5rem .75rem` : une boîte CSS les additionne.
        padding: const EdgeInsets.symmetric(
          horizontal: AgriChamps.bordure + AgriChamps.rembourrageHorizontalChampBrut,
          vertical: AgriChamps.bordure + AgriChamps.rembourrageVerticalChampBrut,
        ),
        child: TextField(
          key: cleSaisie,
          controller: controleur,
          focusNode: focus,
          enabled: actif,
          onChanged: onChange,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            height: AgriTypography.xsInterligne / AgriTypography.xs,
          ),
          decoration: InputDecoration.collapsed(
            hintText: indice,
            hintStyle: const TextStyle(
              fontSize: AgriTypography.xs,
              height: AgriTypography.xsInterligne / AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ),
      ),
    );
  }
}
