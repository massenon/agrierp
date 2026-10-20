import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'clients_creances_repository.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/widgets/toast_agri.dart';

/// Ce que « Nouvel Acompte » rend à l'écran une fois l'avance ÉCRITE en local : de quoi
/// émettre le reçu (jamais avant — un reçu pour une saisie perdue serait un faux).
class AcompteEnregistre {
  const AcompteEnregistre({
    required this.avance,
    required this.nomClient,
    required this.motif,
    required this.mode,
  });

  final CustomerAdvance avance;
  final String nomClient;
  final String motif;

  /// Libellé choisi (« MTN Mobile Money »…), tel que le reçu l'imprime.
  final String mode;
}

/// Ouvre « Nouvel Acompte » (`historique-avances.html`, `modal-add-advance`).
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.73) : l'avance est
/// écrite `pending` ; le serveur fait entrer l'argent en trésorerie (deux livres) et passe
/// l'écriture D 5xx / C 419. Le poste ne modifie aucun solde.
///
/// ⚠️ « Compte de Trésorerie » ne figure pas dans la maquette : le contrat serveur
/// l'exige (un acompte entre dans un compte précis). Même ajout que pour le règlement
/// fournisseur.
Future<AcompteEnregistre?> ouvrirNouvelAcompte({
  required BuildContext context,
  required ClientsCreancesRepository depot,
  required DonneesClients donnees,
}) {
  return afficherModale<AcompteEnregistre>(
    context: context,
    constructeur: (_) => _ModaleAcompte(depot: depot, donnees: donnees),
  );
}

/// Ouvre « Imputer un Acompte » (`modal-imputation`). [depart] présélectionne l'avance de
/// la ligne depuis laquelle la modale est ouverte. Retourne `true` si une imputation a été
/// écrite.
Future<bool> ouvrirImputation({
  required BuildContext context,
  required ClientsCreancesRepository depot,
  required DonneesClients donnees,
  LigneAvance? depart,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) =>
        _ModaleImputation(depot: depot, donnees: donnees, depart: depart),
  );
  return ok == true;
}

const _etiquette = TextStyle(
  fontSize: AgriTypography.xs,
  fontWeight: FontWeight.bold,
);

Widget _bloc(String libelle, Widget champ, {String? erreur}) => Padding(
  padding: const EdgeInsets.only(bottom: AgriSpacing.md),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle, style: _etiquette),
      const SizedBox(height: AgriSpacing.xs),
      champ,
      if (erreur != null)
        Padding(
          padding: const EdgeInsets.only(top: AgriSpacing.xs),
          child: Text(
            erreur,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.errorDeep,
            ),
          ),
        ),
    ],
  ),
);

Widget _liste({
  required Key cle,
  required String valeur,
  required List<DropdownMenuItem<String>> items,
  required ValueChanged<String> onChanged,
}) => DropdownButtonFormField<String>(
  key: cle,
  initialValue: valeur,
  isExpanded: true,
  isDense: true,
  decoration: const InputDecoration(
    border: OutlineInputBorder(),
    isDense: true,
  ),
  style: const TextStyle(
    fontSize: AgriTypography.xs,
    color: AgriColors.onSurface,
  ),
  items: items,
  onChanged: (v) => onChanged(v ?? ''),
);

String _montant(double valeur) => DocumentsAvances.formaterMontant(valeur);

class _ModaleAcompte extends StatefulWidget {
  const _ModaleAcompte({required this.depot, required this.donnees});

  final ClientsCreancesRepository depot;
  final DonneesClients donnees;

  @override
  State<_ModaleAcompte> createState() => _ModaleAcompteState();
}

class _ModaleAcompteState extends State<_ModaleAcompte> {
  final _motif = TextEditingController();
  final _montantSaisi = TextEditingController();
  String _client = '';
  String _compte = '';
  String _mode = ClientsCreancesRepository.modesPaiement.keys.first;
  Map<String, String> _erreurs = const {};
  String? _refus;
  bool _envoi = false;

