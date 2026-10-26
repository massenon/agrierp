import 'package:flutter/material.dart';

import '../../core/erreurs/message_erreur.dart';
import '../../core/export/pdf_recu.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/champs_date_agri.dart';
import 'attestations_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Livraison d'une attestation : voir [LivraisonPdf], partagée avec la fiche
/// sujet. Conservée sous ce nom pour les appelants existants.
class LivraisonAttestation {
  const LivraisonAttestation._();

  static Future<String> enregistrer(
    PdfAttestation pdf, {
    DateTime? maintenant,
  }) => LivraisonPdf.enregistrer(pdf, maintenant: maintenant);

  static Future<void> imprimer(PdfAttestation pdf) =>
      LivraisonPdf.imprimer(pdf);
}

/// `prototype_html/rh-attestations.html` → onglet « Attestations » du hub
/// Personnel & Stages.
///
/// ⚠️⚠️ **LE PDF EST PRODUIT ET COMPTÉ PAR LE SERVEUR** (voir [ClientAttestations]) :
/// l'aperçu est un confort calculé au poste avec les mêmes règles, le document
/// officiel vient du serveur — sa trace d'audit aussi. Générer exige donc le
/// réseau, et le dit.
///
/// ⚠️ **ÉCARTS ASSUMÉS, TOUS DE LARAVEL** :
///  * pas de cases « Filigrane / En-tête / Signature / Cachet » ni de choix de
///    format : le PDF du serveur n'en tient AUCUN compte (la table les porte, la
///    page web ne les propose pas). Des options qui ne changent rien seraient des
///    promesses fausses ;
///  * pour un stagiaire, « Établissement » remplace « Poste » et le type de contrat
///    n'est pas demandé ;
///  * les libellés sont ACCENTUÉS : le prototype n'accentue aucun mot de cette
///    page (« Generer », « Modeles »), la page web les rétablit.
class AttestationsVue extends StatefulWidget {
  const AttestationsVue({
    super.key,
    required this.depot,
    required this.enregistrer,
    required this.imprimer,
    this.maintenant,
  });

  final AttestationsRepository depot;

  /// Écrit le PDF, rend son chemin.
  final Future<String> Function(PdfAttestation) enregistrer;

  /// Ouvre la boîte d'impression.
  final Future<void> Function(PdfAttestation) imprimer;

  /// Date du jour — fixée par les tests.
  final DateTime? maintenant;

  @override
  State<AttestationsVue> createState() => _AttestationsVueState();
}

class _AttestationsVueState extends State<AttestationsVue> {
  static const onglets = <(String, String, IconData)>[
    ('generer', 'Générer une Attestation', SymbolesAgri.description),
    ('modeles', 'Personnaliser les Modèles', SymbolesAgri.edit_note),
  ];

  // En-tête du certificat — celui de la page web (RCCM de la directive officielle,
  // pas l'IFU de démonstration du prototype).
  static const _ferme = 'FERME ÉCOLE OLOUWACHEGOUN';
  static const _sousActivites =
      'Production Animale | Production Végétale | Transformation Agro-alimentaire';
  static const _sousActivites2 =
      'Fabrication de Cages Galvanisées | Formation Agricole | Suivi-Appuis et Conseils';
  static const _rccm = 'RCCM : RB/PNO/22 A 33870';

  // ATT-1 — 3 signataires (décision client conforme au vrai modèle PDF).
  static const _sig1Titre = "L'Examinateur";
  static const _sig1Nom = 'SOGNIGBE Gbédjinou Serge Bruno';
  static const _sig1Sous = 'Chef Cellule Communale\nATDA Pôle 6 (Plateau)';
  static const _sig2Titre = 'Président du Jury';
  static const _sig2Nom = 'Elisée Kocou HOUNKPONOU';
  static const _sig2Sous = 'Président FN-CCPB';
  static const _sig3Titre = 'Le Directeur Général';
  static const _sig3Nom = 'Hassimiyou O. OLOUKOUNLE';
  static const _sig3Sous = 'Directeur Général FEO';

