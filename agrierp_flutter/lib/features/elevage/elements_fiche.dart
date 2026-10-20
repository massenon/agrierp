import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/toast_agri.dart';
import 'gestion_elevage_screen.dart' show GestionElevageScreen;
import 'ration_volaille.dart';
import 'soins_repository.dart';

/// Ticket U12a — LES BLOCS COMMUNS DES VUES BLADE DES FICHES JOURNALIÈRES (Lapins, Porcs, Reproducteurs, Escargots),
/// transposés une fois pour les quatre écrans du poste : en-tête et « Exporter PDF », cartes `x-kpi-card`, carte
/// « aucune bande », carte de saisie et sa barre « Bande : » / « Date : », `x-transferts-du-jour`, étiquettes et
/// champs (`text-[10px] … uppercase`), compteurs ± des morts et des dons, bloc de l'effectif final, encadrés
/// d'avertissement, `x-module-pending`, `x-prophylaxie-du-jour`, bouton « Enregistrer ce Jour ».
///
/// ⚠️ Les classes Tailwind du Blade sont rendues par les jetons (`AgriColors`, `AgriSpacing`, `AgriTypography`) ;
/// seules les teintes « amber » de Tailwind (bloc de ponte / couvoir), absentes de `tailwind.config.js`, sont écrites
/// ici, comme dans la fiche Pondeuses.
abstract final class TeintesFiche {
  static const amber500 = Color(0xFFF59E0B);
  static const amber700 = Color(0xFFB45309);
  static const amber900 = Color(0xFF78350F);
}

