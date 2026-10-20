import 'package:flutter/material.dart';

import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import 'achats_repository.dart';

/// Motifs de retour proposés — **les trois de la maquette** (`liste-achats.html`,
/// `#ret-motif`), mot pour mot.
const motifsRetour = <String>[
  'Marchandises endommagées / périmées',
  "Erreur de saisie / d'article",
  'Non-conformité technique à la livraison',
];

const _etiquette = TextStyle(
  fontSize: AgriTypography.xs,
  fontWeight: FontWeight.bold,
);

Widget _erreur(String texte, Key cle) => Padding(
  padding: const EdgeInsets.only(top: AgriSpacing.xs),
  child: Text(
    texte,
    key: cle,
    style: const TextStyle(
      fontSize: AgriTypography.xs,
      color: AgriColors.errorDeep,
    ),
  ),
);

/// Ouvre « Retour Fournisseur » (`modal-return-purchase`). Retourne `true` si un retour a
/// été ÉCRIT (en attente d'envoi).
///
/// ⚠️⚠️ **LE POSTE DEMANDE, LE SERVEUR APPLIQUE.** La maquette annonce « Cette action
/// décrémentera automatiquement les stocks » : au poste c'est faux — il ne décrémente rien.
/// Le texte l'écrit autrement, et dit que le serveur choisit les lignes et peut refuser.
Future<bool> ouvrirRetourFournisseur({
  required BuildContext context,
  required AchatsRepository depot,
  required LigneAchat ligne,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleRetour(depot: depot, ligne: ligne),
  );
  return ok == true;
}

/// Ouvre « Ajouter un Remboursement » (`modal-ajouter-remboursement`). Retourne `true` si un
/// remboursement a été écrit.
Future<bool> ouvrirRemboursement({
  required BuildContext context,
  required AchatsRepository depot,
  required DonneesAchats donnees,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleRemboursement(depot: depot, donnees: donnees),
  );
  return ok == true;
}

class _ModaleRetour extends StatefulWidget {
  const _ModaleRetour({required this.depot, required this.ligne});

  final AchatsRepository depot;
  final LigneAchat ligne;

  @override
  State<_ModaleRetour> createState() => _ModaleRetourState();
}

class _ModaleRetourState extends State<_ModaleRetour> {
  String _motif = '';
  String? _erreurMotif;
  String? _refus;
  bool _envoi = false;

  Future<void> _confirmer() async {
    if (_motif.isEmpty) {
      // « Ce champ est obligatoire. » — le texte de la maquette (`invalid-feedback`).
      setState(() {
        _erreurMotif = 'Ce champ est obligatoire.';
        _refus = null;
      });
      return;
    }

    setState(() {
      _envoi = true;
      _erreurMotif = null;
      _refus = null;
    });

    try {
      await widget.depot.enregistrerRetour(
        achatId: widget.ligne.achat.id,
        motif: _motif,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaisieAchatRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `confirmReturnPurchase()` : le motif R4 sous « Motif » (`returnReason`), comme au web.
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.ligne.achat;

    return ModaleAgri(
      titre: 'Retour Fournisseur',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Contrôle de validation d'annulation d'achat",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Container(
            key: const Key('retour-avertissement'),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.errorBg,
              border: Border.all(
                color: AgriColors.errorDeep.withValues(alpha: 0.20),
              ),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Text(
              'ATTENTION : Cette action est définitive. Vous demandez '
              "l'annulation de l'achat du ${AchatsRepository.jour(a.purchaseDate)} "
              '— ${a.supplierName ?? '—'}, d’un montant de '
              '${AchatsRepository.montant(a.total)} FCFA. Le poste enregistre '
              'seulement la demande : à la synchronisation, c’est le SERVEUR qui '
              'choisit les lignes concernées, décrémente le stock (jamais sous '
              'zéro), contre-passe l’écriture d’achat et annule la part non '
              'payée de la dette. Il peut REFUSER (achat sans écriture '
              "d'origine, stock insuffisant, exercice clos) : son motif "
              'apparaîtra alors sur la ligne, mot pour mot.',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text("MOTIF DE L'ANNULATION / RETOUR", style: _etiquette),
          const SizedBox(height: AgriSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('retour-motif'),
            initialValue: _motif,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              color: AgriColors.onSurface,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Sélectionner un motif...'),
              ),
              for (final m in motifsRetour)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _motif = v ?? ''),
          ),
          if (_erreurMotif != null)
            _erreur(_erreurMotif!, const Key('retour-erreur-motif')),
          if (_refus != null) _erreur(_refus!, const Key('retour-refus')),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ElevatedButton(
          key: const Key('retour-confirmer'),
          onPressed: _envoi ? null : _confirmer,
          style: ElevatedButton.styleFrom(
            backgroundColor: AgriColors.errorRed,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
          ),
          child: const Text(
            'Confirmer le Retour',
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModaleRemboursement extends StatefulWidget {
  const _ModaleRemboursement({required this.depot, required this.donnees});

  final AchatsRepository depot;
  final DonneesAchats donnees;

  @override
  State<_ModaleRemboursement> createState() => _ModaleRemboursementState();
}

class _ModaleRemboursementState extends State<_ModaleRemboursement> {
  final _montant = TextEditingController();
  String _fournisseur = '';
  late String _compte;
  late DateTime _date;
  Map<String, String> _erreurs = const {};
  String? _refus;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _date = HeureBenin.aujourdhui();
    // La maquette ouvre « Compte de Trésorerie » sur sa première option.
    final comptes = widget.donnees.comptes;
    _compte = comptes.isEmpty ? '' : comptes.first.id;
  }

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final montant = double.tryParse(_montant.text.trim().replaceAll(',', '.'));
    final erreurs = <String, String>{
      if (_fournisseur.isEmpty) 'fournisseur': 'Ce champ est obligatoire.',
      if (montant == null) 'montant': 'Ce champ est obligatoire.',
      if (_compte.isEmpty) 'compte': 'Ce champ est obligatoire.',
    };
    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _refus = null;
      });
      return;
    }

    setState(() {
      _envoi = true;
      _erreurs = const {};
      _refus = null;
    });

    try {
      await widget.depot.enregistrerRemboursement(
        fournisseurId: _fournisseur,
        montant: montant!,
        date: _date,
        compteId: _compte,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaisieAchatRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `submitRefund()` : le motif R4 sous « Montant Remboursé » (`refundAmount`), comme au web.
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreurs = {'montant': e.motif};
      });
    }
  }

