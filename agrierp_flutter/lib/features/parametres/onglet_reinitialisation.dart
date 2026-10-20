import 'package:flutter/material.dart';

import '../../core/erreurs/message_erreur.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'reinitialisation_poste.dart';

/// Ticket R-1 (demande du client : « sur le web et le poste ») — onglet « Réinitialisation » du hub Paramètres,
/// AU POSTE. Transposé de `resources/views/livewire/parametres/reinitialisation-donnees.blade.php` (MAÎTRE, lu par
/// `test/reinitialisation_blade_test.dart`) : même en-tête, même carte « Mode démonstration » et sa bascule,
/// même avertissement, mêmes listes « Supprimé » / « Conservé », même bouton, même modale et même mot à recopier,
/// même bloc « Réinitialisation verrouillée ». L'action est celle du web, par la route du poste
/// ([ReinitialisationPoste]).
///
/// ⚠️ ÉCART (plateforme) — trois blocs que le web n'a pas, parce que le poste a une base à lui et peut être coupé
/// du serveur :
///  - **hors ligne**, l'onglet le dit et ses deux boutons sont désactivés : on ne réinitialise pas le serveur
///    sans lui ;
///  - les **saisies non envoyées** de ce poste (table par table) sont annoncées, à l'écran et dans la modale, et
///    leur perte doit être acceptée explicitement (case à cocher) avant l'appel au serveur ;
///  - **un refus de lecture** du serveur (droit, version) est affiché tel quel.
///
/// ⚠️ ÉCART (composant unique) — la modale est [ModaleConfirmation] (icône centrée, titre, message, boutons
/// empilés), le gabarit de confirmation du poste ; le web pose ses boutons en ligne.
class OngletReinitialisation extends StatefulWidget {
  const OngletReinitialisation({super.key, required this.depot});

  final ReinitialisationPoste depot;

  @override
  State<OngletReinitialisation> createState() => _OngletReinitialisationState();
}

class _OngletReinitialisationState extends State<OngletReinitialisation> {
  bool _charge = false;
  bool? _enLigne;

  /// État de la bascule sur le serveur ; `null` : inconnu (hors ligne, lecture refusée).
  bool? _modeDemo;
  String? _erreurLecture;
  List<SaisiesNonEnvoyees> _nonEnvoyees = const [];
  bool _basculeEnCours = false;
  bool _reinitialisationEnCours = false;