/// En-tête du Blade : icône et titre (`text-xl lg:text-2xl font-bold`), sous-titre, « Exporter PDF » à droite (bord
/// fin, arrondi complet). [onExporter] `null` : bouton inerte (aucun éditeur injecté).
class EnTeteFiche extends StatelessWidget {
  const EnTeteFiche({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onExporter,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback? onExporter;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AgriSpacing.sm,
        spacing: AgriSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icone, color: AgriColors.brandEmerald, size: 26),
                  const SizedBox(width: AgriSpacing.xs),
                  Flexible(
                    child: Text(
                      titre,
                      key: const Key('titre-fiche'),
                      style: TextStyle(
                        fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                sousTitre,
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
              ),
            ],
          ),
          OutlinedButton.icon(
            key: const Key('fiche-exporter-pdf'),
            onPressed: onExporter,
            icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
            label: const Text(
              'Exporter PDF',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AgriColors.brandForest,
              backgroundColor: AgriColors.surfaceCard,
              side: const BorderSide(color: AgriColors.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une `x-kpi-card` : libellé, valeur, icône, variante de couleur (liseré, icône), légende (`caption`).
class CarteFiche {
  const CarteFiche(
    this.libelle,
    this.valeur,
    this.icone,
    this.lisere, {
    this.couleurIcone,
    this.legende,
  });

  final String libelle;
  final String valeur;
  final IconData icone;
  final Color lisere;
  final Color? couleurIcone;
  final String? legende;

  /// Variantes du composant web (`kpi-card.blade.php`).
  static const emerald = AgriColors.brandEmerald;
  static const blue = AgriColors.infoBlue;
  static const maize = AgriColors.accentYellow;
  static const red = AgriColors.errorRed;
}

/// `grid grid-cols-2 md:grid-cols-4 gap-md` des quatre cartes.
class CartesFiche extends StatelessWidget {
  const CartesFiche({super.key, required this.cartes});

  final List<CarteFiche> cartes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;
        final largeur = (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;
        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            for (final c in cartes)
              SizedBox(
                width: largeur,
                child: CarteKpi(
                  key: Key('kpi-${c.libelle}'),
                  libelle: c.libelle,
                  valeur: c.valeur,
                  icone: c.icone,
                  couleurLisere: c.lisere,
                  // `maize` : icône `text-brand-forest`, comme le composant web.
                  couleurIcone: c.couleurIcone ?? (c.lisere == CarteFiche.maize ? AgriColors.brandForest : c.lisere),
                  legende: c.legende,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Sans bande : la carte du Blade (`inbox`, message, lien vers « Bandes & Sujets », qui n'existe qu'au web).
class AucuneBandeFiche extends StatelessWidget {
  const AucuneBandeFiche({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aucune-bande'),
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        children: [
          const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
          const SizedBox(height: AgriSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.demiGras,
              color: AgriColors.onSurface,
            ),
          ),
          const SizedBox(height: AgriSpacing.sm),
          InkWell(
            key: const Key('lien-bandes'),
            // `route('elevage.bandes')` : l'écran n'existe qu'au web — le poste le dit, comme Gestion Élevage.
            onTap: () => ToastAgri.afficher(
              context,
              GestionElevageScreen.messageBandesWeb,
              type: TypeToast.avertissement,
            ),
            child: const Text(
              'Créer une bande depuis Bandes & Sujets →',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandEmerald,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La carte de saisie du Blade (`bg-white rounded-lg border shadow-sm p-md lg:p-lg`), ses blocs espacés de `space-y-md`.
class CarteSaisieFiche extends StatelessWidget {
  const CarteSaisieFiche({super.key, required this.enTete, required this.blocs});

  final Widget enTete;
  final List<Widget> blocs;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    return Container(
      padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          enTete,
          for (final b in blocs) ...[const SizedBox(height: AgriSpacing.md), b],
        ],
      ),
    );
  }
}

/// Titre de la carte de saisie (`edit_note`), puis à droite « Bande : » (s'il y a plusieurs bandes et [bandes] non
/// vide) et « Date : ». Le choix d'une date passe par le sélecteur du système, comme `<input type="date">`.
class EnTeteSaisieFiche extends StatelessWidget {
  const EnTeteSaisieFiche({
    super.key,
    required this.titre,
    required this.jour,
    required this.onJour,
    this.bandes = const [],
    this.bandeId,
    this.onBande,
  });

  final String titre;
  final DateTime jour;
  final ValueChanged<DateTime> onJour;

  /// `(identifiant, code)` des bandes ; le sélecteur n'apparaît qu'à partir de deux bandes, comme au web.
  final List<(String, String)> bandes;
  final String? bandeId;
  final ValueChanged<String>? onBande;

  static String dateLongue(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    Widget etiquette(String texte) => Text(
      texte,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: AgriTypography.demiGras,
        color: AgriColors.outline,
      ),
    );
    Widget cadre(String cle, Widget enfant) => Container(
      key: Key(cle),
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: enfant,
    );
    const style = TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandForest,
    );

    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AgriSpacing.xs,
        runSpacing: AgriSpacing.xs,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(SymbolesAgri.edit_note, color: AgriColors.brandEmerald),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                titre,
                style: const TextStyle(
                  fontSize: AgriTypography.base,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AgriSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (bandes.length > 1) ...[
                etiquette('Bande :'),
                cadre(
                  'bande-fiche',
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: bandeId,
                      isDense: true,
                      style: style,
                      items: [
                        for (final (id, code) in bandes) DropdownMenuItem(value: id, child: Text(code)),
                      ],
                      onChanged: (id) {
                        if (id != null) onBande?.call(id);
                      },
                    ),
                  ),
                ),
              ],
              etiquette('Date :'),
              cadre(
                'date-fiche',
                InkWell(
                  onTap: () async {
                    final choisie = await showDatePicker(
                      context: context,
                      initialDate: jour,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      locale: const Locale('fr'),
                    );
                    if (choisie != null) onJour(DateTime(choisie.year, choisie.month, choisie.day));
                  },
                  child: Text(dateLongue(jour), key: const Key('date-choisie'), style: style),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `components/transferts-du-jour.blade.php` (ticket 15.46) : rien les jours sans transfert.
class TransfertsDuJourFiche extends StatelessWidget {
  const TransfertsDuJourFiche({
    super.key,
    required this.entree,
    required this.sortie,
    this.onOuvrir,
  });

  final int entree;
  final int sortie;
  final VoidCallback? onOuvrir;

  @override
  Widget build(BuildContext context) {
    if (entree <= 0 && sortie <= 0) return const SizedBox.shrink();
    const gras = TextStyle(fontWeight: AgriTypography.gras);
    return Container(
      key: const Key('transferts-du-jour'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(SymbolesAgri.swap_horiz, size: 16, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Transferts entre bandes ce jour : '),
                  if (entree > 0) ...[
                    TextSpan(text: '+$entree', style: gras),
                    const TextSpan(text: ' entré(s)'),
                  ],
                  if (entree > 0 && sortie > 0) const TextSpan(text: ' ; '),
                  if (sortie > 0) ...[
                    TextSpan(text: '−$sortie', style: gras),
                    const TextSpan(text: ' sorti(s)'),
                  ],
                  const TextSpan(text: " — compris dans l'effectif final. Ils se modifient depuis l'écran "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      key: const Key('lien-transferts'),
                      onTap: onOuvrir,
                      child: const Text(
                        'Transferts entre Bandes',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                          decoration: TextDecoration.underline,
                          color: AgriColors.brandForest,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest),
            ),
          ),
        ],
      ),
    );
  }
}

/// Étiquette de champ du Blade : `text-[10px] text-brand-forest font-bold uppercase` ([petite] : `text-[9px]
/// text-outline`, centrée pour les compteurs), suivie d'une précision en petits caractères (« (POS, réel) »).
class EtiquetteFiche extends StatelessWidget {
  const EtiquetteFiche(
    this.libelle, {
    super.key,
    this.suffixe,
    this.petite = false,
    this.centree = false,
  });

  final String libelle;
  final String? suffixe;
  final bool petite;
  final bool centree;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: Wrap(
        alignment: centree ? WrapAlignment.center : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 3,
        children: [
          Text(
            libelle.toUpperCase(),
            textAlign: centree ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: petite ? 9 : 10,
              fontWeight: AgriTypography.gras,
              color: petite ? AgriColors.outline : AgriColors.brandForest,
            ),
          ),
          if (suffixe != null)
            Text(suffixe!, style: const TextStyle(fontSize: 9, color: AgriColors.outline)),
        ],
      ),
    );
  }
}

/// Champ numérique (`<input type="number" min="0" wire:model.live>`). Le texte suit [valeur] quand elle change
/// AILLEURS (jour rechargé, compteur ±), sans perdre la saisie en cours : le champ garde sa clé et son focus.
/// [decimal] : saisie à virgule (pesée en Kg des porcs). Vide = 0 (ou `null` avec [vide]).
class ChampNombreFiche extends StatefulWidget {
  const ChampNombreFiche({
    super.key,
    required this.valeur,
    required this.onChange,
    this.gras = false,
    this.couleur,
    this.hauteur = 40,
    this.centre = false,
    this.sansBord = false,
    this.indice,
    this.decimal = false,
  });

  final num? valeur;
  final ValueChanged<num?> onChange;
  final bool gras;
  final Color? couleur;
  final double hauteur;
  final bool centre;
  final bool sansBord;
  final String? indice;
  final bool decimal;

  @override
  State<ChampNombreFiche> createState() => _ChampNombreFicheState();
}

class _ChampNombreFicheState extends State<ChampNombreFiche> {
  late final _texte = TextEditingController(text: _ecrire(widget.valeur));

  static String _ecrire(num? v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return '${v.round()}';
    return '$v';
  }

  num? _lire(String t) {
    final propre = t.trim().replaceAll(',', '.');
    if (propre.isEmpty) return null;
    return widget.decimal ? double.tryParse(propre) : int.tryParse(propre);
  }

  @override
  void didUpdateWidget(ChampNombreFiche ancien) {
    super.didUpdateWidget(ancien);
    // Valeur changée hors de la frappe (jour rechargé, bouton ±) : le texte la suit.
    if (_lire(_texte.text) != widget.valeur && !(widget.valeur == 0 && _texte.text.trim().isEmpty)) {
      _texte.text = _ecrire(widget.valeur);
    }
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.hauteur,
      child: TextField(
        controller: _texte,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        textAlign: widget.centre ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: AgriTypography.sm,
          fontWeight: widget.gras ? AgriTypography.gras : AgriTypography.normal,
          color: widget.couleur ?? AgriColors.onSurface,
        ),
        decoration: InputDecoration(
          hintText: widget.indice,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: widget.sansBord ? InputBorder.none : const OutlineInputBorder(),
        ),
        onChanged: (t) {
          final v = _lire(t);
          // `min="0"` : un nombre négatif n'est pas pris.
          widget.onChange(v != null && v < 0 ? 0 : v);
        },
      ),
    );
  }
}

/// Champ libellé + saisie numérique (`h-10`), dans une colonne.
class ChampSaisieFiche extends StatelessWidget {
  const ChampSaisieFiche({
    super.key,
    required this.libelle,
    required this.cle,
    required this.valeur,
    required this.onChange,
    this.suffixe,
    this.gras = false,
    this.couleur,
    this.indice,
    this.petite = false,
    this.decimal = false,
  });

  final String libelle;
  final String? suffixe;
  final String cle;
  final num? valeur;
  final ValueChanged<num?> onChange;
  final bool gras;
  final Color? couleur;
  final String? indice;

  /// Étiquette `text-[9px] text-outline`, champ `h-9` (effectifs saisis).
  final bool petite;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetteFiche(libelle, suffixe: suffixe, petite: petite),
        ChampNombreFiche(
          key: Key('champ-$cle'),
          valeur: valeur,
          onChange: onChange,
          gras: gras,
          couleur: couleur,
          hauteur: petite ? 36 : 40,
          indice: indice,
          decimal: decimal,
        ),
      ],
    );
  }
}

/// Valeur calculée, en lecture seule (`bg-surface-zebra`) : « Ventes (POS, réel) », taux, poids moyen…
class ChampLectureFiche extends StatelessWidget {
  const ChampLectureFiche({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.cle,
    this.suffixe,
    this.couleur = AgriColors.outline,
    this.gras = false,
    this.petite = false,
  });

  final String libelle;
  final String? suffixe;
  final String valeur;
  final String cle;
  final Color couleur;
  final bool gras;
  final bool petite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetteFiche(libelle, suffixe: suffixe, petite: petite),
        Container(
          height: petite ? 36 : 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AgriColors.surfaceZebra,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            valeur,
            key: Key(cle),
            style: TextStyle(
              fontSize: AgriTypography.sm,
              color: couleur,
              fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Une rangée de champs de même largeur (`grid grid-cols-N gap-*`) ; [colonnes] > nombre d'enfants laisse des cases
/// vides, comme `sm:grid-cols-3` avec un seul champ.
class GrilleFiche extends StatelessWidget {
  const GrilleFiche({
    super.key,
    required this.enfants,
    this.colonnes,
    this.ecart = AgriSpacing.md,
  });

  final List<Widget> enfants;
  final int? colonnes;
  final double ecart;

  @override
  Widget build(BuildContext context) {
    final n = colonnes ?? enfants.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) SizedBox(width: ecart),
          Expanded(child: i < enfants.length ? enfants[i] : const SizedBox.shrink()),
        ],
      ],
    );
  }
}

/// Morts (ou dons) par catégorie : le bloc du Blade (titre, éventuelle mention des morts / dons déjà enregistrés sans
/// répartition, puis trois compteurs « − [champ] + », jamais sous zéro).
class BlocCategoriesFiche extends StatelessWidget {
  const BlocCategoriesFiche({
    super.key,
    required this.titre,
    required this.icone,
    required this.couleur,
    required this.fond,
    required this.bord,
    required this.categories,
    required this.valeurs,
    required this.onChange,
    required this.prefixeCle,
    this.mention,
    this.cleMention,
  });

  final String titre;
  final IconData icone;
  final Color couleur;
  final Color fond;
  final Color bord;

  /// `(clé, libellé)` dans l'ordre du Blade.
  final List<(String, String)> categories;
  final Map<String, int> valeurs;
  final void Function(String cle, int valeur) onChange;
  final String prefixeCle;
  final String? mention;
  final String? cleMention;

  /// Les blocs Morts et Dons du Blade.
  static BlocCategoriesFiche morts({
    required List<(String, String)> categories,
    required Map<String, int> valeurs,
    required void Function(String, int) onChange,
    int? dejaEnregistres,
  }) => BlocCategoriesFiche(
    titre: 'Morts par catégorie',
    icone: SymbolesAgri.skull,
    couleur: AgriColors.errorDeep,
    fond: AgriColors.errorBg.withValues(alpha: 0.3),
    bord: AgriColors.errorRed.withValues(alpha: 0.2),
    categories: categories,
    valeurs: valeurs,
    onChange: onChange,
    prefixeCle: 'mort',
    cleMention: 'morts-enregistres',
    mention: dejaEnregistres == null
        ? null
        : '$dejaEnregistres mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
              "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
  );

  static BlocCategoriesFiche dons({
    required List<(String, String)> categories,
    required Map<String, int> valeurs,
    required void Function(String, int) onChange,
    int? dejaEnregistres,
  }) => BlocCategoriesFiche(
    titre: 'Dons par catégorie',
    icone: SymbolesAgri.redeem,
    couleur: AgriColors.brandEmerald,
    fond: AgriColors.brandEmerald.withValues(alpha: 0.05),
    bord: AgriColors.brandEmerald.withValues(alpha: 0.2),
    categories: categories,
    valeurs: valeurs,
    onChange: onChange,
    prefixeCle: 'don',
    cleMention: 'dons-enregistres',
    mention: dejaEnregistres == null
        ? null
        : '$dejaEnregistres don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
              "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
  );

  @override
  Widget build(BuildContext context) {
    Widget pas(String cle, int delta, String signe) => InkWell(
      key: Key('pas-$prefixeCle-$cle-$delta'),
      // `max(0, … - 1)` du Blade : jamais en dessous de zéro.
      onTap: () => onChange(cle, ((valeurs[cle] ?? 0) + delta).clamp(0, 1 << 30)),
      child: Container(
        width: 32,
        height: 34,
        alignment: Alignment.center,
        color: AgriColors.surfaceZebra,
        child: Text(
          signe,
          style: const TextStyle(fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: couleur),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                titre.toUpperCase(),
                style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: couleur),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          if (mention != null) ...[
            Container(
              key: Key(cleMention ?? 'mention-$prefixeCle'),
              padding: const EdgeInsets.all(AgriSpacing.xs),
              decoration: BoxDecoration(
                color: AgriColors.accentYellow.withValues(alpha: 0.2),
                border: Border.all(color: AgriColors.accentYellow),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Text(mention!, style: const TextStyle(fontSize: 11, color: AgriColors.brandForest)),
            ),
            const SizedBox(height: AgriSpacing.xs),
          ],
          GrilleFiche(
            ecart: AgriSpacing.sm,
            enfants: [
              for (final (cle, libelle) in categories)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EtiquetteFiche(libelle, petite: true, centree: true),
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: AgriColors.surfaceCard,
                        border: Border.all(color: AgriColors.outlineVariant),
                        borderRadius: BorderRadius.circular(AgriRadius.lg),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          pas(cle, -1, '−'),
                          Expanded(
                            child: ChampNombreFiche(
                              key: Key('compteur-$prefixeCle-$cle'),
                              valeur: valeurs[cle] ?? 0,
                              onChange: (v) => onChange(cle, (v ?? 0).toInt()),
                              gras: true,
                              centre: true,
                              sansBord: true,
                              hauteur: 34,
                            ),
                          ),
                          pas(cle, 1, '+'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le bloc du Blade : fond zébré, deux colonnes (libellé, formule, valeur dans un encadré blanc) — effectif final et
/// taux de mortalité du jour.
class BlocEffectifFiche extends StatelessWidget {
  const BlocEffectifFiche({
    super.key,
    required this.titreEffectif,
    required this.formuleEffectif,
    required this.effectif,
    required this.tauxMortalite,
  });

  final String titreEffectif;
  final String formuleEffectif;
  final String effectif;
  final String tauxMortalite;

  @override
  Widget build(BuildContext context) {
    Widget colonne(String titre, String formule, String valeur, Color couleur, Key cle) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titre.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
        ),
        Text(formule, style: const TextStyle(fontSize: 10, color: AgriColors.outline)),
        const SizedBox(height: 4),
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          child: Text(
            valeur,
            key: cle,
            style: TextStyle(fontSize: AgriTypography.base, fontWeight: FontWeight.w900, color: couleur),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: GrilleFiche(
        enfants: [
          colonne(titreEffectif, formuleEffectif, effectif, AgriColors.brandEmerald, const Key('effectif-final')),
          colonne(
            'Taux de Mortalité du Jour (%)',
            '= (Morts du Jour ÷ Effectif J-1) × 100',
            tauxMortalite,
            AgriColors.errorDeep,
            const Key('taux-mortalite-jour'),
          ),
        ],
      ),
    );
  }
}

/// Encadré d'information du Blade : `avertissement` (`bg-accent-yellow/20 border-accent-yellow`), `erreur`
/// (`bg-error-bg border-error-deep/30 text-error-deep font-bold`, `role="alert"`).
class EncadreFiche extends StatelessWidget {
  const EncadreFiche(this.texte, {super.key, this.erreur = false});

  final String texte;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: erreur ? AgriColors.errorBg : AgriColors.accentYellow.withValues(alpha: 0.2),
        border: Border.all(
          color: erreur ? AgriColors.errorDeep.withValues(alpha: 0.3) : AgriColors.accentYellow,
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: erreur ? AgriTypography.gras : AgriTypography.normal,
          color: erreur ? AgriColors.errorDeep : AgriColors.brandForest,
        ),
      ),
    );
  }
}

/// Titre de section du Blade (`text-xs font-bold text-brand-forest uppercase` précédé d'une icône).
class TitreSectionFiche extends StatelessWidget {
  const TitreSectionFiche(
    this.titre, {
    super.key,
    required this.icone,
    this.couleurIcone = AgriColors.brandEmerald,
    this.couleur = AgriColors.brandForest,
    this.tailleIcone = 16,
  });

  final String titre;
  final IconData icone;
  final Color couleurIcone;
  final Color couleur;
  final double tailleIcone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: tailleIcone, color: couleurIcone),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            titre.toUpperCase(),
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: couleur),
          ),
        ),
      ],
    );
  }
}