  Widget _bloc(String libelle, Widget champ, {String? erreur, Key? cle}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle, style: _etiquette),
            const SizedBox(height: AgriSpacing.xs),
            champ,
            if (erreur != null)
              _erreur(erreur, cle ?? Key('remb-erreur-$libelle')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;

    // Les fournisseurs actifs, plus ceux qui ont une créance ouverte alors qu'ils sont
    // archivés depuis : on rembourse aussi une fiche archivée.
    final options = <(String, String)>[
      for (final f in d.fournisseurs) (f.id, f.name),
      for (final c in d.creances)
        if (!d.fournisseurs.any((f) => f.id == c.supplierId))
          (c.supplierId, c.supplierName ?? '—'),
    ];

    return ModaleAgri(
      titre: 'Ajouter un Remboursement',
      largeur: LargeurModale.sm,
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloc(
            'Fournisseur *',
            DropdownButtonFormField<String>(
              key: const Key('remb-fournisseur'),
              initialValue: _fournisseur,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.onSurface,
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('-- Sélectionner --'),
                ),
                for (final (id, nom) in options)
                  DropdownMenuItem(
                    value: id,
                    child: Text(nom, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _fournisseur = v ?? ''),
            ),
            erreur: _erreurs['fournisseur'],
            cle: const Key('remb-erreur-fournisseur'),
          ),
          if (_fournisseur.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.md),
              child: Text(
                'Créance ouverte sur ce fournisseur : '
                '${AchatsRepository.montant(d.creanceNette(_fournisseur))} FCFA '
                '(remboursements en attente déduits).',
                key: const Key('remb-creance'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ),
          _bloc(
            'Montant Remboursé (FCFA) *',
            TextField(
              key: const Key('remb-montant'),
              controller: _montant,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: AgriTypography.sm),
              decoration: const InputDecoration(
                hintText: 'ex : 50000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            erreur: _erreurs['montant'],
            cle: const Key('remb-erreur-montant'),
          ),
          _bloc(
            'Date du Remboursement *',
            OutlinedButton(
              key: const Key('remb-date'),
              onPressed: () async {
                // Ticket EX6 (EF7) — calendrier borné au plus ancien exercice OUVERT connu (`min` du web).
                final premier = await widget.depot.premierJourSaisissable();
                if (!context.mounted) return;
                final dernier = HeureBenin.maintenant();
                final bornes = ExerciceDeSaisie.calendrier(
                  premier: premier,
                  repli: DateTime(2020),
                  dernier: dernier,
                  initial: _date,
                );
                final choisie = await showDatePicker(
                  context: context,
                  initialDate: bornes.initial,
                  firstDate: bornes.premier,
                  lastDate: dernier,
                );
                if (choisie != null) setState(() => _date = choisie);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(AchatsRepository.jour(_date)),
              ),
            ),
          ),
          _bloc(
            'Compte de Trésorerie',
            DropdownButtonFormField<String>(
              key: const Key('remb-compte'),
              initialValue: _compte.isEmpty ? null : _compte,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.onSurface,
              ),
              items: [
                for (final c in d.comptes)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _compte = v ?? ''),
            ),
            erreur: _erreurs['compte'],
            cle: const Key('remb-erreur-compte'),
          ),
          const Text(
            'Le poste enregistre seulement le remboursement : le serveur le '
            'plafonne à la créance ouverte, fait entrer l’argent en trésorerie '
            'et passe l’écriture. Il peut le refuser.',
            key: Key('remb-mention'),
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          if (_refus != null) _erreur(_refus!, const Key('remb-refus')),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('remb-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _envoi ? null : _valider,
        ),
      ],
    );
  }
}