  @override
  void dispose() {
    _motif.dispose();
    _montantSaisi.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    // « Ce champ est obligatoire. » — le texte de la maquette (`invalid-feedback`).
    final montant = double.tryParse(
      _montantSaisi.text.trim().replaceAll(',', '.'),
    );
    final erreurs = <String, String>{
      if (_client.isEmpty) 'client': 'Ce champ est obligatoire.',
      if (_motif.text.trim().isEmpty) 'motif': 'Ce champ est obligatoire.',
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
      final avance = await widget.depot.enregistrerAvance(
        clientId: _client,
        montant: montant!,
        compteId: _compte,
        motif: _motif.text,
        modePaiement: _mode,
      );
      if (!mounted) return;
      final nom = widget.donnees.clients
          .firstWhere((l) => l.client.id == _client)
          .client
          .name;
      Navigator.of(context).pop(
        AcompteEnregistre(
          avance: avance,
          nomClient: nom,
          motif: _motif.text.trim(),
          mode: _mode,
        ),
      );
    } on SaisieRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `HistoriqueAvances::save()` : motif R4 en toast d'erreur, modale ouverte.
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;
    const choisir = DropdownMenuItem(
      value: '',
      child: Text('-- Sélectionner --'),
    );

    return ModaleAgri(
      titre: 'Nouvel Acompte',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloc(
            'Client *',
            _liste(
              cle: const Key('acompte-client'),
              valeur: _client,
              items: [
                choisir,
                for (final l in d.clients)
                  DropdownMenuItem(
                    value: l.client.id,
                    child: Text(l.client.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _client = v),
            ),
            erreur: _erreurs['client'],
          ),
          _bloc(
            'Motif / Commande réservée *',
            TextField(
              key: const Key('acompte-motif'),
              controller: _motif,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                hintText: "ex : Réservation 50 poussins d'un jour",
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            erreur: _erreurs['motif'],
          ),
          _bloc(
            "Montant de l'Acompte (FCFA) *",
            TextField(
              key: const Key('acompte-montant'),
              controller: _montantSaisi,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                hintText: 'ex : 20000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            erreur: _erreurs['montant'],
          ),
          _bloc(
            'Mode de Paiement',
            _liste(
              cle: const Key('acompte-mode'),
              valeur: _mode,
              items: [
                for (final m in ClientsCreancesRepository.modesPaiement.keys)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _mode = v),
            ),
          ),
          _bloc(
            'Compte de Trésorerie *',
            _liste(
              cle: const Key('acompte-compte'),
              valeur: _compte,
              items: [
                choisir,
                for (final c in d.comptes)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _compte = v),
            ),
            erreur: _erreurs['compte'],
          ),
          if (_refus != null)
            Text(
              _refus!,
              key: const Key('acompte-refus'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoutonModalePrimaire(
          key: const Key('acompte-enregistrer'),
          libelle: 'Enregistrer et Délivrer le Reçu',
          onPressed: _envoi ? null : _valider,
        ),
      ],
    );
  }
}

class _ModaleImputation extends StatefulWidget {
  const _ModaleImputation({
    required this.depot,
    required this.donnees,
    required this.depart,
  });

  final ClientsCreancesRepository depot;
  final DonneesClients donnees;
  final LigneAvance? depart;

  @override
  State<_ModaleImputation> createState() => _ModaleImputationState();
}

class _ModaleImputationState extends State<_ModaleImputation> {
  String _avanceId = '';
  String _creanceId = '';
  String? _refus;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final d = widget.depart;
    if (d != null && _imputable(d)) _avanceId = d.avance.id;
  }

  /// Acomptes « en suspens » : un reste à imputer, une avance que le serveur n'a pas
  /// refusée.
  static bool _imputable(LigneAvance l) => !l.soldee && !l.refusee;

  LigneAvance? get _avance {
    for (final l in widget.donnees.avances) {
      if (l.avance.id == _avanceId) return l;
    }
    return null;
  }

  /// Créances du client de l'avance choisie, encore dues (net des imputations en
  /// attente).
  List<LigneCreance> get _creances {
    final a = _avance;
    if (a == null) return const [];
    return [
      for (final c in widget.donnees.creances)
        if (c.creance.customerId == a.avance.customerId && c.resteDu > 0) c,
    ];
  }

  LigneCreance? get _creance {
    for (final c in _creances) {
      if (c.creance.id == _creanceId) return c;
    }
    return null;
  }

  /// Ce que l'imputation portera : le plus petit du reste de l'avance et du solde de la
  /// créance, tous deux nets des imputations en attente — ce que le serveur appliquerait.
  double? get _montantImpute {
    final a = _avance;
    final c = _creance;
    if (a == null || c == null) return null;
    return a.soldeRestant < c.resteDu ? a.soldeRestant : c.resteDu;
  }

  Future<void> _valider() async {
    final a = _avance;
    final c = _creance;
    if (a == null) {
      setState(() => _refus = 'Veuillez choisir un acompte à affecter.');
      return;
    }
    if (c == null) {
      // Le texte de la maquette (`confirmImputation`).
      setState(() => _refus = 'Veuillez choisir une facture active.');
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
    });

    try {
      await widget.depot.imputerAvance(
        avanceId: a.avance.id,
        creanceId: c.creance.id,
        montant: _montantImpute!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaisieRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.motif;
      });
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `HistoriqueAvances::confirmImputation()` : motif R4 en toast d'erreur, modale ouverte.
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
    }
  }

  static String _initiales(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
    if (mots.isEmpty) return '?';
    return mots.take(2).map((m) => m[0].toUpperCase()).join();
  }

  static String _jour(DateTime? d) =>
      d == null ? '—' : DocumentsAvances.formaterJour(d);

  @override
  Widget build(BuildContext context) {
    final enSuspens = [
      for (final l in widget.donnees.avances)
        if (_imputable(l)) l,
    ];
    final a = _avance;
    final impute = _montantImpute;

    return ModaleAgri(
      titre: 'Imputer un Acompte',
      largeur: LargeurModale.lg,
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ACOMPTES EN SUSPENS',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.outline,
            ),
          ),
          const SizedBox(height: AgriSpacing.sm),
          if (enSuspens.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: AgriSpacing.md),
              child: Text(
                '— Aucun acompte à imputer —',
                key: Key('imputation-aucun'),
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ),
          for (final l in enSuspens)
            Container(
              key: Key('suspens-${l.avance.id}'),
              margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
              padding: const EdgeInsets.all(AgriSpacing.sm),
              decoration: BoxDecoration(
                color: _avanceId == l.avance.id
                    ? AgriColors.brandEmerald.withValues(alpha: 0.06)
                    : AgriColors.surfaceCard,
                border: Border.all(color: AgriColors.outlineVariant),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AgriColors.brandEmerald,
                    child: Text(
                      _initiales(l.nomClient),
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.nomClient,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: FontWeight.bold,
                            color: AgriColors.brandForest,
                          ),
                        ),
                        Text(
                          '${_montant(l.soldeRestant)} FCFA disponible — '
                          '${_jour(l.avance.advanceDate)}',
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: FontWeight.bold,
                            color: AgriColors.brandEmerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    key: Key('affecter-${l.avance.id}'),
                    onPressed: () => setState(() {
                      _avanceId = l.avance.id;
                      _creanceId = '';
                      _refus = null;
                    }),
                    icon: const Icon(SymbolesAgri.link, size: 14),
                    label: const Text(
                      'Affecter',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgriColors.brandEmerald,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AgriSpacing.sm),
          const Row(
            children: [
              Icon(SymbolesAgri.payments, size: 18, color: AgriColors.brandForest),
              SizedBox(width: AgriSpacing.xs),
              Text(
                "IMPUTER L'ACOMPTE",
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              children: [
                _ligneResume(
                  'Acompte sélectionné',
                  a?.nomClient ?? '—',
                  const Key('imputation-client'),
                ),
                const SizedBox(height: 4),
                _ligneResume(
                  "Valeur de l'acompte",
                  a == null ? '—' : '${_montant(a.soldeRestant)} FCFA',
                  const Key('imputation-solde'),
                  couleur: AgriColors.brandEmerald,
                ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          _bloc(
            'Choix Facture de Vente',
            _liste(
              cle: const Key('imputation-creance'),
              valeur: _creances.any((c) => c.creance.id == _creanceId)
                  ? _creanceId
                  : '',
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Choisir une facture active...'),
                ),
                for (final c in _creances)
                  DropdownMenuItem(
                    value: c.creance.id,
                    // ⚠️ Pas de numéro de facture : le poste n'en détient aucun pour une
                    // créance servie (D9). L'échéance et le solde NET identifient la ligne.
                    child: Text(
                      'Créance — échéance ${_jour(c.creance.dueDate)} — '
                      'Solde ${_montant(c.resteDu)} FCFA',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _creanceId = v;
                _refus = null;
              }),
            ),
          ),
          if (impute != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
              child: Text(
                'Montant imputé : ${_montant(impute)} FCFA (le plus petit du '
                "reste de l'acompte et du solde de la facture, imputations en "
                'attente déduites).',
                key: const Key('imputation-montant'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ),
          if (_refus != null)
            Text(
              _refus!,
              key: const Key('imputation-refus'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('imputation-valider'),
          libelle: "Valider l'Imputation",
          onPressed: _envoi ? null : _valider,
        ),
      ],
    );
  }

  Widget _ligneResume(
    String libelle,
    String valeur,
    Key cle, {
    Color couleur = AgriColors.onSurface,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
      Flexible(
        child: Text(
          valeur,
          key: cle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      ),
    ],
  );
}