/// `components/module-pending.blade.php` : sablier, « [label] sera alimenté en données réelles dès sa mise en
/// œuvre. », puis « Prévu : [since] ».
class ModuleEnAttenteFiche extends StatelessWidget {
  const ModuleEnAttenteFiche({super.key, required this.libelle, this.prevu});

  final String libelle;
  final String? prevu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.lg, horizontal: AgriSpacing.md),
      child: Column(
        children: [
          Icon(SymbolesAgri.hourglass_empty, size: 32, color: AgriColors.outline.withValues(alpha: 0.4)),
          const SizedBox(height: AgriSpacing.xs),
          Text(
            '$libelle sera alimenté en données réelles dès sa mise en œuvre.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.demiGras,
              color: AgriColors.outline,
            ),
          ),
          if (prevu != null) ...[
            const SizedBox(height: AgriSpacing.xs),
            Text(
              'Prévu : $prevu',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AgriColors.outline.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Champ « Observations » du Blade (texte libre, `h-10`, indice).
class ObservationsFiche extends StatelessWidget {
  const ObservationsFiche({
    super.key,
    required this.libelle,
    required this.indice,
    required this.controleur,
  });

  final String libelle;
  final String indice;
  final TextEditingController controleur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetteFiche(libelle),
        SizedBox(
          height: 40,
          child: TextField(
            key: const Key('champ-observations'),
            controller: controleur,
            style: const TextStyle(fontSize: AgriTypography.xs),
            decoration: InputDecoration(
              hintText: indice,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

/// `components/prophylaxie-du-jour.blade.php` (ticket 15.35) : jour de cycle, badge d'état, lignes à cocher,
/// entrées calendaires non évaluées, bouton de validation, « Indice Rouge ».
class ProphylaxieDuJourFiche extends StatelessWidget {
  const ProphylaxieDuJourFiche({
    super.key,
    required this.protocole,
    required this.coches,
    required this.onCocher,
    required this.onValider,
    required this.enCours,
  });

  final ProtocoleDuJour protocole;
  final Set<String> coches;
  final void Function(String idBareme, bool coche) onCocher;
  final VoidCallback onValider;
  final bool enCours;

  @override
  Widget build(BuildContext context) {
    final p = protocole;
    // `$protocole->etat()` et les classes du badge (`$badges`).
    final (etat, fondBadge, texteBadge, bordBadge) = !p.determinable
        ? ('Indéterminé', AgriColors.errorBg, AgriColors.errorDeep, AgriColors.errorDeep.withValues(alpha: 0.3))
        : p.traitements.isEmpty
        ? ('Libre', AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant)
        : p.enAttente == 0
        ? (
            'Validé / Effectué',
            AgriColors.brandEmerald.withValues(alpha: 0.2),
            AgriColors.brandEmerald,
            AgriColors.brandEmerald,
          )
        : (
            '${p.traitements.length} Prévu(s)',
            AgriColors.accentYellow.withValues(alpha: 0.3),
            AgriColors.brandForest,
            AgriColors.accentYellow,
          );

    return Container(
      key: const Key('prophylaxie-du-jour'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.05),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.determinable ? 'Jour ${p.jourDeCycle} du cycle de la bande' : 'Jour de cycle inconnu',
                  style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: fondBadge,
                  border: Border.all(color: bordBadge),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  etat,
                  key: const Key('etat-prophylaxie'),
                  style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: texteBadge),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!p.determinable)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(SymbolesAgri.help, size: 16, color: AgriColors.errorDeep),
                      const SizedBox(width: AgriSpacing.xs),
                      Expanded(
                        child: Text(
                          'Protocole non calculable — ${p.motifIndetermine ?? ''} Consultez le registre avant toute '
                          'administration.',
                          style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
                        ),
                      ),
                    ],
                  )
                else if (p.traitements.isEmpty)
                  const Text(
                    '— Aucun traitement récurrent programmé pour ce jour —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  )
                else
                  for (final t in p.traitements) _ligne(t),
              ],
            ),
          ),
          if (p.calendairesNonEvalues > 0) ...[
            const SizedBox(height: AgriSpacing.sm),
            Text(
              '${p.calendairesNonEvalues} entrée(s) du protocole sans jour de cycle (calendaires, ex. « Le 1er du '
              'mois ») ne sont pas évaluées ici.',
              style: const TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ],
          if (p.determinable && p.enAttente > 0) ...[
            const SizedBox(height: AgriSpacing.sm),
            const Text(
              "Valider un traitement rémanent bloque la vente de cette bande jusqu'à la fin du délai d'attente.",
              style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
            const SizedBox(height: AgriSpacing.xs),
            ElevatedButton.icon(
              key: const Key('bouton-valider-traitements'),
              onPressed: enCours ? null : onValider,
              icon: const Icon(SymbolesAgri.check_circle, size: 16),
              label: const Text(
                "Valider l'Administration de tous ces Traitements Aujourd'hui",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: AgriColors.surfaceCard,
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
              ),
            ),
          ],
          if (p.determinable && p.traitements.isNotEmpty) ...[
            const SizedBox(height: AgriSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: p.enAttente > 0 ? AgriColors.errorBg : AgriColors.brandEmerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  'Indice Rouge : ${p.enAttente} soin(s) en attente',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: AgriTypography.gras,
                    color: p.enAttente > 0 ? AgriColors.errorDeep : AgriColors.brandEmerald,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ligne(TraitementPrevu t) {
    final standard = t.standard;
    final details = [
      if ((standard.productRecommended ?? '').isNotEmpty) standard.productRecommended!,
      if ((standard.dosage ?? '').isNotEmpty) standard.dosage!,
    ].join(' — ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: Checkbox(
              key: Key('traitement-${standard.id}'),
              value: t.dejaAdministre || coches.contains(standard.id),
              onChanged: t.dejaAdministre ? null : (coche) => onCocher(standard.id, coche == true),
            ),
          ),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: standard.treatment,
                    style: TextStyle(
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                      decoration: t.dejaAdministre ? TextDecoration.lineThrough : TextDecoration.none,
                    ),
                  ),
                  if (details.isNotEmpty)
                    TextSpan(text: ' ($details)', style: const TextStyle(color: AgriColors.outline)),
                ],
              ),
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
          if (t.remanenceJours > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AgriColors.errorBg,
                borderRadius: BorderRadius.circular(AgriRadius.full),
              ),
              child: Text(
                'Rémanence ${t.remanenceJours}j',
                style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.errorDeep),
              ),
            ),
        ],
      ),
    );
  }
}