  // ATT-1 — domaines de formation cochables (identique à AttestationService::DOMAINES).
  static const _domainesDisponibles = <String, String>{
    'maraichage': 'Maraîchage et cultures légumières',
    'elevage': 'Élevage (Lapins, Porcs, Poulets)',
    'rations': 'Fabrication de rations alimentaires',
    'gestion': 'Gestion agricole',
  };

  // Mois en français pour la date longue (décision ATT-1).
  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  String _onglet = 'generer';
  String _type = 'employe';

  List<PersonneAttestation> _personnes = const [];
  String _personneId = '';
  String _contrat = AttestationsRepository.contrats.first;
  // ATT-1 — civilité (M. / Mme), conditionne l'accord grammatical.
  String _civilite = 'M.';

  final _debut = TextEditingController();
  final _fin = TextEditingController();
  final _note = TextEditingController();
  // ATT-1 — champs spécifiques au stagiaire.
  final _appreciation = TextEditingController();
  final _naissance = TextEditingController();
  final _lieuNaissance = TextEditingController();
  final Set<String> _domaines = {};

  // ATT-1 — signataires éditables par attestation (pré-remplis depuis le modèle).
  final _sig1TitreCtrl = TextEditingController(text: _sig1Titre);
  final _sig1NomCtrl = TextEditingController(text: _sig1Nom);
  final _sig2TitreCtrl = TextEditingController(text: _sig2Titre);
  final _sig2NomCtrl = TextEditingController(text: _sig2Nom);
  final _sig3TitreCtrl = TextEditingController(text: _sig3Titre);
  final _sig3NomCtrl = TextEditingController(text: _sig3Nom);

  final _modeles = <String, TextEditingController>{
    'employe': TextEditingController(),
    'stagiaire': TextEditingController(),
  };
  final _modelesRecus = <String, bool>{'employe': false, 'stagiaire': false};

  bool _chargee = false;
  bool _enCours = false;

  /// Retour de la dernière action, par zone : (réussi, message).
  (bool, String)? _retour;
  Map<String, String> _erreurs = const {};

  /// Dernier PDF produit, proposé à l'impression.
  PdfAttestation? _dernierPdf;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _debut.dispose();
    _fin.dispose();
    _note.dispose();
    _appreciation.dispose();
    _naissance.dispose();
    _lieuNaissance.dispose();
    _sig1TitreCtrl.dispose();
    _sig1NomCtrl.dispose();
    _sig2TitreCtrl.dispose();
    _sig2NomCtrl.dispose();
    _sig3TitreCtrl.dispose();
    _sig3NomCtrl.dispose();
    for (final c in _modeles.values) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _aujourdhui => widget.maintenant ?? HeureBenin.maintenant();

  Future<void> _charger() async {
    final personnes = await widget.depot.personnes(_type);
    for (final t in AttestationsRepository.types) {
      final texte = await widget.depot.modele(t);
      _modelesRecus[t] = texte != null;
      if (texte != null && _modeles[t]!.text.isEmpty) _modeles[t]!.text = texte;
    }
    if (!mounted) return;
    setState(() {
      _personnes = personnes;
      _chargee = true;
    });
  }

  PersonneAttestation? get _personne {
    for (final x in _personnes) {
      if (x.id == _personneId) return x;
    }
    return null;
  }

  /// `jj/mm/aaaa` → date, `null` si vide ou invalide.
  static DateTime? _lire(String texte) {
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$').firstMatch(texte);
    if (m == null) return null;
    final j = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final a = int.parse(m.group(3)!);
    final d = DateTime(a, mo, j);
    // `DateTime(2026, 2, 31)` déborde sur mars : on refuse plutôt que de décaler.
    return (d.year == a && d.month == mo && d.day == j) ? d : null;
  }

