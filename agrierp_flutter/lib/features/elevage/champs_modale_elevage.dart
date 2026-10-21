import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';

/// Les champs des modales « Nouvelle Bande », « Modifier la Bande », « Nouveau Sujet » et « Modifier le Sujet » : le
/// gabarit de saisie des Blades `gestion-bandes` et `enregistrer-sujets`, UNE seule fois.
///
/// ```html
/// <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Espèce *</label>
/// <select class="w-full h-11 px-md border rounded-lg text-sm bg-white is-invalid|border-outline-variant">
/// @error('species_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
/// <p class="text-[10px] text-outline mt-xs">Aide…</p>
/// ```
///
/// `is-invalid` : bordure `#BA1A1A` et fond `#FFF5F5` ; `invalid-feedback` : 11 px `#BA1A1A`, `mt-[2px]`.
class BlocChampModale extends StatelessWidget {
  const BlocChampModale({
    super.key,
    required this.libelle,
    required this.enfant,
    this.cleErreur,
    this.erreur,
    this.aide,
  });

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  final String libelle;
  final Widget enfant;

  /// Clé du texte d'erreur (`@error` du Blade), pour les tests.
  final Key? cleErreur;
  final String? erreur;

  /// `<p class="text-[10px] text-outline mt-xs">`.
  final String? aide;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
          child: Text(
            libelle.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
          ),
        ),
        enfant,
        if (aide != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(aide!, style: const TextStyle(fontSize: 10, color: AgriColors.outline)),
          ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(erreur!, key: cleErreur, style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep)),
          ),
      ],
    ),
  );
}

/// Cadre `h-11 px-md border rounded-lg text-sm`, rouge et teinté si le champ est en erreur (`is-invalid`).
BoxDecoration cadreChampModale({bool enErreur = false, bool grise = false}) => BoxDecoration(
  color: enErreur
      ? const Color(0xFFFFF5F5)
      : grise
      ? AgriColors.surfaceZebra
      : AgriColors.surfaceCard,
  border: Border.all(color: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant),
  borderRadius: BorderRadius.circular(AgriRadius.lg),
);

/// `<input type="text|number">` : 44 px, `text-sm`.
class ChampTexteModale extends StatelessWidget {
  const ChampTexteModale({
    super.key,
    required this.controleur,
    this.indice,
    this.nombre = false,
    this.enErreur = false,
    this.surChangement,
  });

  final TextEditingController controleur;

  /// `placeholder="ex : LOT-LAP-7"`.
  final String? indice;
  final bool nombre;
  final bool enErreur;
  final ValueChanged<String>? surChangement;

  @override
  Widget build(BuildContext context) {
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: BorderSide(color: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant),
    );
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controleur,
        onChanged: surChangement,
        keyboardType: nombre ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: AgriTypography.sm),
        decoration: InputDecoration(
          hintText: indice,
          hintStyle: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline),
          isDense: true,
          filled: true,
          fillColor: enErreur ? const Color(0xFFFFF5F5) : AgriColors.surfaceCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: 10),
          border: bord,
          enabledBorder: bord,
          focusedBorder: bord,
        ),
      ),
    );
  }
}

/// `<input disabled>` : valeur grisée (`bg-surface-zebra text-outline`).
class ChampLectureModale extends StatelessWidget {
  const ChampLectureModale({super.key, required this.valeur});

  final String valeur;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: cadreChampModale(grise: true),
    child: Text(valeur, style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline)),
  );
}

/// `<select>` : 44 px, `text-sm`, fond blanc ; [options] = (valeur, libellé) ; [vide] = libellé de l'option vide
/// (`-- Sélectionner --`), absente quand `null`.
class ChampListeModale extends StatelessWidget {
  const ChampListeModale({
    super.key,
    required this.valeur,
    required this.options,
    required this.surChangement,
    this.vide,
    this.enErreur = false,
    this.desactive = false,
  });

  final String valeur;
  final List<(String, String)> options;
  final ValueChanged<String> surChangement;
  final String? vide;
  final bool enErreur;
  final bool desactive;

  @override
  Widget build(BuildContext context) {
    final valeurs = {if (vide != null) '', for (final (v, _) in options) v};
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
      decoration: cadreChampModale(enErreur: enErreur),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: valeurs.contains(valeur) ? valeur : (vide != null ? '' : null),
          icon: const Icon(SymbolesAgri.expand_more, size: 20, color: AgriColors.outline),
          style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
          items: [
            if (vide != null) DropdownMenuItem(value: '', child: Text(vide!, overflow: TextOverflow.ellipsis)),
            for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: desactive ? null : (v) => surChangement(v ?? ''),
        ),
      ),
    );
  }
}