/// « Enregistrer ce Jour » (`save`), à droite, sous un filet.
class BoutonEnregistrerFiche extends StatelessWidget {
  const BoutonEnregistrerFiche({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AgriSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            key: const Key('bouton-enregistrer'),
            onPressed: onPressed,
            icon: const Icon(SymbolesAgri.save, size: 16),
            label: const Text(
              'Enregistrer ce Jour',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: AgriColors.surfaceCard,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section précédée d'un filet haut (`border-t border-outline-variant pt-md`).
class FiletFiche extends StatelessWidget {
  const FiletFiche({super.key, required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants),
    );
  }
}

/// Cellule d'un petit tableau de la fiche (rationnement).
class CelluleFiche extends StatelessWidget {
  const CelluleFiche(
    this.texte, {
    super.key,
    this.centre = false,
    this.droite = false,
    this.gras = false,
    this.taille = AgriTypography.xs,
    this.couleur = AgriColors.onSurface,
    this.cleTexte,
  });

  final String texte;
  final bool centre;
  final bool droite;
  final bool gras;
  final double taille;
  final Color couleur;

  /// Clé posée sur le `Text` lui-même (lu par les tests).
  final Key? cleTexte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
      child: Text(
        texte,
        key: cleTexte,
        textAlign: centre ? TextAlign.center : (droite ? TextAlign.right : TextAlign.start),
        style: TextStyle(
          fontSize: taille,
          fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
          color: couleur,
        ),
      ),
    );
  }
}

/// `components/ration-volaille.blade.php` (ticket 15.57) — le tableau du rationnement par stade des fiches avicoles,
/// « — » quand aucune ligne du barème ne correspond (jamais 0 g). [ligneCle] : « des reproducteurs », « du stade de
/// la bande (Pondeuse) »…
class RationVolailleFiche extends StatelessWidget {
  const RationVolailleFiche({super.key, required this.lignes, required this.ligneCle});

