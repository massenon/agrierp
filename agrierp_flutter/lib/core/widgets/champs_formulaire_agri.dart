import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket MP2 — LES CHAMPS DE FORMULAIRE DES MODALES, UNE SEULE FOIS.
///
/// Ces gabarits reprennent exactement le HTML du Blade pour les champs texte, liste et nombre
/// qui VOISINENT une date dans les modales (`h-11 px-md text-sm`, libellés `text-[10px] uppercase`).
/// Avant ce ticket, ces widgets vivaient dans `lib/features/elevage/champs_modale_elevage.dart`
/// (scope trop étroit) et les autres modales (Transferts, Grand Livre) utilisaient
/// `InputDecoration(labelText: …)` (style Material flottant, étranger au Blade).
///
/// ```html
/// <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Libellé *</label>
/// <input class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
/// @error('champ') <p class="invalid-feedback">{{ $message }}</p> @enderror
/// <p class="text-[10px] text-outline mt-xs">Aide…</p>
/// ```

/// Cadre `h-11 px-md border rounded-lg text-sm`, rouge et teinté si le champ est en erreur (`is-invalid`).
///
/// Anciennement `cadreChampModale` dans `champs_modale_elevage.dart`.
BoxDecoration cadreChampFormulaire({bool enErreur = false, bool grise = false}) => BoxDecoration(
  color: enErreur
      ? const Color(0xFFFFF5F5)
      : grise
      ? AgriColors.surfaceZebra
      : AgriColors.surfaceCard,
  border: Border.all(color: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant),
  borderRadius: BorderRadius.circular(AgriRadius.lg),
);

/// Bloc libellé + champ + erreur + aide.
///
/// Le libellé suit `block text-[10px] text-brand-forest font-bold uppercase mb-xs` ;
/// l'erreur suit `.invalid-feedback` (11 px, `#BA1A1A`, `mt-[2px]`).
class BlocChampFormulaire extends StatelessWidget {
  const BlocChampFormulaire({
    super.key,
    required this.libelle,
    required this.enfant,
    this.cleErreur,
    this.erreur,
    this.aide,
  });

  /// Sans majuscules ajoutées : `.toUpperCase()` est appliqué en interne.
  final String libelle;
  final Widget enfant;
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
            style: const TextStyle(
              fontSize: AgriChamps.etiquetteFormulaire,
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        enfant,
        if (aide != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(aide!, style: const TextStyle(fontSize: AgriChamps.etiquetteFormulaire, color: AgriColors.outline)),
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

/// `<input type="text|number">` : `h-11 px-md text-sm`.
class ChampTexteFormulaire extends StatelessWidget {
  const ChampTexteFormulaire({
    super.key,
    required this.controleur,
    this.indice,
    this.nombre = false,
    this.enErreur = false,
    this.surChangement,
  });

  final TextEditingController controleur;
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
      height: AgriChamps.hauteurFormulaire,
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

/// `<input disabled>` : valeur grisée (`bg-surface-zebra text-outline`), `h-11 px-md text-sm`.
class ChampLectureFormulaire extends StatelessWidget {
  const ChampLectureFormulaire({super.key, required this.valeur});

  final String valeur;

  @override
  Widget build(BuildContext context) => Container(
    height: AgriChamps.hauteurFormulaire,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: cadreChampFormulaire(grise: true),
    child: Text(valeur, style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline)),
  );
}

/// `<select>` : `h-11 px-md text-sm`, fond blanc.
///
/// [options] = (valeur, libellé) ; [vide] = libellé de l'option vide (`-- Sélectionner --`).
class ChampListeFormulaire extends StatelessWidget {
  const ChampListeFormulaire({
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
      height: AgriChamps.hauteurFormulaire,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
      decoration: cadreChampFormulaire(enErreur: enErreur),
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
