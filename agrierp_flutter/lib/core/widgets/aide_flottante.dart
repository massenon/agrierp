import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aide/aide_ecrans.dart';
import '../aide/placement_visite.dart';
import '../auth/permissions_poste.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket AIDE-1 — BOUTON FLOTTANT D'AIDE, PANNEAU ET VISITE GUIDÉE, transposés de `components/aide-flottante.blade.php`
/// (le maître). Posés par `SocleAccueil` SEULEMENT quand le module « Assistant de démarrage » est allumé (copie locale de
/// `modules_config`, éteint par défaut) : éteint, aucun bouton, comme au web.
///
/// Web :
/// - bouton : `fixed z-[60] w-12 h-12 rounded-full bg-brand-emerald hover:bg-brand-forest text-white shadow-lg`,
///   `bottom:148px; right:16px`, icône `help` 24 px, title « Aide et visite guidée » — AU-DESSUS du bouton « Accès rapide »
///   (`bottom:88px`, 48 px) avec 12 px d'écart : les deux ne se chevauchent pas ;
/// - panneau : le gabarit du tiroir « Accès rapide » (`w-72 max-w-[85vw]`, en-tête `bg-brand-forest`, voile `bg-black/40`) ;
///   section « Aide de cet écran » (titre + puces), « Relancer l'assistant de démarrage » (administrateur) et « Visite guidée » ;
/// - visite : 4 étapes, voile `rgba(0,0,0,0.6)` avec un trou sur l'élément expliqué, carte blanche (`w-[22rem]`), indicateur
///   « Étape N sur 4 » + points, « Passer » toujours visible, message de fin sobre.
///
/// ⚠️ ÉCART (plateforme) : au web le trou est une ombre géante sur un `div` posé aux coordonnées de l'élément
/// (`getBoundingClientRect`) ; au poste c'est un `CustomPainter` qui découpe le voile aux coordonnées du `RenderBox` de l'élément
/// (`GlobalKey`). Même résultat visuel, même placement de la carte (`PlacementVisite`, transposition de `aide-logique.js`).
/// Les textes sont ceux du web, mot pour mot (`AideEcrans`, produit depuis `lang/fr/aide_ecrans.php`).
class CiblesVisite {
  /// Les quatre éléments expliqués, dans l'ordre des étapes — `data-aide="aide|topbar|contenu|menu"` du web.
  final aide = GlobalKey(debugLabel: 'cible-aide');
  final topbar = GlobalKey(debugLabel: 'cible-topbar');
  final contenu = GlobalKey(debugLabel: 'cible-contenu');
  final menu = GlobalKey(debugLabel: 'cible-menu');

  /// Les noms des quatre cibles, dans l'ordre des étapes : ceux de `data-aide` du web (comparés au Blade par
  /// `test/aide_ecrans_parite_test.dart`).
  static const ordre = ['aide', 'topbar', 'contenu', 'menu'];

  /// Les clés, dans l'ordre des quatre étapes de la visite.
  List<GlobalKey> get parEtape => [aide, topbar, contenu, menu];
}

/// Ce que l'utilisateur a choisi dans le panneau.
enum ActionAide { relancerAssistant, visiteGuidee }

class AideFlottante {
  AideFlottante._();

  /// Ouvre le panneau d'aide de [ecran] ; [surRelancer] est appelé APRÈS la fermeture du panneau (`null` : pas de ligne
  /// « Relancer l'assistant de démarrage », comme `@can('manage-parametres')` au web).
  static Future<void> ouvrir(
    BuildContext context, {
    required EcranPoste ecran,
    required CiblesVisite cibles,
    VoidCallback? surRelancer,
  }) async {
    final choix = await showGeneralDialog<ActionAide>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AideEcrans.panneau['fermer']!,
      // `bg-black/40`.
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (contexte, _, _) =>
          _PanneauAide(ecran: ecran, peutRelancer: surRelancer != null),
      transitionBuilder: (_, animation, _, enfant) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: enfant,
      ),
    );
    if (!context.mounted) return;
    switch (choix) {
      case ActionAide.relancerAssistant:
        surRelancer?.call();
      case ActionAide.visiteGuidee:
        await VisiteGuidee.demarrer(context, cibles);
      case null:
        break;
    }
  }
}

