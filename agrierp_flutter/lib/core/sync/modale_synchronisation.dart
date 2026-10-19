import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../erreurs/message_erreur.dart';
import '../temps/heure_benin.dart';
import '../theme/agri_tokens.dart';
import '../widgets/carte_kpi.dart';
import '../widgets/modale_agri.dart';
import '../widgets/toast_agri.dart';
import 'sync_engine.dart';
import '../theme/symboles_agri.dart';

/// Ticket H2 — MODALE « SYNCHRONISATION » du poste, ouverte par le bouton de la barre supérieure
/// (PRD `docs/prd/synchronisation-barre-superieure.md`, EF2, EF4-EF6, EF14).
///
/// Même bouton, même modale, même titre qu'au web (ticket H3) ; le contenu est celui de CE poste : sa liaison,
/// sa file, ses refus. Le web, lui, montre l'état de tous les postes (le serveur n'envoie rien).
///
/// ⚠️ HORS LIGNE N'EST PAS UNE ERREUR (`agrierp_flutter/CLAUDE.md`) : la modale s'ouvre et lit la base locale ;
/// « Synchroniser maintenant » sans réseau répond par un avertissement, jamais par du rouge.
class ModaleSynchronisation extends StatefulWidget {
  const ModaleSynchronisation({
    super.key,
    required this.engine,
    required this.database,
    this.onVoirDetail,
    this.onTermine,
  });

  final SyncEngine engine;
  final AppDatabase database;

  /// Ouvre l'écran Synchronisation (refus détaillés, « Remettre en file »). `null` : bouton non proposé.
  final VoidCallback? onVoirDetail;

  /// Appelé après chaque tentative : la barre supérieure relit son compteur.
  final VoidCallback? onTermine;

  @override
  State<ModaleSynchronisation> createState() => _ModaleSynchronisationState();
}

class _ModaleSynchronisationState extends State<ModaleSynchronisation> {
  bool? _enLigne;
  ({int aEnvoyer, int refuses})? _compteurs;
  SyncStateData? _etat;
  bool _enCours = false;

