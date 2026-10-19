import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/toast_agri.dart';
import 'gestion_elevage_repository.dart';

/// Une carte de navigation du hub (`components/nav-card.blade.php`) : icône, titre, description, écran ouvert.
///
/// [ecran] `null` : la cible du web n'existe pas au poste (« Bandes & Sujets »).
typedef CarteHub = (IconData icone, String titre, String description, EcranPoste? ecran);

/// Ticket H4 — « Gestion Élevage », aligné sur le Blade (maître).
///
/// Web : `app/Livewire/Elevage/GestionElevage.php` + `resources/views/livewire/elevage/gestion-elevage.blade.php`,
/// avec `components/kpi-card.blade.php` et `components/nav-card.blade.php`. Ordre du Blade : titre et sous-titre,
/// 4 KPI, « Registres par Espèce » (6 cartes), « Accès Rapides — Élevage & Soins » (4 cartes).
///
/// 🔴 Avant : écran porté de la maquette — aucun KPI ni intertitre, une seule colonne, titres et descriptions de la
/// maquette, « Fiches Escargots » MASQUÉ quand l'héliciculture est éteinte (le web la GRISE), « Bandes & Sujets » et
/// trois accès rapides absents. Garde-fou : `test/gestion_elevage_blade_test.dart` lit les libellés DANS LE BLADE.
///
/// ⚠️ Les quatre fiches Lapins, Pondeuses, Volailles et Porcs sont TOUJOURS affichées : le Blade ne conditionne que
/// l'héliciculture (`@if($this->helicoEnabled)`), et la carte grisée garde son lien.
class GestionElevageScreen extends StatefulWidget {
  const GestionElevageScreen({
    super.key,
    required this.onOuvrir,
    required this.depot,
  });

  /// Rappel de navigation vers un autre écran du poste (le `href` des cartes du web).
  final void Function(EcranPoste) onOuvrir;

  final GestionElevageRepository depot;

  /// « Bandes & Sujets » (`/gestion-bandes`) n'a pas d'écran au poste : la carte reste, son clic le dit.
  static const messageBandesWeb =
      "La gestion des bandes (création, numérotation individuelle) se fait sur l'application web.";

  /// Description de la carte Escargots grisée — branche `@else` du Blade.
  static const descriptionEscargotsDesactive = 'Héliciculture — module désactivé';

  /// « Registres par Espèce », dans l'ordre du Blade. La description de « Bandes & Sujets » est précédée du nombre de
  /// bandes actives (`$this->bandesActives.' bande(s) …'`).
  static const registres = <CarteHub>[
    (Icons.layers, 'Bandes & Sujets', ' bande(s) active(s) — création, numérotation individuelle', null),
    (Icons.cruelty_free, 'Fiches Lapins', 'Suivi mensuel du cheptel — Cuniculture', EcranPoste.ficheElevage),
    (Icons.egg, 'Fiches Pondeuses', "Suivi quotidien de la ponte et récolte d'œufs", EcranPoste.fichePondeuses),
    (Icons.pets, 'Fiches Volailles', 'Reproducteurs, poussins, Goliath/Chair', EcranPoste.ficheReproducteurs),
    (Icons.pets, 'Fiches Porcs', 'Suivi journalier — Porciculture', EcranPoste.fichePorcs),
    (Icons.bug_report, 'Fiches Escargots', 'Héliciculture — suivi mensuel du cheptel', EcranPoste.ficheEscargots),
  ];

  /// « Accès Rapides — Élevage & Soins », dans l'ordre du Blade.
  static const accesRapides = <CarteHub>[
    (Icons.favorite, 'Suivi Reproduction', 'Saillies, palpations, mises bas, sevrages', EcranPoste.suiviReproduction),
    (Icons.vaccines, 'Soins et Vaccins', 'Registre vétérinaire, calendrier, rémanence', EcranPoste.soinsEtVaccins),
    (Icons.dashboard, 'Dashboard Élevage', 'GMQ, rentabilité, alertes', EcranPoste.dashboardElevage),
    (
      Icons.swap_horiz,
      'Transferts entre Bandes',
      "Portées, sevrés, regroupements ; rattachement à la bande d'origine",
      EcranPoste.transfertsBandes,
    ),
  ];

  @override
  State<GestionElevageScreen> createState() => _GestionElevageScreenState();
}