/// Bouton flottant `help`, à placer dans le même `Stack` que [BoutonAccesRapide] (`bottom:148px right:16px`).
class BoutonAide extends StatelessWidget {
  const BoutonAide({
    super.key,
    required this.ecran,
    required this.cibles,
    this.surRelancer,
  });

  final EcranPoste ecran;
  final CiblesVisite cibles;

  /// `null` : le compte n'a pas le droit de l'assistant (`manage-parametres`) — la ligne n'est pas proposée.
  final VoidCallback? surRelancer;

  /// 88 (Accès rapide) + 48 (son diamètre) + 12 (écart).
  static const double bas = 148;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: AgriSpacing.md,
      bottom: bas,
      child: Tooltip(
        message: AideEcrans.panneau['bouton']!,
        child: Material(
          key: const Key('bouton-aide'),
          // La cible de l'étape 1 de la visite : le bouton lui-même.
          child: KeyedSubtree(
            key: cibles.aide,
            child: Material(
              color: AgriColors.brandEmerald,
              shape: const CircleBorder(),
              elevation: 6,
              child: InkWell(
                customBorder: const CircleBorder(),
                hoverColor: AgriColors.brandForest,
                onTap: () => AideFlottante.ouvrir(
                  context,
                  ecran: ecran,
                  cibles: cibles,
                  surRelancer: surRelancer,
                ),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(SymbolesAgri.help, size: 24, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanneauAide extends StatelessWidget {
  const _PanneauAide({required this.ecran, required this.peutRelancer});

  final EcranPoste ecran;
  final bool peutRelancer;

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
    final aide = AideEcrans.pour(ecran);
    final libelles = AideEcrans.panneau;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        key: const Key('panneau-aide'),
        color: Colors.white,
        elevation: 24,
        child: SizedBox(
          // `w-72 max-w-[85vw]`.
          width: largeur * 0.85 < 288 ? largeur * 0.85 : 288,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AgriSpacing.md),
                decoration: const BoxDecoration(
                  color: AgriColors.brandForest,
                  border: Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      SymbolesAgri.help,
                      size: 20,
                      color: AgriColors.accentYellow,
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Expanded(
                      child: Text(
                        libelles['titre']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AgriTypography.sm,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('aide-fermer'),
                      tooltip: libelles['fermer'],
                      iconSize: 20,
                      color: Colors.white.withValues(alpha: 0.80),
                      icon: const Icon(SymbolesAgri.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AgriSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AgriSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              SymbolesAgri.lightbulb,
                              size: 16,
                              color: AgriColors.brandEmerald,
                            ),
                            const SizedBox(width: AgriSpacing.xs),
                            Expanded(
                              child: Text(
                                libelles['ecran']!.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: AgriColors.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AgriSpacing.sm,
                          AgriSpacing.xs,
                          AgriSpacing.sm,
                          0,
                        ),
                        child: Text(
                          aide.titre,
                          key: const Key('aide-ecran-titre'),
                          style: const TextStyle(
                            fontSize: AgriTypography.sm,
                            fontWeight: FontWeight.bold,
                            color: AgriColors.brandForest,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AgriSpacing.sm,
                          AgriSpacing.xs,
                          AgriSpacing.sm,
                          0,
                        ),
                        child: Column(
                          key: const Key('aide-ecran-puces'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final puce in aide.puces)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AgriSpacing.xs,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '•  ',
                                      style: TextStyle(
                                        fontSize: AgriTypography.xs,
                                        color: AgriColors.onSurface,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        puce,
                                        style: const TextStyle(
                                          fontSize: AgriTypography.xs,
                                          color: AgriColors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: AgriColors.outlineVariant,
                        ),
                      ),
                      if (peutRelancer)
                        _ligne(
                          context,
                          cle: 'aide-relancer',
                          icone: SymbolesAgri.checklist,
                          titre: libelles['relancer']!,
                          detail: libelles['relancer_detail']!,
                          action: ActionAide.relancerAssistant,
                        ),
                      _ligne(
                        context,
                        cle: 'aide-visite',
                        icone: SymbolesAgri.school,
                        titre: libelles['visite']!,
                        detail: libelles['visite_detail']!,
                        action: ActionAide.visiteGuidee,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ligne(
    BuildContext context, {
    required String cle,
    required IconData icone,
    required String titre,
    required String detail,
    required ActionAide action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: InkWell(
        key: Key(cle),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        hoverColor: AgriColors.surfaceZebra,
        onTap: () => Navigator.of(context).pop(action),
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Row(
            children: [
              Icon(icone, size: 22, color: AgriColors.brandForest),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: FontWeight.w600,
                        color: AgriColors.onSurface,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La visite guidée : voile sombre, trou sur l'élément expliqué, carte de l'étape. Rien n'est mémorisé à la fermeture
/// (comme au web : « Passer » et « Fermer » ferment, point).
class VisiteGuidee {
  VisiteGuidee._();

  static Future<void> demarrer(BuildContext context, CiblesVisite cibles) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: AideEcrans.libellesVisite['passer']!,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (contexte, _, _) => _FenetreVisite(cibles: cibles),
      transitionBuilder: (_, animation, _, enfant) =>
          FadeTransition(opacity: animation, child: enfant),
    );
  }
}

class _FenetreVisite extends StatefulWidget {
  const _FenetreVisite({required this.cibles});

  final CiblesVisite cibles;

  @override
  State<_FenetreVisite> createState() => _FenetreVisiteState();
}

class _FenetreVisiteState extends State<_FenetreVisite> {
  int _etape = 0;
  bool _fin = false;

  List<EtapeVisite> get _etapes => AideEcrans.etapesVisite;

  void _suivant() => setState(() {
    if (_etape == _etapes.length - 1) {
      _fin = true;
    } else {
      _etape += 1;
    }
  });

  void _precedent() {
    if (_etape > 0) setState(() => _etape -= 1);
  }

  void _passer() => Navigator.of(context).pop();

  /// Rectangle (coordonnées de la fenêtre) de l'élément de l'étape ; `null` s'il n'est pas à l'écran (menu replié…).
  Rect? _rectDe(GlobalKey cle) {
    final objet = cle.currentContext?.findRenderObject();
    if (objet is! RenderBox || !objet.attached || !objet.hasSize) return null;
    return objet.localToGlobal(Offset.zero) & objet.size;
  }

  @override
  Widget build(BuildContext context) {
    final fenetre = MediaQuery.sizeOf(context);
    final rect = _fin ? null : _rectDe(widget.cibles.parEtape[_etape]);
    final trou = rect != null && PlacementVisite.rectUtilisable(rect, fenetre)
        ? PlacementVisite.trouAutour(rect, fenetre)
        : null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _passer,
        if (!_fin)
          const SingleActivator(LogicalKeyboardKey.arrowRight): _suivant,
        if (!_fin)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _precedent,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          key: const Key('visite-guidee'),
          children: [
            // Le voile : absorbe les clics (la page derrière est inerte), `rgba(0,0,0,0.6)` avec un trou.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(
                  key: const Key('visite-voile'),
                  painter: _VoilePainter(trou),
                ),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _PlacementCarte(trou, fenetre),
              child: _Carte(
                etape: _etape,
                fin: _fin,
                surSuivant: _suivant,
                surPrecedent: _precedent,
                surPasser: _passer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Voile `rgba(0,0,0,0.6)` percé d'un trou aux coins arrondis (`rounded-lg`) cerclé de blanc (`ring-2 ring-white`).
class _VoilePainter extends CustomPainter {
  const _VoilePainter(this.trou);

  final Rect? trou;

  @override
  void paint(Canvas canvas, Size size) {
    final voile = Paint()..color = Colors.black.withValues(alpha: 0.60);
    final ecran = Path()..addRect(Offset.zero & size);
    if (trou == null) {
      canvas.drawPath(ecran, voile);
      return;
    }
    final forme = RRect.fromRectAndRadius(
      trou!,
      const Radius.circular(AgriRadius.lg),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, ecran, Path()..addRRect(forme)),
      voile,
    );
    canvas.drawRRect(
      forme,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_VoilePainter ancien) => ancien.trou != trou;
}

/// Pose la carte avec `PlacementVisite.placerCarte`, sur sa taille MESURÉE (le web la mesure aussi : `offsetWidth/Height`).
class _PlacementCarte extends SingleChildLayoutDelegate {
  const _PlacementCarte(this.trou, this.fenetre);

  final Rect? trou;
  final Size fenetre;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints contraintes) =>
      BoxConstraints.loose(
        Size(fenetre.width - 2 * AgriSpacing.md, fenetre.height),
      );

  @override
  Offset getPositionForChild(Size taille, Size enfant) =>
      PlacementVisite.placerCarte(trou, enfant, fenetre).position;

  @override
  bool shouldRelayout(_PlacementCarte ancien) =>
      ancien.trou != trou || ancien.fenetre != fenetre;
}

class _Carte extends StatelessWidget {
  const _Carte({
    required this.etape,
    required this.fin,
    required this.surSuivant,
    required this.surPrecedent,
    required this.surPasser,
  });

  final int etape;
  final bool fin;
  final VoidCallback surSuivant;
  final VoidCallback surPrecedent;
  final VoidCallback surPasser;

  @override
  Widget build(BuildContext context) {
    final libelles = AideEcrans.libellesVisite;
    final etapes = AideEcrans.etapesVisite;
    final derniere = etape == etapes.length - 1;

    return Material(
      key: const Key('visite-carte'),
      color: Colors.white,
      elevation: 24,
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      child: SizedBox(
        // `w-[22rem]` (352 px).
        width: 352,
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.md),
          child: fin
              ? _corpsFin(libelles)
              : _corpsEtape(libelles, etapes, derniere),
        ),
      ),
    );
  }

  Widget _corpsEtape(
    Map<String, String> libelles,
    List<EtapeVisite> etapes,
    bool derniere,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                PlacementVisite.indicateur(
                  libelles['etape_sur']!,
                  etape,
                  etapes.length,
                ).toUpperCase(),
                key: const Key('visite-indicateur'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AgriColors.outline,
                ),
              ),
            ),
            // « Passer » : toujours visible pendant les étapes.
            OutlinedButton(
              key: const Key('visite-passer'),
              onPressed: surPasser,
              style: OutlinedButton.styleFrom(
                foregroundColor: AgriColors.outline,
                side: const BorderSide(color: AgriColors.outlineVariant),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.sm,
                  vertical: 2,
                ),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                libelles['passer']!,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.sm),
        Text(
          etapes[etape].titre,
          key: const Key('visite-titre'),
          style: const TextStyle(
            fontSize: AgriTypography.base,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          etapes[etape].texte,
          key: const Key('visite-texte'),
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        Row(
          key: const Key('visite-points'),
          children: [
            for (var i = 0; i < etapes.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: AgriSpacing.xs),
                width: i == etape ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == etape
                      ? AgriColors.brandEmerald
                      : AgriColors.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AgriSpacing.xs,
          children: [
            if (etape > 0)
              OutlinedButton(
                key: const Key('visite-precedent'),
                onPressed: surPrecedent,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgriColors.brandForest,
                  side: const BorderSide(color: AgriColors.outlineVariant),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  libelles['precedent']!,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            FilledButton(
              key: const Key('visite-suivant'),
              autofocus: true,
              onPressed: surSuivant,
              style: FilledButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                shape: const StadiumBorder(),
              ),
              child: Text(
                derniere ? libelles['terminer']! : libelles['suivant']!,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Message de fin : sobre, sans confettis.
  Widget _corpsFin(Map<String, String> libelles) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              SymbolesAgri.check_circle,
              size: 22,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Expanded(
              child: Text(
                libelles['fin_titre']!,
                key: const Key('visite-fin-titre'),
                style: const TextStyle(
                  fontSize: AgriTypography.base,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          libelles['fin_texte']!,
          key: const Key('visite-fin-texte'),
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('visite-fin-fermer'),
            autofocus: true,
            onPressed: surPasser,
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              shape: const StadiumBorder(),
            ),
            child: Text(
              libelles['fin_fermer']!,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