  /// Résultat de la dernière tentative faite DANS cette modale (EF4, point 4).
  SyncOutcome? _resultat;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    final enLigne = await widget.engine.estEnLigne();
    final compteurs = await widget.database.compteursSynchronisation();
    final etat = await widget.database.etatDeSynchronisation();
    if (!mounted) return;
    setState(() {
      _enLigne = enLigne;
      _compteurs = compteurs;
      _etat = etat;
    });
  }

  Future<void> _synchroniser() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final r = await widget.engine.synchroniser();
      if (!mounted) return;
      setState(() => _resultat = r);
      _annoncer(r);
    } catch (e) {
      // ⚠️ L'ÉCHEC EST DIT, JAMAIS AVALÉ : c'est le seul moment où l'utilisateur peut encore agir.
      if (!mounted) return;
      // Ticket U5 : jamais l'exception brute (anglaise) à l'écran.
      final message = e is EchecSynchronisation ? e.message : 'Synchronisation impossible — ${messageErreur(e)}';
      setState(() => _erreur = message);
      ToastAgri.afficher(context, message, type: TypeToast.erreur, duree: const Duration(seconds: 8));
    } finally {
      if (mounted) setState(() => _enCours = false);
      await _relire();
      widget.onTermine?.call();
    }
  }

  void _annoncer(SyncOutcome r) {
    if (r.horsLigne) {
      ToastAgri.afficher(
        context,
        'Serveur injoignable — les saisies restent sur ce poste et partiront à la prochaine synchronisation.',
        type: TypeToast.avertissement,
      );
      return;
    }
    if (r.rejete > 0) {
      ToastAgri.afficher(
        context,
        '${r.rejete} enregistrement(s) refusé(s) — voir le détail.',
        type: TypeToast.erreur,
        duree: const Duration(seconds: 8),
      );
      return;
    }
    if (r.avertissements.isNotEmpty) {
      ToastAgri.afficher(
        context,
        r.avertissements.join(' '),
        type: TypeToast.avertissement,
        duree: const Duration(seconds: 12),
      );
      return;
    }
    ToastAgri.afficher(
      context,
      'Synchronisation terminée : ${r.tire} reçu(s), ${r.accepte} envoyé(s).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _compteurs;
    final enLigne = _enLigne;

    return ModaleAgri(
      key: const Key('modale-synchronisation'),
      titre: 'Synchronisation',
      surtitre: 'Poste ${widget.engine.deviceId}',
      largeur: LargeurModale.lg,
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _liaison(enLigne),
          const SizedBox(height: AgriSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CarteKpi(
                  key: const Key('sync-en-attente'),
                  libelle: "En attente d'envoi",
                  valeur: c == null ? '—' : '${c.aEnvoyer}',
                  icone: SymbolesAgri.cloud_upload,
                  couleurLisere: AgriColors.accentYellow,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: CarteKpi(
                  key: const Key('sync-refuses'),
                  libelle: 'Refusés par le serveur',
                  valeur: c == null ? '—' : '${c.refuses}',
                  icone: SymbolesAgri.block,
                  couleurLisere: AgriColors.errorRed,
                  couleurValeur: (c?.refuses ?? 0) > 0 ? AgriColors.errorDeep : AgriColors.onSurface,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: CarteKpi(
                  key: const Key('sync-derniere-reussie'),
                  libelle: 'Dernière synchronisation réussie',
                  // « — » et non « Jamais » : la carte dit qu'elle ne connaît pas d'instant, comme toute valeur
                  // inconnue du poste.
                  valeur: _etat?.lastSucceededAt == null ? '—' : horodatage(_etat!.lastSucceededAt!),
                  tailleValeur: AgriTypography.sm,
                  icone: SymbolesAgri.cloud_done,
                  couleurLisere: AgriColors.brandEmerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          _ligneDate('Dernière réception', _etat?.lastPulledAt, const Key('sync-derniere-reception')),
          _ligneDate('Dernier envoi', _etat?.lastPushedAt, const Key('sync-dernier-envoi')),
          if (_resultat != null || _erreur != null) ...[
            const SizedBox(height: AgriSpacing.md),
            _derniereTentative(),
          ],
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.onVoirDetail != null)
          BoutonModaleSecondaire(
            key: const Key('sync-voir-detail'),
            libelle: 'Voir le détail',
            onPressed: () {
              Navigator.of(context).pop();
              widget.onVoirDetail!();
            },
          ),
        BoutonModalePrimaire(
          key: const Key('sync-maintenant'),
          libelle: _enCours ? 'Synchronisation…' : 'Synchroniser maintenant',
          onPressed: _enCours ? null : _synchroniser,
        ),
      ],
    );
  }

  Widget _liaison(bool? enLigne) {
    final (texte, couleur, icone) = switch (enLigne) {
      true => ('En ligne', AgriColors.brandEmerald, SymbolesAgri.wifi),
      false => ('Hors ligne', AgriColors.outline, SymbolesAgri.wifi_off),
      null => ('—', AgriColors.outline, SymbolesAgri.wifi_find),
    };
    return Row(
      key: const Key('sync-liaison'),
      children: [
        Icon(icone, size: 18, color: couleur),
        const SizedBox(width: AgriSpacing.xs),
        Text(
          texte,
          style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: couleur),
        ),
        if (_enCours) ...[
          const SizedBox(width: AgriSpacing.sm),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AgriColors.brandEmerald),
          ),
        ],
      ],
    );
  }

  Widget _ligneDate(String libelle, DateTime? quand, Key cle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
          ),
          Text(
            quand == null ? 'Jamais' : horodatage(quand),
            key: cle,
            style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// EF4, point 4 — TOUS les motifs de refus, plus seulement le premier (`sync_button.dart:146` n'en montrait
  /// qu'un) : l'utilisateur doit pouvoir les lire avant de corriger.
  Widget _derniereTentative() {
    final r = _resultat;
    final lignes = <Widget>[];
    if (_erreur != null) {
      lignes.add(_texte(_erreur!, AgriColors.errorDeep));
    } else if (r != null && r.horsLigne) {
      lignes.add(_texte('Serveur injoignable : rien n\'a été envoyé ni reçu.', AgriColors.brandForest));
    } else if (r != null) {
      lignes.add(_texte('${r.tire} reçu(s) · ${r.accepte} accepté(s) · ${r.rejete} refusé(s)', AgriColors.onSurface));
      for (final m in r.motifs) {
        lignes.add(_texte('• $m', AgriColors.errorDeep));
      }
      for (final a in r.avertissements) {
        lignes.add(_texte('⚠ $a', AgriColors.brandForest));
      }
    }

    return Container(
      key: const Key('sync-derniere-tentative'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dernière tentative',
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
          ),
          const SizedBox(height: AgriSpacing.xs),
          ...lignes,
        ],
      ),
    );
  }

  Widget _texte(String t, Color couleur) => Text(t, style: TextStyle(fontSize: AgriTypography.xs, color: couleur));

  /// `dd/mm/AAAA HH:MM`, à l'heure du Bénin (S-T11) — même format que l'écran Synchronisation.
  static String horodatage(DateTime d) {
    final l = HeureBenin.depuisInstant(d);
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