  final List<LigneRationVolaille> lignes;
  final String ligneCle;

  @override
  Widget build(BuildContext context) {
    const titre = TitreSectionFiche('Rationnement & Provende Servie par Stade (en Grammes g/j)', icone: SymbolesAgri.restaurant);
    if (lignes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titre,
          const SizedBox(height: AgriSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              "Aucune ration normative pour l'aviculture : renseignez le barème dans Paramètres Élevage > Rationnement.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titre,
        const SizedBox(height: AgriSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.8)},
            children: [
              const TableRow(
                decoration: BoxDecoration(
                  color: AgriColors.surfaceZebra,
                  border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                ),
                children: [
                  CelluleFiche("Stade / Tranche d'Âge", couleur: AgriColors.outline),
                  CelluleFiche('Effectif', centre: true, couleur: AgriColors.outline),
                  CelluleFiche('Ration Normative', centre: true, couleur: AgriColors.outline),
                  CelluleFiche('Provende Servie (g)', droite: true, couleur: AgriColors.outline),
                ],
              ),
              for (final l in lignes)
                TableRow(
                  children: [
                    CelluleFiche(l.libelle, gras: true, couleur: AgriColors.brandForest),
                    CelluleFiche(l.effectif == null ? '—' : '${l.effectif}', centre: true, gras: true),
                    CelluleFiche('${l.ration.round()} g/j', centre: true),
                    CelluleFiche(
                      l.totalG == null ? '—' : '${l.totalG!.round()} g',
                      droite: true,
                      gras: true,
                      couleur: AgriColors.brandEmerald,
                    ),
                  ],
                ),
              TableRow(
                decoration: BoxDecoration(color: AgriColors.brandEmerald.withValues(alpha: 0.10)),
                children: [
                  const CelluleFiche(
                    'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                    gras: true,
                    taille: 10,
                    couleur: AgriColors.brandForest,
                  ),
                  const CelluleFiche(''),
                  const CelluleFiche(''),
                  CelluleFiche(
                    RationVolaille.totalAffiche(RationVolaille.totalG(lignes)),
                    cleTexte: const Key('total-provende'),
                    droite: true,
                    gras: true,
                    taille: AgriTypography.sm,
                    couleur: AgriColors.brandEmerald,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        if (RationVolaille.rattachee(lignes))
          Text(
            "L'effectif n'est pas encore ventilé par stade : la fiche du jour n'en porte que le total. La ligne "
            '$ligneCle le reçoit entièrement.',
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          )
        else
          Text(
            'Aucune ligne du barème ne correspond $ligneCle : ajoutez-la dans Paramètres Élevage > Rationnement pour '
            'calculer la provende.',
            key: const Key('ration-non-rattachee'),
            style: const TextStyle(fontSize: 10, color: AgriColors.errorDeep),
          ),
      ],
    );
  }
}