class _GestionElevageScreenState extends State<GestionElevageScreen> {
  IndicateursGestionElevage? _indicateurs;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final indicateurs = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _indicateurs = indicateurs);
  }

  @override
  Widget build(BuildContext context) {
    final k = _indicateurs;

    // ⚠️ Rien ne s'affiche tant que les indicateurs ne sont pas lus : griser Escargots puis le dégriser sous le
    // doigt de l'utilisateur serait pire qu'une seconde d'attente.
    if (k == null) {
      return const Scaffold(
        backgroundColor: AgriColors.surfaceBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final large = AgriBreakpoints.large(context);
    // `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` — sur la largeur de l'ÉCRAN (`AgriBreakpoints`).
    final colonnesCartes = large ? 3 : (AgriBreakpoints.petit(context) ? 2 : 1);

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _entete(large),
            const SizedBox(height: AgriSpacing.md),
            // `grid grid-cols-2 lg:grid-cols-4 gap-sm lg:gap-md mb-lg`.
            _grille(
              colonnes: large ? 4 : 2,
              ecart: large ? AgriSpacing.md : AgriSpacing.sm,
              enfants: _kpis(k),
            ),
            const SizedBox(height: AgriSpacing.lg),
            _intertitre('Registres par Espèce'),
            _grille(
              colonnes: colonnesCartes,
              ecart: AgriSpacing.md,
              enfants: [
                for (final carte in GestionElevageScreen.registres)
                  if (carte.$4 == null)
                    _carte(
                      carte,
                      cle: 'carte-bandes-sujets',
                      description: '${k.bandesActives}${carte.$3}',
                      onTap: _bandesSurLeWeb,
                    )
                  else if (carte.$4 == EcranPoste.ficheEscargots && !k.helicoActif)
                    _carte(
                      carte,
                      description: GestionElevageScreen.descriptionEscargotsDesactive,
                      grise: true,
                    )
                  else
                    _carte(carte),
              ],
            ),
            const SizedBox(height: AgriSpacing.lg),
            _intertitre('Accès Rapides — Élevage & Soins'),
            _grille(
              colonnes: colonnesCartes,
              ecart: AgriSpacing.md,
              enfants: [for (final carte in GestionElevageScreen.accesRapides) _carte(carte)],
            ),
          ],
        ),
      ),
    );
  }

  /// `<h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs">` + `<p class="text-xs text-outline mt-xs">`.
  Widget _entete(bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.pets, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text(
              'Gestion Élevage',
              style: TextStyle(
                fontSize: large ? AgriTypography.xl : AgriTypography.lg,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AgriSpacing.xs),
      const Text(
        "Vue d'ensemble du cheptel et accès rapide aux registres de chaque espèce.",
        style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
      ),
    ],
  );

  /// Les quatre `<x-kpi-card>` du Blade, couleurs de `$variants` (`kpi-card.blade.php`).
  List<Widget> _kpis(IndicateursGestionElevage k) => [
    CarteKpi(
      libelle: 'Effectif Total Vivant',
      icone: Icons.pets,
      couleurLisere: AgriColors.brandEmerald,
      couleurIcone: AgriColors.brandEmerald,
      valeur: GestionElevageRepository.formaterEntier(k.effectifTotal),
      legende: 'Cumul de tous les animaux vivants enregistrés',
    ),
    CarteKpi(
      libelle: 'Bandes Actives',
      icone: Icons.layers,
      couleurLisere: AgriColors.accentYellow,
      couleurIcone: AgriColors.brandForest,
      valeur: '${k.bandesActives}',
      legende: 'Lots au statut « Actif », toutes espèces',
    ),
    // `:pending="true" pending-since="Sprint 6 (Stocks)"` : aucune table ne suit encore un stock d'aliment.
    CarteKpi(
      libelle: 'Alertes Stock Aliment',
      icone: Icons.warning,
      couleurLisere: AgriColors.errorRed,
      couleurIcone: AgriColors.errorRed,
      valeur: '—',
      couleurValeur: AgriColors.outline.withValues(alpha: 0.5),
      legende: 'Disponible après Sprint 6 (Stocks)',
    ),
    CarteKpi(
      libelle: 'Taux Mortalité (mois)',
      icone: Icons.monitor_heart,
      couleurLisere: AgriColors.infoBlue,
      couleurIcone: AgriColors.infoBlue,
      valeur: GestionElevageRepository.formaterTaux(k.tauxMortaliteMois),
      legende: k.tauxMortaliteMois != null ? 'Seuil normal < 5%' : 'Aucune fiche journalière saisie ce mois-ci',
    ),
  ];

  /// `<h3 class="text-xs font-bold text-brand-forest uppercase tracking-wider mb-sm">`.
  Widget _intertitre(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: AgriTypography.gras,
        color: AgriColors.brandForest,
        // `tracking-wider` : 0,05 em.
        letterSpacing: AgriTypography.xs * 0.05,
      ),
    ),
  );

  /// Grille CSS : colonnes de même largeur, cellules d'une même rangée à la même hauteur.
  Widget _grille({required int colonnes, required double ecart, required List<Widget> enfants}) {
    final rangees = <Widget>[];
    for (var i = 0; i < enfants.length; i += colonnes) {
      if (i > 0) rangees.add(SizedBox(height: ecart));
      rangees.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < colonnes; j++) ...[
                if (j > 0) SizedBox(width: ecart),
                Expanded(child: i + j < enfants.length ? enfants[i + j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rangees);
  }

  void _bandesSurLeWeb() => ToastAgri.afficher(
    context,
    GestionElevageScreen.messageBandesWeb,
    type: TypeToast.avertissement,
  );

  /// `components/nav-card.blade.php` — et sa variante grisée (Escargots, module désactivé) : fond d'icône
  /// `bg-outline-variant/20`, icône `text-outline`, le lien restant actif.
  Widget _carte(CarteHub carte, {String? cle, String? description, bool grise = false, VoidCallback? onTap}) {
    final (icone, titre, descriptionBlade, ecran) = carte;
    return Material(
      color: AgriColors.surfaceCard,
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      child: InkWell(
        key: Key(cle ?? 'carte-${ecran!.name}'),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        onTap: onTap ?? () => widget.onOuvrir(ecran!),
        child: Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: grise
                      ? AgriColors.outlineVariant.withValues(alpha: 0.2)
                      : AgriColors.brandEmerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: Icon(icone, color: grise ? AgriColors.outline : AgriColors.brandEmerald, size: 24),
              ),
              const SizedBox(width: AgriSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.brandForest,
                      ),
                    ),
                    Text(
                      description ?? descriptionBlade,
                      style: const TextStyle(fontSize: 11, color: AgriColors.outline),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AgriColors.outline),
            ],
          ),
        ),
      ),
    );
  }
}