  ReinitialisationPoste get _d => widget.depot;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (!_d.autorise) {
      setState(() => _charge = true);
      return;
    }
    final enLigne = await _d.estEnLigne();
    final nonEnvoyees = await _d.saisiesNonEnvoyees();
    bool? mode;
    String? erreur;
    if (enLigne) {
      try {
        mode = await _d.modeDemoActif();
      } on RefusReinitialisation catch (e) {
        erreur = e.message;
      } catch (e) {
        erreur = messageErreur(e);
      }
    }
    if (!mounted) return;
    setState(() {
      _charge = true;
      _enLigne = enLigne;
      // Une perte de réseau après lecture garde l'état lu : l'écran dit alors « hors ligne ».
      _modeDemo = enLigne ? mode : _modeDemo;
      _erreurLecture = erreur;
      _nonEnvoyees = nonEnvoyees;
    });
  }

  void _toast(String message, {TypeToast type = TypeToast.succes, Duration? duree}) =>
      ToastAgri.afficher(context, message, type: type, duree: duree);

  Future<void> _basculer() async {
    setState(() => _basculeEnCours = true);
    try {
      final r = await _d.basculerModeDemo();
      if (!mounted) return;
      setState(() => _modeDemo = r.actif);
      _toast(r.message, type: r.avertissement ? TypeToast.avertissement : TypeToast.succes);
    } on RefusReinitialisation catch (e) {
      if (mounted) _toast(e.message, type: TypeToast.erreur);
    } catch (e) {
      if (mounted) _toast(messageErreur(e), type: TypeToast.erreur);
    } finally {
      if (mounted) setState(() => _basculeEnCours = false);
    }
  }

  Future<void> _ouvrirModale() async {
    // Les saisies sont recomptées à l'ouverture : une vente faite depuis l'affichage de l'onglet compte aussi.
    final nonEnvoyees = await _d.saisiesNonEnvoyees();
    if (!mounted) return;
    setState(() => _nonEnvoyees = nonEnvoyees);
    final confirmation = await afficherModale<String>(
      context: context,
      confirmation: true,
      constructeur: (_) => _ModaleReinitialisation(nonEnvoyees: nonEnvoyees),
    );
    if (confirmation == null || !mounted) return;
    await _reinitialiser(confirmation);
  }

  Future<void> _reinitialiser(String confirmation) async {
    setState(() => _reinitialisationEnCours = true);
    try {
      final r = await _d.reinitialiser(confirmation);
      if (!mounted) return;
      _toast(r.message);
      final echec = r.echecSynchronisation;
      if (echec != null) {
        _toast(
          'Les données de ce poste ont été effacées, mais la synchronisation qui suit n\'a pas abouti — '
          '${messageErreur(echec)}',
          type: TypeToast.avertissement,
          duree: const Duration(seconds: 8),
        );
      }
    } on RefusReinitialisation catch (e) {
      if (mounted) _toast(e.message, type: TypeToast.erreur, duree: const Duration(seconds: 6));
    } catch (e) {
      if (mounted) _toast(messageErreur(e), type: TypeToast.erreur, duree: const Duration(seconds: 6));
    } finally {
      if (mounted) setState(() => _reinitialisationEnCours = false);
      await _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(large),
        const SizedBox(height: AgriSpacing.md),
        if (!_charge)
          const Center(child: CircularProgressIndicator())
        else if (!_d.autorise)
          _bandeau(ReinitialisationPoste.refusRole, SymbolesAgri.block, cle: 'reinitialisation-refus-role')
        else ...[
          if (_enLigne == false) ...[
            _bandeau(ReinitialisationPoste.refusHorsLigne, SymbolesAgri.wifi_off, cle: 'reinitialisation-hors-ligne'),
            const SizedBox(height: AgriSpacing.md),
          ] else if (_erreurLecture != null) ...[
            _bandeau(_erreurLecture!, SymbolesAgri.error, cle: 'reinitialisation-erreur-lecture'),
            const SizedBox(height: AgriSpacing.md),
          ],
          _carteModeDemo(),
          const SizedBox(height: AgriSpacing.md),
          if (_modeDemo == true) ..._contenuDeverrouille(large) else _verrouille(),
        ],
      ],
    );
  }

  // `border-b border-outline-variant pb-md` : titre `text-xl lg:text-2xl font-bold`, icône `restart_alt` 26 px
  // `text-error-deep`, sous-titre `text-xs lg:text-sm text-outline`.
  Widget _entete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.restart_alt, size: 26, color: AgriColors.errorDeep),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Réinitialisation des Données',
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
          "Vide les données d'activité pour repartir d'une base propre après une démonstration.",
          style: TextStyle(fontSize: large ? AgriTypography.sm : AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    ),
  );

  Widget _carteModeDemo() {
    final actif = _modeDemo;
    final possible = _enLigne == true && actif != null && !_basculeEnCours && !_reinitialisationEnCours;
    final allume = actif == true;

    return _carte(
      cle: 'reinitialisation-mode-demo',
      enfant: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode démonstration',
                  style: TextStyle(
                    fontSize: AgriTypography.sm,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                SizedBox(height: AgriSpacing.xs),
                Text(
                  "Tant qu'il est désactivé, aucune réinitialisation n'est possible — c'est ce qui protège "
                  "une exploitation en production d'un effacement accidentel.",
                  style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          OutlinedButton.icon(
            key: const Key('reinitialisation-basculer'),
            onPressed: possible ? _basculer : null,
            icon: Icon(allume ? SymbolesAgri.toggle_on : SymbolesAgri.toggle_off, size: 16),
            label: Text(
              actif == null ? '—' : (actif ? 'Activé' : 'Désactivé'),
              key: const Key('reinitialisation-etat-mode-demo'),
              style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: allume ? AgriColors.accentYellow : AgriColors.surfaceCard,
              foregroundColor: allume ? AgriColors.brandForest : AgriColors.outline,
              side: BorderSide(color: allume ? AgriColors.accentYellow : AgriColors.outlineVariant),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contenuDeverrouille(bool large) {
    const supprime = _ListeBlade(
      cle: 'reinitialisation-supprime',
      titre: 'Supprimé',
      icone: SymbolesAgri.delete_sweep,
      couleur: AgriColors.errorDeep,
      paragraphes: [
        'Ventes et clients · Achats et fournisseurs · Dépenses · Mouvements de stock · '
            'Bandes, fiches journalières, transferts et soins vétérinaires · Employés, paies et stages · '
            'Écritures comptables, clôtures et immobilisations achetées · Courriers, archives et documents '
            'administratifs · Notifications',
        "Les postes Windows effacent aussi leurs données d'activité à leur prochaine synchronisation ; "
            'leurs saisies non encore envoyées sont perdues.',
      ],
    );
    const conserve = _ListeBlade(
      cle: 'reinitialisation-conserve',
      titre: 'Conservé',
      icone: SymbolesAgri.shield,
      couleur: AgriColors.brandEmerald,
      paragraphes: [
        "Comptes utilisateurs et rôles · Réglages de l'entreprise · Plan comptable · "
            'Exercices et comptes de trésorerie · Catalogue produits · Espèces, rations, '
            'protocoles prophylactiques, normes de croissance · Centres de coût · Barème ITS · '
            "Modèles d'attestation · Numérotation de l'élevage · Immobilisations reprises "
            "d'antériorité (remises hors comptabilité) · Journal d'audit",
      ],
      gras: "Journal d'audit",
    );
    final possible = _enLigne == true && !_reinitialisationEnCours && !_basculeEnCours;

    return [
      Container(
        key: const Key('reinitialisation-avertissement'),
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.errorBg,
          border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(SymbolesAgri.warning, size: 18, color: AgriColors.errorDeep),
                SizedBox(width: AgriSpacing.xs),
                Flexible(
                  child: Text(
                    "Cette opération vide TOUTES les données d'activité",
                    style: TextStyle(
                      fontSize: AgriTypography.sm,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AgriSpacing.xs),
            Text(
              "L'application ne peut pas distinguer une vente de démonstration d'une vente réelle : elles "
              'vivent dans la même table, avec la même forme. Ventes, achats, dépenses, mouvements de stock, '
              'fiches d\'élevage, soins, paies et écritures comptables seront supprimés — qu\'ils viennent '
              "d'une démonstration ou d'une activité réelle.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
            ),
          ],
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      if (large)
        const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: supprime),
              SizedBox(width: AgriSpacing.md),
              Expanded(child: conserve),
            ],
          ),
        )
      else ...[
        supprime,
        const SizedBox(height: AgriSpacing.md),
        conserve,
      ],
      if (_nonEnvoyees.isNotEmpty) ...[
        const SizedBox(height: AgriSpacing.md),
        _SaisiesNonEnvoyeesBloc(nonEnvoyees: _nonEnvoyees, cle: 'reinitialisation-saisies-ecran'),
      ],
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('reinitialisation-ouvrir'),
          onPressed: possible ? _ouvrirModale : null,
          icon: _reinitialisationEnCours
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(SymbolesAgri.restart_alt, size: 18),
          label: const Text(
            'Réinitialiser les données',
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.errorRed,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          ),
        ),
      ),
    ];
  }

  // `bg-surface-zebra border border-outline-variant rounded-lg p-lg text-center`.
  Widget _verrouille() => Container(
    key: const Key('reinitialisation-verrouillee'),
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: const Column(
      children: [
        Icon(SymbolesAgri.lock, size: 44, color: AgriColors.outlineVariant),
        SizedBox(height: AgriSpacing.sm),
        Text(
          'Réinitialisation verrouillée',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: AgriTypography.demiGras,
            color: AgriColors.onSurface,
          ),
        ),
        SizedBox(height: AgriSpacing.xs),
        Text(
          'Activez le mode démonstration ci-dessus pour y accéder.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    ),
  );

  Widget _carte({required String cle, required Widget enfant}) => Container(
    key: Key(cle),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: enfant,
  );

  Widget _bandeau(String texte, IconData icone, {required String cle}) => Container(
    key: Key(cle),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: AgriColors.errorDeep),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
          ),
        ),
      ],
    ),
  );
}