  static String _ecrire(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _changerType(String type) async {
    setState(() {
      _type = type;
      _personneId = '';
      _debut.clear();
      _fin.clear();
      _appreciation.clear();
      _naissance.clear();
      _lieuNaissance.clear();
      _domaines.clear();
      _retour = null;
      _erreurs = const {};
    });
    await _charger();
  }

  void _choisir(String id) {
    final x = _personnes.firstWhere((e) => e.id == id);
    setState(() {
      _personneId = id;
      // Comme la page web : la personne préremplit les dates.
      _debut.text = _ecrire(x.debut);
      _fin.text = _ecrire(x.fin);
      // ATT-1 : pré-remplissage de la naissance et civilité pour un stagiaire.
      if (_type == 'stagiaire') {
        _naissance.text = _ecrire(x.birthDate);
        _lieuNaissance.text = x.birthPlace ?? '';
        _civilite = x.civilite;
      }
    });
  }

  Future<void> _generer() async {
    if (_enCours) return;

    final personne = _personne;
    if (personne == null) {
      setState(() {
        _erreurs = {'personne': 'Ce champ est obligatoire.'};
        _retour = null;
      });
      return;
    }

    final erreurs = <String, String>{};
    if (_debut.text.trim().isNotEmpty && _lire(_debut.text) == null) {
      erreurs['debut'] = 'Date invalide (jj/mm/aaaa).';
    }
    if (_fin.text.trim().isNotEmpty && _lire(_fin.text) == null) {
      erreurs['fin'] = 'Date invalide (jj/mm/aaaa).';
    }
    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _retour = null;
      });
      return;
    }

    setState(() {
      _enCours = true;
      _erreurs = const {};
      _retour = null;
      _dernierPdf = null;
    });

    try {
      final pdf = await widget.depot.generer(
        type: _type,
        personne: personne,
        contrat: _contrat,
        debut: _lire(_debut.text),
        fin: _lire(_fin.text),
        note: _note.text,
        domaines: _domaines.toList(),
        appreciation: _appreciation.text,
        birthDate: _lire(_naissance.text),
        birthPlace: _lieuNaissance.text,
        civilite: _civilite,
        sig1Titre: _sig1TitreCtrl.text.trim().isEmpty ? null : _sig1TitreCtrl.text,
        sig1Nom: _sig1NomCtrl.text.trim().isEmpty ? null : _sig1NomCtrl.text,
        sig2Titre: _sig2TitreCtrl.text.trim().isEmpty ? null : _sig2TitreCtrl.text,
        sig2Nom: _sig2NomCtrl.text.trim().isEmpty ? null : _sig2NomCtrl.text,
        sig3Titre: _sig3TitreCtrl.text.trim().isEmpty ? null : _sig3TitreCtrl.text,
        sig3Nom: _sig3NomCtrl.text.trim().isEmpty ? null : _sig3NomCtrl.text,
      );
      final chemin = await widget.enregistrer(pdf);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _dernierPdf = pdf;
        _retour = (true, 'Attestation enregistrée : $chemin');
      });
    } on EchecAttestation catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = e.champs;
        _retour = (false, e.message);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _retour = (false, messageEcritureFichier(e)); // U5 : pas d'exception brute
      });
    }
  }

  Future<void> _enregistrerModele(String type) async {
    if (_enCours) return;
    final texte = _modeles[type]!.text;

    if (texte.trim().isEmpty) {
      setState(() {
        _erreurs = {'modele-$type': 'Ce champ est obligatoire.'};
        _retour = null;
      });
      return;
    }

    setState(() {
      _enCours = true;
      _erreurs = const {};
      _retour = null;
    });

    try {
      await widget.depot.enregistrerModele(type, texte);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _modelesRecus[type] = true;
        _retour = (true, 'Modèle enregistré avec succès.');
      });
    } on EchecAttestation catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = {for (final c in e.champs.entries) 'modele-$type': c.value};
        _retour = (false, e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_chargee) return const Center(child: CircularProgressIndicator());

    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(large),
        const SizedBox(height: AgriSpacing.lg),
        _barreOnglets(),
        const SizedBox(height: AgriSpacing.lg),
        if (_onglet == 'generer') _generer_(large) else _modelesOnglet(large),
      ],
    );
  }

  BoxDecoration _carte({Color? fond, Color? bordure}) => BoxDecoration(
    color: fond ?? AgriColors.surfaceCard,
    border: Border.all(color: bordure ?? AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

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
            const Icon(
              SymbolesAgri.workspace_premium,
              size: 26,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Attestations de Travail & de Stage',
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
        const Text(
          'Personnalisez les modèles officiels, puis générez et téléchargez les '
          'attestations certifiées au format PDF.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Row(
      children: [
        for (final (cle, titre, _) in onglets)
          InkWell(
            key: Key('onglet-attestations-$titre'),
            onTap: () => setState(() {
              _onglet = cle;
              _retour = null;
              _erreurs = const {};
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: _onglet == cle
                        ? AgriColors.brandEmerald
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: _onglet == cle
                      ? AgriColors.brandEmerald
                      : AgriColors.outline,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ── Onglet 1 : Générer une Attestation ───────────────────────────────────

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  static const _etiquette = StylesChampsAgri.etiquetteFormulaire;

  Widget _generer_(bool large) {
    final formulaire = _carteFormulaire();
    final apercu = _carteApercu();

    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 45, child: formulaire),
              const SizedBox(width: AgriSpacing.md),
              Expanded(flex: 55, child: apercu),
            ],
          )
        : Column(
            children: [
              formulaire,
              const SizedBox(height: AgriSpacing.md),
              apercu,
            ],
          );
  }

  Widget _erreur(String champ) {
    final e = _erreurs[champ];
    if (e == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AgriSpacing.xs),
      child: Text(
        e,
        key: Key('erreur-$champ'),
        style: const TextStyle(fontSize: 11, color: AgriColors.errorRed),
      ),
    );
  }

  Widget _carteFormulaire() {
    final employe = _type == 'employe';
    final x = _personne;

    return Container(
      key: const Key('att-formulaire'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1. Choix de la Fiche'.toUpperCase(), style: _etiquette),
          const SizedBox(height: AgriSpacing.md),
          Row(
            children: [
              Expanded(
                child: _boutonType('employe', SymbolesAgri.badge, 'Employé Permanent'),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _boutonType(
                  'stagiaire',
                  SymbolesAgri.school,
                  'Stagiaire en Formation',
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          Text('Nom de la personne *'.toUpperCase(), style: _etiquette),
          const SizedBox(height: AgriSpacing.xs),
          _liste(
            cle: const Key('att-personne'),
            valeur: _personneId,
            erreur: _erreurs.containsKey('personne'),
            elements: [
              const DropdownMenuItem(
                value: '',
                child: Text('-- Sélectionner --'),
              ),
              for (final e in _personnes)
                DropdownMenuItem(value: e.id, child: Text(e.libelle)),
            ],
            surChoix: (v) => v == null || v.isEmpty
                ? setState(() {
                    _personneId = '';
                    _debut.clear();
                    _fin.clear();
                  })
                : _choisir(v),
          ),
          _erreur('personne'),
          const SizedBox(height: AgriSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (employe ? 'Poste' : 'Établissement').toUpperCase(),
                      style: _etiquette,
                    ),
                    const SizedBox(height: AgriSpacing.xs),
                    Container(
                      key: const Key('att-role'),
                      height: 44,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgriSpacing.md,
                      ),
                      decoration: _carte(fond: AgriColors.surfaceZebra),
                      child: Text(
                        (employe ? x?.poste : x?.etablissement) ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AgriTypography.sm),
                      ),
                    ),
                  ],
                ),
              ),
              if (employe) ...[
                const SizedBox(width: AgriSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type de Contrat'.toUpperCase(), style: _etiquette),
                      const SizedBox(height: AgriSpacing.xs),
                      _liste(
                        cle: const Key('att-contrat'),
                        valeur: _contrat,
                        elements: [
                          for (final c in AttestationsRepository.contrats)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        surChoix: (v) =>
                            setState(() => _contrat = v ?? _contrat),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champDate(
                  'Date de Début',
                  _debut,
                  'att-debut',
                  'debut',
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champDate('Date de Fin', _fin, 'att-fin', 'fin'),
              ),
            ],
          ),
          // ATT-1 — champs naissance + domaines + appréciation (stagiaire seulement).
          if (!employe) ...[
            const SizedBox(height: AgriSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _champDate(
                    'Date de Naissance',
                    _naissance,
                    'att-naissance',
                    'naissance',
                  ),
                ),
                const SizedBox(width: AgriSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lieu de Naissance'.toUpperCase(), style: _etiquette),
                      const SizedBox(height: AgriSpacing.xs),
                      TextField(
                        key: const Key('att-lieu-naissance'),
                        controller: _lieuNaissance,
                        onChanged: (_) => setState(() {}),
                        style: StylesChampsAgri.valeurFormulaire,
                        decoration: _decor(
                          'Ex : Cotonou',
                          hauteurFixe: AgriChamps.hauteurFormulaire,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.md),
            Text('Domaines de Formation'.toUpperCase(), style: _etiquette),
            const SizedBox(height: AgriSpacing.xs),
            Container(
              padding: const EdgeInsets.all(AgriSpacing.sm),
              decoration: _carte(fond: AgriColors.surfaceZebra),
              child: Column(
                children: [
                  for (final entry in _domainesDisponibles.entries)
                    InkWell(
                      key: Key('att-domaine-${entry.key}'),
                      onTap: () => setState(() {
                        if (_domaines.contains(entry.key)) {
                          _domaines.remove(entry.key);
                        } else {
                          _domaines.add(entry.key);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AgriSpacing.xs / 2,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: _domaines.contains(entry.key),
                                onChanged: (_) => setState(() {
                                  if (_domaines.contains(entry.key)) {
                                    _domaines.remove(entry.key);
                                  } else {
                                    _domaines.add(entry.key);
                                  }
                                }),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                activeColor: AgriColors.brandEmerald,
                              ),
                            ),
                            const SizedBox(width: AgriSpacing.sm),
                            Flexible(
                              child: Text(
                                entry.value,
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AgriSpacing.md),
            Text('Appréciation'.toUpperCase(), style: _etiquette),
            const SizedBox(height: AgriSpacing.xs),
            TextField(
              key: const Key('att-appreciation'),
              controller: _appreciation,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: AgriTypography.sm),
              decoration: _decor(
                "sa ponctualité, son esprit d'initiative, sa capacité d'adaptation…",
              ),
            ),
          ],
          const SizedBox(height: AgriSpacing.md),
          Text(
            "Note d'Évaluation (optionnel)".toUpperCase(),
            style: _etiquette,
          ),
          const SizedBox(height: AgriSpacing.xs),
          TextField(
            key: const Key('att-note'),
            controller: _note,
            minLines: 3,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: AgriTypography.sm),
            decoration: _decor('Assiduité, rigueur, compétences acquises...'),
          ),
          const SizedBox(height: AgriSpacing.md),
          FilledButton.icon(
            key: const Key('att-generer'),
            onPressed: _enCours ? null : _generer,
            icon: const Icon(SymbolesAgri.description, size: 18),
            label: const Text(
              "Générer l'Attestation",
              style: TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
          ),
          if (_retour != null && _onglet == 'generer') ...[
            const SizedBox(height: AgriSpacing.md),
            _bandeau(_retour!.$1, _retour!.$2),
            if (_dernierPdf != null) ...[
              const SizedBox(height: AgriSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('att-imprimer'),
                  onPressed: () => widget.imprimer(_dernierPdf!),
                  icon: const Icon(SymbolesAgri.print, size: 18),
                  label: const Text('Imprimer'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  InputDecoration _decor(
    String aide, {
    bool erreur = false,
    Widget? fin,
    double? hauteurFixe,
  }) => InputDecoration(
        hintText: aide,
        hintStyle: const TextStyle(
          fontSize: AgriTypography.sm,
          color: AgriColors.outline,
        ),
        suffixIcon: fin,
        suffixIconConstraints: const BoxConstraints(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: hauteurFixe == null ? 14 : (hauteurFixe - AgriTypography.smInterligne) / 2,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: BorderSide(
            color: erreur ? AgriColors.errorRed : AgriColors.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: BorderSide(
            color: erreur ? AgriColors.errorRed : AgriColors.brandEmerald,
          ),
        ),
      );

  Widget _champDate(
    String libelle,
    TextEditingController controleur,
    String cle,
    String champ,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle.toUpperCase(), style: _etiquette),
      const SizedBox(height: AgriSpacing.xs),
      TextField(
        key: Key(cle),
        controller: controleur,
        onChanged: (_) => setState(() {}),
        style: StylesChampsAgri.valeurFormulaire,
        decoration: _decor(
          'jj/mm/aaaa',
          // `h-11` : 44 px EXACTS (ticket MP1) — interligne de `text-sm` + marges verticales de part et d'autre.
          hauteurFixe: AgriChamps.hauteurFormulaire,
          erreur: _erreurs.containsKey(champ),
          fin: IconButton(
            key: Key('$cle-calendrier'),
            // Sans zone de toucher de 48 px, qui porterait le champ à 48 px au lieu des 44 px de `h-11`.
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            icon: const Icon(SymbolesAgri.calendar_today, size: AgriChamps.iconeCalendrier),
            onPressed: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _lire(controleur.text) ?? _aujourdhui,
                firstDate: DateTime(1990),
                lastDate: DateTime(2100),
              );
              if (choisie != null) {
                setState(() => controleur.text = _ecrire(choisie));
              }
            },
          ),
        ),
      ),
      _erreur(champ),
    ],
  );

  Widget _liste({
    required Key cle,
    required String valeur,
    required List<DropdownMenuItem<String>> elements,
    required void Function(String?) surChoix,
    bool erreur = false,
  }) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(
        color: erreur ? AgriColors.errorRed : AgriColors.outlineVariant,
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: cle,
        value: valeur,
        isExpanded: true,
        // ⚠️ Le menu déroulant ne reprend pas le style du thème : sans cette
        // base il retombe sur la police par défaut du moteur.
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: AgriTypography.sm,
          color: AgriColors.onSurface,
        ),
        items: elements,
        onChanged: surChoix,
      ),
    ),
  );

  Widget _boutonType(String type, IconData icone, String libelle) {
    final actif = _type == type;

    return InkWell(
      key: Key('att-type-$type'),
      onTap: actif ? null : () => _changerType(type),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: actif ? AgriColors.brandEmerald.withValues(alpha: 0.05) : null,
          border: Border.all(
            width: 2,
            color: actif ? AgriColors.brandEmerald : AgriColors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          children: [
            Icon(
              icone,
              size: 24,
              color: actif ? AgriColors.brandForest : AgriColors.outline,
            ),
            const SizedBox(height: AgriSpacing.xs),
            Text(
              libelle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: actif ? AgriColors.brandForest : AgriColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Aperçu du certificat ──────────────────────────────────────────────────

  String _dateLongue(DateTime d) =>
      '${d.day} ${_mois[d.month - 1]} ${d.year}';

  Widget _carteApercu() {
    final stagiaire = _type == 'stagiaire';
    final titre = stagiaire ? 'Attestation de Formation' : 'Attestation de Travail';
    final x = _personne;
    final modele = _modeles[_type]!.text;

    String? corps;
    if (x != null && _modelesRecus[_type]! && modele.isNotEmpty) {
      corps = AttestationsRepository.apercu(
        modele: modele,
        type: _type,
        personne: x,
        contrat: _contrat,
        debut: _lire(_debut.text),
        fin: _lire(_fin.text),
        birthDate: _lire(_naissance.text),
        birthPlace: _lieuNaissance.text,
        civilite: _civilite,
      );
    }

    const mute = TextStyle(
      fontSize: AgriTypography.xs,
      fontStyle: FontStyle.italic,
      color: AgriColors.outline,
    );

    return Container(
      key: const Key('att-apercu'),
      constraints: const BoxConstraints(minHeight: 480),
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: _carte(),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: const Opacity(
                  opacity: 0.05,
                  child: Icon(SymbolesAgri.agriculture, size: 220),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── En-tête : logo | ferme + activités + RCCM | lieu-date ───
              Container(
                padding: const EdgeInsets.only(bottom: AgriSpacing.md),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(width: 2, color: AgriColors.brandForest),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          SymbolesAgri.agriculture,
                          size: 36,
                          color: AgriColors.brandEmerald,
                        ),
                        const SizedBox(width: AgriSpacing.sm),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ferme,
                                style: TextStyle(
                                  fontSize: AgriTypography.sm,
                                  fontWeight: FontWeight.w900,
                                  color: AgriColors.brandForest,
                                ),
                              ),
                              Text(
                                _sousActivites,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: AgriColors.outline,
                                ),
                              ),
                              Text(
                                _sousActivites2,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: AgriColors.outline,
                                ),
                              ),
                              Text(
                                _rccm,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: AgriColors.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'ATTAN - ÉWÉ, le ${_dateLongue(_aujourdhui)}',
                          key: const Key('att-apercu-lieu-date'),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: AgriTypography.gras,
                            color: AgriColors.outline,
                          ),
                        ),
                      ],
                    ),
                    if (stagiaire) ...[
                      const SizedBox(height: AgriSpacing.xs),
                      const Text(
                        'N°—/FEO/DG',
                        key: Key('att-apercu-numero'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.brandForest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              // ─── Titre centré souligné ───
              Text(
                titre.toUpperCase(),
                key: const Key('att-apercu-titre'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  letterSpacing: 0.8,
                  color: AgriColors.brandForest,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
              // ─── Corps ───
              if (corps != null)
                Text(
                  corps,
                  key: const Key('att-apercu-corps'),
                  textAlign: TextAlign.justify,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    height: 1.6,
                  ),
                )
              else
                Text(
                  !_modelesRecus[_type]!
                      ? 'Modèle pas encore reçu du serveur — synchronisez.'
                      : "Sélectionnez une personne pour prévisualiser l'attestation.",
                  key: const Key('att-apercu-vide'),
                  style: mute,
                ),
              // ─── Domaines (stagiaire) ───
              if (stagiaire && _domaines.isNotEmpty) ...[
                const SizedBox(height: AgriSpacing.sm),
                for (final cle in _domaines)
                  if (_domainesDisponibles.containsKey(cle))
                    Text(
                      '➢ ${_domainesDisponibles[cle]} ;',
                      key: Key('att-apercu-domaine-$cle'),
                      style: const TextStyle(fontSize: 10),
                    ),
              ],
              // ─── Appréciation (stagiaire) ───
              if (stagiaire && _appreciation.text.trim().isNotEmpty &&
                  x != null) ...[
                const SizedBox(height: AgriSpacing.sm),
                Text(
                  "Au cours de sa formation, ${x.libelle} s'est distingué(e) "
                  'par ${_appreciation.text}.',
                  key: const Key('att-apercu-appreciation'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              // ─── Note ───
              if (_note.text.trim().isNotEmpty) ...[
                const SizedBox(height: AgriSpacing.md),
                Text(
                  _note.text,
                  key: const Key('att-apercu-note'),
                  style: mute,
                ),
              ],
              const SizedBox(height: AgriSpacing.sm),
              // ─── Formule de clôture ───
              const Text(
                'En foi de quoi, la présente attestation lui est délivrée '
                'pour servir et valoir ce que de droit.',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: AgriSpacing.lg),
              // ─── 3 blocs de signature (ATT-1) ───
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _blocSignature(_sig1Titre, _sig1Nom, _sig1Sous)),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: _blocSignature(_sig2Titre, _sig2Nom, _sig2Sous)),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: _blocSignature(_sig3Titre, _sig3Nom, _sig3Sous)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _blocSignature(String titre, String nom, String sousTitre) =>
      Column(
        children: [
          Text(
            titre.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          const SizedBox(height: AgriSpacing.lg),
          Container(
            width: double.infinity,
            height: 1,
            color: AgriColors.outlineVariant,
          ),
          const SizedBox(height: AgriSpacing.xs),
          Text(
            nom,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          Text(
            sousTitre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 7.5,
              color: AgriColors.outline,
            ),
          ),
        ],
      );

  Widget _bandeau(bool reussi, String message) {
    final couleur = reussi ? AgriColors.brandEmerald : AgriColors.errorRed;

    return Container(
      key: Key(reussi ? 'att-reussi' : 'att-echec'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: _carte(
        fond: couleur.withValues(alpha: 0.10),
        bordure: couleur.withValues(alpha: 0.30),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reussi ? SymbolesAgri.check_circle : SymbolesAgri.error,
            size: 18,
            color: couleur,
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 2 : Personnaliser les Modèles ─────────────────────────────────

  Widget _modelesOnglet(bool large) {
    final employe = _carteModele(
      'employe',
      SymbolesAgri.badge,
      'Modèle - Attestation de Travail (Employé)',
      'Balises disponibles : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]',
    );
    final stagiaire = _carteModele(
      'stagiaire',
      SymbolesAgri.school,
      'Modèle - Attestation de Stage (Stagiaire)',
      'Balises disponibles : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_NAISSANCE], [LIEU_NAISSANCE], '
          '[DATE_DEBUT], [DATE_FIN]',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        large
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: employe),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(child: stagiaire),
                ],
              )
            : Column(
                children: [
                  employe,
                  const SizedBox(height: AgriSpacing.md),
                  stagiaire,
                ],
              ),
        if (_retour != null) ...[
          const SizedBox(height: AgriSpacing.md),
          _bandeau(_retour!.$1, _retour!.$2),
        ],
      ],
    );
  }

  Widget _carteModele(
    String type,
    IconData icone,
    String titre,
    String balises,
  ) => Container(
    key: Key('att-modele-$type'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icone, size: 18, color: AgriColors.brandForest),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                titre.toUpperCase(),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        Text('Texte du certificat'.toUpperCase(), style: _etiquette),
        const SizedBox(height: AgriSpacing.xs),
        if (!_modelesRecus[type]!)
          const Padding(
            padding: EdgeInsets.only(bottom: AgriSpacing.xs),
            child: Text(
              'Modèle pas encore reçu du serveur — synchronisez.',
              key: Key('att-modele-absent'),
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            ),
          ),
        TextField(
          key: Key('att-texte-$type'),
          controller: _modeles[type],
          minLines: 6,
          maxLines: 6,
          style: const TextStyle(fontSize: AgriTypography.xs),
          decoration: _decor('', erreur: _erreurs.containsKey('modele-$type')),
        ),
        _erreur('modele-$type'),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          balises,
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        FilledButton(
          key: Key('att-enregistrer-$type'),
          onPressed: _enCours ? null : () => _enregistrerModele(type),
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
            padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
          ),
          child: const Text(
            'Enregistrer ce Modèle',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
      ],
    ),
  );
}
