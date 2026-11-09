import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'clients_creances_repository.dart';

/// Ticket VC-1 — « Enregistrer un Recouvrement » (`suivi-dettes.blade.php`, `modal-add-payment`) : encaisse une créance
/// client, EN ATTENTE d'envoi. Rend `true` quand l'encaissement a été écrit.
///
/// [depart] est la créance de la ligne depuis laquelle la modale s'ouvre ; absente (bouton « Ajouter un Recouvrement »
/// de l'en-tête), la modale propose la liste des créances ouvertes.
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT** : le serveur solde la créance, fait entrer l'argent dans les DEUX livres de
/// trésorerie et passe D 5xx / C 411 (`CustomerSettlementService`). « Nouveau Solde Dû » (maquette) n'est qu'un aperçu.
///
/// Ticket VC-3 — la fiche client ouvre la MÊME modale : « Régler » une créance ([depart], [titre] « Enregistrer un
/// Règlement », [libelleReference] « Référence ») ou « Enregistrer un règlement » du solde GLOBAL ([clientGlobal] et
/// [soldeGlobal] : encaissement sans créance visée, imputé aux plus anciennes d'abord par le serveur).
Future<bool> ouvrirRecouvrement({
  required BuildContext context,
  required ClientsCreancesRepository depot,
  required DonneesClients donnees,
  LigneCreance? depart,
  String titre = 'Enregistrer un Recouvrement',
  String libelleReference = 'Débiteur / Facture',
  String? clientGlobal,
  double soldeGlobal = 0,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleRecouvrement(
      depot: depot,
      donnees: donnees,
      depart: depart,
      titre: titre,
      libelleReference: libelleReference,
      clientGlobal: clientGlobal,
      soldeGlobal: soldeGlobal,
    ),
  );
  return ok == true;
}

class _ModaleRecouvrement extends StatefulWidget {
  const _ModaleRecouvrement({
    required this.depot,
    required this.donnees,
    required this.depart,
    required this.titre,
    required this.libelleReference,
    required this.clientGlobal,
    required this.soldeGlobal,
  });

  final ClientsCreancesRepository depot;
  final DonneesClients donnees;
  final LigneCreance? depart;
  final String titre;
  final String libelleReference;
  final String? clientGlobal;
  final double soldeGlobal;

  @override
  State<_ModaleRecouvrement> createState() => _ModaleRecouvrementState();
}

class _ModaleRecouvrementState extends State<_ModaleRecouvrement> {
  final _montant = TextEditingController();
  String _creanceId = '';
  String _compteId = '';
  String? _erreurMontant;
  String? _erreurCompte;
  String? _refus;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _creanceId = widget.depart?.creance.id ?? '';
  }

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  List<LigneCreance> get _ouvertes => [
    for (final c in widget.donnees.creances)
      if (c.resteDu > 0) c,
  ];

  bool get _global => widget.clientGlobal != null;

  LigneCreance? get _creance {
    for (final c in widget.donnees.creances) {
      if (c.creance.id == _creanceId) return c;
    }
    return null;
  }

  double? get _saisi => double.tryParse(_montant.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  static String _f(double v) => v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

  static String _reference(LigneCreance c) => (c.creance.saleId ?? c.creance.id).substring(0, 8).toUpperCase();

  static String _etiquette(LigneCreance c) => '${c.nomClient} — ${c.creance.saleId == null ? c.creance.id.substring(0, 8).toUpperCase() : c.creance.saleId!.substring(0, 8).toUpperCase()}';

  Future<void> _valider() async {
    final c = _creance;
    final montant = _saisi;
    setState(() {
      _erreurMontant = montant == null
          ? 'Le champ montant du règlement est obligatoire.'
          : montant < 1
          ? 'Le champ montant du règlement doit être supérieur ou égal à 1.'
          : null;
      _erreurCompte = _compteId.isEmpty ? 'Le champ compte de trésorerie est obligatoire.' : null;
      _refus = c == null && !_global ? 'Veuillez choisir une créance.' : null;
    });
    if (_erreurMontant != null || _erreurCompte != null || _refus != null) return;

    setState(() => _envoi = true);
    try {
      if (_global) {
        await widget.depot.encaisserSolde(clientId: widget.clientGlobal!, montant: montant!, compteId: _compteId);
      } else {
        await widget.depot.encaisserCreance(creanceId: c!.creance.id, montant: montant!, compteId: _compteId);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaisieRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    } on RefusExercice catch (e) {
      // Motif R4 en toast d'erreur, modale ouverte (comme `SuiviDettes::confirmPayment` au web).
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
    }
  }

  Widget _bloc(String libelle, Widget champ, {String? erreur}) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.xs),
        champ,
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(erreur, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = _creance;
    final saisi = _saisi;
    final solde = _global ? widget.soldeGlobal : c?.resteDu;
    final nouveau = solde == null ? null : (solde - (saisi ?? 0)).clamp(0, double.infinity);

    return ModaleAgri(
      titre: widget.titre,
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.depart == null && !_global)
            _bloc(
              'Débiteur / Facture',
              DropdownButtonFormField<String>(
                key: const Key('recouvrement-creance'),
                initialValue: _creanceId,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
                items: [
                  const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
                  for (final l in _ouvertes) DropdownMenuItem(value: l.creance.id, child: Text('${_etiquette(l)} (${_f(l.resteDu)} F)', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _creanceId = v ?? ''),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: AgriSpacing.md),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(color: AgriColors.surfaceZebra, borderRadius: BorderRadius.circular(AgriRadius.lg)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text(widget.libelleReference, style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))),
                    Flexible(
                      child: Text(
                        _global ? 'Solde global' : (c == null ? '—' : widget.libelleReference == 'Référence' ? _reference(c) : _etiquette(c)),
                        key: const Key('recouvrement-debiteur'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(child: Text('Solde restant', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))),
                    Flexible(child: Text(
                      solde == null ? '—' : '${_f(solde)} FCFA',
                      key: const Key('recouvrement-solde'),
                      style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.errorDeep),
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(child: Text('Nouveau Solde Dû', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))),
                    Flexible(child: Text(
                      nouveau == null ? '—' : '${_f(nouveau.toDouble())} FCFA',
                      key: const Key('recouvrement-nouveau-solde'),
                      style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
                    )),
                  ],
                ),
              ],
            ),
          ),
          _bloc(
            'Montant du Règlement (FCFA)',
            TextField(
              key: const Key('recouvrement-montant'),
              controller: _montant,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: 'Saisir le montant...', errorText: _erreurMontant),
              style: const TextStyle(fontSize: AgriTypography.sm),
            ),
          ),
          _bloc(
            'Compte de Trésorerie',
            DropdownButtonFormField<String>(
              key: const Key('recouvrement-compte'),
              initialValue: _compteId,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), errorText: _erreurCompte),
              style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
              items: [
                const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
                for (final TreasuryAccount t in widget.donnees.comptes) DropdownMenuItem(value: t.id, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _compteId = v ?? ''),
            ),
          ),
          if (_refus != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
              child: Text(_refus!, key: const Key('recouvrement-refus'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
            ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: _envoi ? null : () => Navigator.of(context).pop(false)),
        BoutonModalePrimaire(libelle: 'Valider le Règlement', onPressed: _envoi ? null : _valider),
      ],
    );
  }
}