/// Carte « Supprimé » / « Conservé » : `text-xs font-bold uppercase` titré, paragraphes `text-xs text-outline`.
class _ListeBlade extends StatelessWidget {
  const _ListeBlade({
    required this.cle,
    required this.titre,
    required this.icone,
    required this.couleur,
    required this.paragraphes,
    this.gras,
  });

  final String cle;
  final String titre;
  final IconData icone;
  final Color couleur;
  final List<String> paragraphes;

  /// Fin du dernier paragraphe, rendue en gras (`<strong>Journal d'audit</strong>`).
  final String? gras;

  Widget _paragraphe(String texte, String? fin) {
    final enGras = fin != null && texte.endsWith(fin);
    return Text.rich(
      TextSpan(
        text: enGras ? texte.substring(0, texte.length - fin.length) : texte,
        children: [
          if (enGras) TextSpan(text: fin, style: const TextStyle(fontWeight: AgriTypography.gras)),
        ],
      ),
      style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline, height: 1.6),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: Key(cle),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: AgriSpacing.sm),
        for (var i = 0; i < paragraphes.length; i++) ...[
          if (i > 0) const SizedBox(height: AgriSpacing.xs),
          _paragraphe(paragraphes[i], i == paragraphes.length - 1 ? gras : null),
        ],
      ],
    ),
  );
}

