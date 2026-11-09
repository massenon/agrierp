import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/mecef/passerelle_boitier.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import 'transmission_boitier.dart';

/// MECEF-2 — L'INDICATEUR DU BOÎTIER FISCAL : prêt ou injoignable, factures en attente / refusées / à vérifier, et les deux gestes
/// (vérifier le boîtier, transmettre les factures en attente). N'existe qu'en mode `boitier` sur le poste Windows.
///
/// ⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER. Un boîtier absent est un ÉTAT, pas une erreur : jamais de rouge, jamais de fenêtre d'alerte.
/// [compact] : la version de la caisse (une ligne). Complet : Paramètres > Facturation normalisée (informations de l'appareil).
class BandeauBoitier extends StatefulWidget {
  const BandeauBoitier({super.key, this.compact = false, this.service});

  final bool compact;
  final TransmissionBoitier? service;

  @override
  State<BandeauBoitier> createState() => _BandeauBoitierState();
}

class _BandeauBoitierState extends State<BandeauBoitier> {
  bool _actif = false;
  bool _occupe = false;
  InfoBoitier? _infos;
  ({int enAttente, int refusees, int aVerifier}) _compteurs = (enAttente: 0, refusees: 0, aVerifier: 0);
  String? _resume;

  TransmissionBoitier? get _service => widget.service ?? TransmissionBoitier.courant;

  @override
  void initState() {
    super.initState();
    _service?.addListener(_actualiser);
    unawaited(_charger(verifier: true));
  }

  @override
  void dispose() {
    _service?.removeListener(_actualiser);
    super.dispose();
  }

  void _actualiser() {
    unawaited(_charger(verifier: false));
  }

  Future<void> _charger({required bool verifier}) async {
    final s = _service;
    if (s == null) return;
    final actif = await s.actif();
    if (!mounted) return;
    if (!actif) {
      setState(() => _actif = false);
      return;
    }
    if (verifier) await s.verifier();
    final c = await s.compteurs();
    if (!mounted) return;
    setState(() {
      _actif = true;
      _compteurs = c;
    });
  }

  Future<void> _verifier() async {
    final s = _service;
    if (s == null) return;
    setState(() {
      _occupe = true;
      _resume = null;
    });
    final e = await s.verifier();
    final infos = e.pret ? await s.passerelle.informations() : null;
    final c = await s.compteurs();
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _infos = infos;
      _compteurs = c;
    });
  }

  Future<void> _transmettre() async {
    final s = _service;
    if (s == null) return;
    setState(() {
      _occupe = true;
      _resume = null;
    });
    final faites = await s.reprendre();
    final c = await s.compteurs();
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _compteurs = c;
      _resume = faites == 0 ? "Aucune facture n'a pu être transmise pour le moment." : '$faites facture(s) transmise(s) au boîtier.';
    });
  }

  Future<void> _relancerAVerifier() async {
    final s = _service;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vérifier sur le boîtier'),
        content: const Text(
          "Pour ces factures, la réponse du boîtier n'est pas revenue : il les a peut-être déjà certifiées. Regardez sur l'appareil (dernières factures) : "
          "si une facture y figure déjà, ne la relancez pas. Relancer une facture déjà certifiée en crée une seconde.",
        ),
        actions: [
          TextButton(key: const Key('boitier-annuler-relance'), onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(key: const Key('boitier-confirmer-relance'), onPressed: () => Navigator.pop(c, true), child: const Text("Je l'ai vérifié : relancer")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _occupe = true);
    for (final v in await s.aVerifier()) {
      await s.transmettre(v.id, apresVerification: true);
    }
    final c = await s.compteurs();
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _compteurs = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    if (s == null || !_actif) return const SizedBox.shrink();

    final etat = s.etat;
    final pret = etat?.pret ?? false;
    final texteEtat = etat == null ? 'Boîtier non vérifié' : etat.message;
    final compteurs = [
      if (_compteurs.enAttente > 0) '${_compteurs.enAttente} facture(s) en attente du boîtier',
      if (_compteurs.refusees > 0) '${_compteurs.refusees} refusée(s) par le boîtier',
      if (_compteurs.aVerifier > 0) '${_compteurs.aVerifier} à vérifier sur l\'appareil',
    ];
    final dernier = s.dernier;

    final entete = Row(
      children: [
        Icon(pret ? SymbolesAgri.check_circle : SymbolesAgri.info, size: 16, color: pret ? AgriColors.brandEmerald : AgriColors.outline),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            key: const Key('boitier-etat'),
            texteEtat,
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600, color: pret ? AgriColors.brandForest : AgriColors.errorRed),
          ),
        ),
        TextButton(
          key: const Key('boitier-verifier'),
          onPressed: _occupe ? null : _verifier,
          child: Text(_occupe ? 'Patientez…' : (widget.compact ? 'Vérifier' : 'Vérifier le boîtier'), style: const TextStyle(fontSize: 11)),
        ),
      ],
    );

    return Container(
      key: const Key('bandeau-boitier'),
      margin: const EdgeInsets.fromLTRB(AgriSpacing.md, AgriSpacing.xs, AgriSpacing.md, AgriSpacing.xs),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          entete,
          if (compteurs.isNotEmpty)
            Text(compteurs.join(' · '), key: const Key('boitier-compteurs'), style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
          if (dernier != null && dernier.issue != IssueTransmission.nonConcernee)
            Text(dernier.message, key: const Key('boitier-dernier'), style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
          if (!widget.compact) ...[
            if (_infos != null)
              Padding(
                padding: const EdgeInsets.only(top: AgriSpacing.xs),
                child: Text(
                  'Appareil : NIM ${_infos!.nim} · IFU ${_infos!.ifu} · compteur ${_infos!.compteur} · factures de vente ${_infos!.compteurVentes}',
                  key: const Key('boitier-infos'),
                  style: const TextStyle(fontSize: 11, color: AgriColors.outline),
                ),
              ),
            if (_resume != null) Text(_resume!, key: const Key('boitier-resume'), style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
            Wrap(
              spacing: AgriSpacing.xs,
              children: [
                OutlinedButton(
                  key: const Key('boitier-transmettre'),
                  onPressed: _occupe || (_compteurs.enAttente == 0) ? null : _transmettre,
                  child: const Text('Transmettre les factures en attente', style: TextStyle(fontSize: 11)),
                ),
                if (_compteurs.aVerifier > 0)
                  OutlinedButton(
                    key: const Key('boitier-relancer'),
                    onPressed: _occupe ? null : _relancerAVerifier,
                    child: const Text('Relancer après vérification', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const Text(
              "Fonction construite sans l'appareil : pas encore essayée avec un vrai boîtier.",
              style: TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ],
        ],
      ),
    );
  }
}