/// ⚠️ ÉCART (plateforme) — les saisies de CE poste qui n'ont jamais atteint le serveur, table par table.
class _SaisiesNonEnvoyeesBloc extends StatelessWidget {
  const _SaisiesNonEnvoyeesBloc({required this.nonEnvoyees, required this.cle});

  final List<SaisiesNonEnvoyees> nonEnvoyees;
  final String cle;

  @override
  Widget build(BuildContext context) {
    final total = nonEnvoyees.fold<int>(0, (s, n) => s + n.total);
    return Container(
      key: Key(cle),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.accentYellow.withValues(alpha: 0.2),
        border: Border.all(color: AgriColors.accentYellow),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ce poste a $total saisie(s) non envoyée(s) au serveur',
            key: Key('$cle-total'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          for (final n in nonEnvoyees)
            Text(
              '• ${n.libelle} : ${n.total}'
              '${n.refusees > 0 ? ' (dont ${n.refusees} refusée(s) par le serveur)' : ''}',
              key: Key('$cle-${n.table}'),
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
            ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "Elles n'ont jamais atteint le serveur : la réinitialisation les rend caduques. Elles seront effacées "
            'de ce poste dès la réinitialisation faite, et ne pourront plus être envoyées.',
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Modale « Réinitialiser toutes les données d'activité ? » — `<x-modal name="modal-reinitialisation">` du web :
/// icône `warning` `text-error-deep`, titre, message « irréversible », champ « Saisissez REINITIALISER pour
/// confirmer », « Annuler » / « Confirmer la réinitialisation ». Rend le mot saisi, `null` à l'annulation.
class _ModaleReinitialisation extends StatefulWidget {
  const _ModaleReinitialisation({required this.nonEnvoyees});

  final List<SaisiesNonEnvoyees> nonEnvoyees;

  @override
  State<_ModaleReinitialisation> createState() => _ModaleReinitialisationState();
}

class _ModaleReinitialisationState extends State<_ModaleReinitialisation> {
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _perteAcceptee = false;
  String? _erreurPerte;

  static const messagePerte = 'Cochez la case pour accepter la perte des saisies non envoyées de ce poste.';

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  void _confirmer() {
    final mot = _confirmation.text;
    final perteRequise = widget.nonEnvoyees.isNotEmpty;
    setState(() {
      // Le verrou du web, au même endroit (sous le champ) et avec son message.
      _erreur = mot == ReinitialisationPoste.motDeConfirmation ? null : ReinitialisationPoste.messageConfirmation;
      _erreurPerte = perteRequise && !_perteAcceptee ? messagePerte : null;
    });
    if (_erreur == null && _erreurPerte == null) Navigator.of(context).pop(mot);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.nonEnvoyees.fold<int>(0, (s, n) => s + n.total);

    return ModaleConfirmation(
      icone: SymbolesAgri.warning,
      couleurIcone: AgriColors.errorDeep,
      titre: "Réinitialiser toutes les données d'activité ?",
      message:
          'Cette action est irréversible : les enregistrements supprimés ne passent pas par la corbeille et ne '
          'pourront pas être restaurés. Assurez-vous d\'avoir généré une sauvegarde de la base au préalable.',
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.nonEnvoyees.isNotEmpty) ...[
            const SizedBox(height: AgriSpacing.sm),
            _SaisiesNonEnvoyeesBloc(nonEnvoyees: widget.nonEnvoyees, cle: 'reinitialisation-saisies-modale'),
            CheckboxListTile(
              key: const Key('reinitialisation-accepter-perte'),
              value: _perteAcceptee,
              onChanged: (v) => setState(() {
                _perteAcceptee = v ?? false;
                if (_perteAcceptee) _erreurPerte = null;
              }),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AgriColors.errorRed,
              title: Text(
                "J'accepte de perdre ces $total saisie(s) non envoyée(s)",
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
              ),
            ),
            if (_erreurPerte != null)
              Text(
                _erreurPerte!,
                key: const Key('reinitialisation-erreur-perte'),
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
              ),
          ],
          const SizedBox(height: AgriSpacing.md),
          Text(
            'Saisissez REINITIALISER pour confirmer'.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
          ),
          const SizedBox(height: AgriSpacing.xs),
          TextField(
            key: const Key('reinitialisation-confirmation'),
            controller: _confirmation,
            autofocus: true,
            style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, letterSpacing: 1),
            decoration: InputDecoration(
              hintText: ReinitialisationPoste.motDeConfirmation,
              errorText: _erreur,
              errorMaxLines: 2,
            ),
            onSubmitted: (_) => _confirmer(),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoutonModalePrimaire(
          key: const Key('reinitialisation-confirmer'),
          libelle: 'Confirmer la réinitialisation',
          couleur: AgriColors.errorRed,
          onPressed: _confirmer,
        ),
      ],
    );
  }
}
