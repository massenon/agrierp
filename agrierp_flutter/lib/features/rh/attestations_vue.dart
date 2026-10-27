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
/// ⚠️⚠️ **LE POSTE FABRIQUE LUI-MÊME LE PDF** (ATT-3, voir [AttestationsRepository.produire]) :
/// hors ligne comprise. Le serveur attribue le numéro et garde la trace d'audit : l'émission lui est
/// déclarée à la génération, ou mise en file (numéro vide sur le document) et déclarée à la
/// synchronisation suivante.
///
/// ⚠️ **ÉCARTS ASSUMÉS, TOUS DE LARAVEL** :
///  * pas de cases « Filigrane / En-tête / Signature / Cachet » ni de choix de
///    format : le PDF n'en tient AUCUN compte (la table les porte, la
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

  // En-tête du certificat — celui du modèle officiel (config/attestation.php du serveur).
  static const _ferme = 'FERME ÉCOLE OLOUWACHEGOUN';
  static const _activites =
      'Production Animale | Production Végétale | Transformation Agro-alimentaire| Fabrication de Cages '
      'Galvanisées | Formation Agricole | Suivi-Appuis et Conseils';
  static const _adresse = "Adresse : Attan-Ewé, Arrondissement d'Ikpinlè, Commune d'Adja-Ouèrè, Bénin";
  static const _telephone = 'Téléphone : +229 01 97 84 02 85 / 01 43 46 08 71, RCCM : RB/PNO/22 A 33870';

  // Domaines de formation cochables — LES LIBELLÉS DE L'ÉCRAN WEB (`AttestationService::DOMAINES`) ; le PDF imprime, lui,
  // la phrase longue du modèle officiel (`DOMAINES_PUCES`), reprise ici pour l'aperçu.
  static const _domainesDisponibles = <String, String>{
    'maraichage': 'Maraîchage',
    'elevage': 'Élevage',
    'rations': 'Rations alimentaires',
    'gestion': "Gestion d'entreprise",
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

  // ATT-2 — les modifications des signataires POUR CETTE attestation, par position serveur (1 = Directeur Général,
  // 2 = Examinateur, 3 = Président du Jury). Vides : le modèle s'applique (il est montré en indication).
  final _surcharges = <int, ({TextEditingController titre, TextEditingController nom, TextEditingController fonction})>{
    for (final n in [1, 2, 3])
      n: (titre: TextEditingController(), nom: TextEditingController(), fonction: TextEditingController()),
  };

  /// La règle de signature de chaque modèle, telle que le poste l'a reçue (`null` : pas encore reçue).
  final _reglages = <String, ReglageSignature?>{'employe': null, 'stagiaire': null};

  /// Les champs de l'onglet « Personnaliser les Modèles » (règle de signature), par type.
  final _champsReglage = <String, _ChampsReglage>{
    'employe': _ChampsReglage(),
    'stagiaire': _ChampsReglage(),
  };

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
    for (final c in _surcharges.values) {
      c.titre.dispose();
      c.nom.dispose();
      c.fonction.dispose();
    }
    for (final c in _champsReglage.values) {
      c.dispose();
    }
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
      final reglage = await widget.depot.reglage(t);
      _reglages[t] = reglage;
      if (reglage != null && !_champsReglage[t]!.initialise) _champsReglage[t]!.charger(reglage);
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
      final produite = await widget.depot.produire(
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
        surcharges: _surchargesSaisies(),
        aujourdhui: _aujourdhui,
      );
      final pdf = produite.pdf;
      final chemin = await widget.enregistrer(pdf);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _dernierPdf = pdf;
        // ⚠️ HORS LIGNE EST NORMAL : le document est produit, son numéro vient à la prochaine synchronisation.
        _retour = (
          true,
          'Attestation enregistrée : $chemin'
              '${produite.horsLigne ? ' — numéro à attribuer à la prochaine synchronisation' : ' — ${produite.numero}'}',
        );
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

  /// Les modifications saisies pour CETTE attestation, par position du signataire (vides ignorés par la règle).
  Map<int, Map<String, String>> _surchargesSaisies() => {
    for (final e in _surcharges.entries)
      e.key: {'titre': e.value.titre.text, 'nom': e.value.nom.text, 'fonction': e.value.fonction.text},
  };

  /// La règle du modèle du type courant — celle du serveur, ou les valeurs d'un modèle neuf tant qu'elle n'est pas reçue.
  ReglageSignature get _reglage => _reglages[_type] ?? ReglageSignature.defaut;

  /// Palier de la durée saisie : `court` (le promoteur seul) ou `long` (trois signataires).
  String get _palier => ReglageSignature.palier(_lire(_debut.text), _lire(_fin.text), _reglage.seuilMois, _aujourdhui);

  /// Les signataires que la durée appelle, tels qu'ils s'imprimeront.
  List<SignataireModele> get _signatairesRequis => _reglage.requis(
    debut: _lire(_debut.text),
    fin: _lire(_fin.text),
    aujourdhui: _aujourdhui,
    surcharges: {
      for (final e in _surcharges.entries)
        e.key: {'titre': e.value.titre.text, 'nom': e.value.nom.text, 'fonction': e.value.fonction.text},
    },
  );

  Future<void> _enregistrerReglage(String type) async {
    if (_enCours) return;
    final champs = _champsReglage[type]!;
    final erreur = champs.erreurSeuil();

    if (erreur != null) {
      setState(() {
        _erreurs = {'reglage-$type': erreur};
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
      final reglage = champs.versReglage();
      await widget.depot.enregistrerReglage(type, reglage);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _reglages[type] = reglage;
        _retour = (true, 'Règle de signature enregistrée.');
      });
    } on EchecAttestation catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = {for (final c in e.champs.entries) 'reglage-$type': c.value};
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
          // ATT-1 — civilité (M. / Mme).
          const SizedBox(height: AgriSpacing.md),
          Text('Civilité'.toUpperCase(), style: _etiquette),
          const SizedBox(height: AgriSpacing.xs),
          RadioGroup<String>(
            groupValue: _civilite,
            onChanged: (v) => setState(() => _civilite = v ?? 'M.'),
            child: Row(
              children: [
                for (final (val, lib) in [('M.', 'M. (Monsieur)'), ('Mme', 'Mme (Madame)')])
                  Flexible(
                    child: InkWell(
                      key: Key('att-civilite-$val'),
                      onTap: () => setState(() => _civilite = val),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: val,
                            activeColor: AgriColors.brandEmerald,
                          ),
                          Text(lib, style: const TextStyle(fontSize: AgriTypography.xs)),
                          const SizedBox(width: AgriSpacing.md),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
          // ATT-2 — les signataires que la DURÉE appelle ; un champ vide reprend le modèle.
          const SizedBox(height: AgriSpacing.md),
          _blocSignataires(),
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

    final debut = _lire(_debut.text);
    final fin = _lire(_fin.text);
    final appreciation = x == null
        ? null
        : AttestationsRepository.appreciation(
            type: _type,
            personne: x,
            saisie: _note.text.trim().isNotEmpty ? _note.text : _appreciation.text,
            reglage: _reglages[_type],
            debut: debut,
            fin: fin,
            civilite: _civilite,
            aujourdhui: _aujourdhui,
          );

    return Container(
      key: const Key('att-apercu'),
      constraints: const BoxConstraints(minHeight: 480),
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: _carte(),
      child: Stack(
        children: [
          // Filigrane : le logo officiel de la ferme, très pâle (comme le PDF).
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.12,
                  child: Image.asset('assets/images/logo.png', key: const Key('att-apercu-filigrane'), width: 240),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── En-tête : logo officiel | nom, activités, adresse, téléphone ───
              Container(
                padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/images/logo.png', key: const Key('att-apercu-logo'), width: 56),
                    const SizedBox(width: AgriSpacing.sm),
                    const Expanded(
                      child: Column(
                        children: [
                          Text(
                            _ferme,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AgriTypography.sm,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2E6B1A),
                            ),
                          ),
                          Text(_activites, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                          Text(_adresse, textAlign: TextAlign.center, style: TextStyle(fontSize: 8)),
                          Text(_telephone, textAlign: TextAlign.center, style: TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                'ATTAN - ÉWÉ, le ${_dateLongue(_aujourdhui)}',
                key: const Key('att-apercu-lieu-date'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
              ),
              const Text(
                'N°—/FEO/DG',
                key: Key('att-apercu-numero'),
                style: TextStyle(fontSize: 9, fontWeight: AgriTypography.gras),
              ),
              const SizedBox(height: AgriSpacing.sm),
              // ─── Titre centré souligné ───
              Text(
                titre.toUpperCase(),
                key: const Key('att-apercu-titre'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
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
                  style: const TextStyle(fontSize: AgriTypography.xs, height: 1.6),
                )
              else
                Text(
                  !_modelesRecus[_type]!
                      ? 'Modèle pas encore reçu du serveur — synchronisez.'
                      : "Sélectionnez une personne pour prévisualiser l'attestation.",
                  key: const Key('att-apercu-vide'),
                  style: mute,
                ),
              // ─── Domaines : une puce ➢ par domaine coché, dans l'ordre du modèle ───
              if (_domaines.isNotEmpty) ...[
                const SizedBox(height: AgriSpacing.sm),
                for (final cle in AttestationsRepository.domainesPuces.keys)
                  if (_domaines.contains(cle))
                    Padding(
                      padding: const EdgeInsets.only(left: AgriSpacing.md),
                      child: Text(
                        '➢ ${AttestationsRepository.apostrophes(AttestationsRepository.domainesPuces[cle]!)}',
                        key: Key('att-apercu-domaine-$cle'),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
              ],
              // ─── Appréciation : la saisie, sinon celle du modèle ───
              if (appreciation != null) ...[
                const SizedBox(height: AgriSpacing.sm),
                Text(
                  appreciation,
                  key: const Key('att-apercu-appreciation'),
                  style: const TextStyle(fontSize: 10),
                ),
              ],
              if (x != null) ...[
                const SizedBox(height: AgriSpacing.sm),
                const Text(
                  'En foi de quoi, la présente attestation lui est délivrée pour servir et valoir ce que de droit.',
                  key: Key('att-apercu-cloture'),
                  style: TextStyle(fontSize: 10),
                ),
              ],
              const SizedBox(height: AgriSpacing.lg),
              // ─── Signataires appelés par la durée : trois (Examinateur, Président du Jury, Directeur) ou le promoteur seul ───
              Row(
                key: const Key('att-apercu-signataires'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final sig in _signatairesRequis)
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AgriSpacing.sm),
                        child: _blocSignature(sig),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AgriSpacing.xs),
              const Text(
                'Aperçu simplifié : le PDF reprend le modèle officiel (décor, filigrane, polices).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8, color: AgriColors.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _blocSignature(SignataireModele sig) => Column(
    key: Key('att-apercu-sig-${sig.position}'),
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (sig.titre.isNotEmpty)
        Align(
          alignment: Alignment.center,
          child: Text(
            sig.titre,
            style: const TextStyle(fontSize: 9, fontWeight: AgriTypography.gras, decoration: TextDecoration.underline),
          ),
        ),
      const SizedBox(height: AgriSpacing.xs),
      Text(
        sig.nom.isEmpty ? '…' : sig.nom,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 9, fontWeight: AgriTypography.gras),
      ),
      if (sig.fonction.isNotEmpty)
        Text(sig.fonction, textAlign: TextAlign.right, style: const TextStyle(fontSize: 8)),
    ],
  );

  // ── ATT-2 : signataires selon la durée ───────────────────────────────────

  /// Le bloc « Signataires » du formulaire : ceux que la DURÉE appelle, un champ vide reprenant le modèle.
  Widget _blocSignataires() {
    final seuil = _reglage.seuilMois;
    final long = _palier == 'long';
    final requis = _signatairesRequis;
    final titre = long
        ? 'trois signataires (attestation de plus de $seuil mois)'
        : "le promoteur seul (jusqu'à $seuil mois)";

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('att-signataires'),
        initiallyExpanded: _debut.text.trim().isNotEmpty,
        tilePadding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        collapsedShape: RoundedRectangleBorder(
          side: const BorderSide(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        title: Text(
          'Signataires — $titre'.toUpperCase(),
          key: const Key('att-signataires-titre'),
          style: _etiquette,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AgriSpacing.sm, 0, AgriSpacing.sm, AgriSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (requis.isEmpty)
                  const Text(
                    "Aucun signataire n'est appelé par la règle de ce modèle (voir « Personnaliser les Modèles »).",
                    key: Key('att-signataires-aucun'),
                    style: TextStyle(fontSize: 10, color: AgriColors.outline),
                  ),
                for (final sig in requis) ...[
                  const SizedBox(height: AgriSpacing.xs),
                  Row(
                    key: Key('att-signataire-${sig.position}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (champ, libelle, indication, ctrl) in [
                        ('titre', 'Intitulé', _reglage.signataires[sig.position]?.titre ?? '', _surcharges[sig.position]!.titre),
                        ('nom', 'Nom', _reglage.signataires[sig.position]?.nom ?? '', _surcharges[sig.position]!.nom),
                        ('fonction', 'Fonction', _reglage.signataires[sig.position]?.fonction ?? '', _surcharges[sig.position]!.fonction),
                      ]) ...[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(libelle.toUpperCase(), style: _etiquette),
                              const SizedBox(height: AgriSpacing.xs),
                              TextField(
                                key: Key('att-sig${sig.position}-$champ'),
                                controller: ctrl,
                                onChanged: (_) => setState(() {}),
                                style: StylesChampsAgri.valeurFormulaire,
                                decoration: _decor(indication.isEmpty ? '—' : indication, hauteurFixe: AgriChamps.hauteurFormulaire),
                              ),
                            ],
                          ),
                        ),
                        if (champ != 'fonction') const SizedBox(width: AgriSpacing.xs),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: AgriSpacing.xs),
                const Text(
                  "Champs vides : le modèle s'applique. Qui signe, et à partir de quelle durée, se règle dans « Personnaliser les Modèles ».",
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Carte « Signataires et règle de signature » d'un modèle (onglet « Personnaliser les Modèles »).
  Widget _carteReglage(String type, String libelleModele) {
    final c = _champsReglage[type]!;

    Widget champ(String cle, TextEditingController ctrl, String indication) => Expanded(
      child: TextField(
        key: Key(cle),
        controller: ctrl,
        style: StylesChampsAgri.valeurFormulaire,
        decoration: _decor(indication, hauteurFixe: AgriChamps.hauteurFormulaire),
      ),
    );

    return Container(
      key: Key('att-reglage-$type'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(SymbolesAgri.workspace_premium, size: 18, color: AgriColors.brandForest),
              const SizedBox(width: AgriSpacing.xs),
              Flexible(
                child: Text(
                  'Signataires et règle de signature — $libelleModele'.toUpperCase(),
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
          if (_reglages[type] == null)
            const Padding(
              padding: EdgeInsets.only(bottom: AgriSpacing.sm),
              child: Text(
                'Règle pas encore reçue du serveur — synchronisez. Les valeurs ci-dessous sont celles d\'un modèle neuf.',
                key: Key('att-reglage-absent'),
                style: TextStyle(fontSize: AgriTypography.xs, fontStyle: FontStyle.italic, color: AgriColors.outline),
              ),
            ),
          Row(
            children: [
              const Text("Palier court : jusqu'à ", style: TextStyle(fontSize: AgriTypography.xs)),
              SizedBox(
                width: 72,
                child: TextField(
                  key: Key('att-seuil-$type'),
                  controller: c.seuil,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: StylesChampsAgri.valeurFormulaire,
                  decoration: _decor('12', erreur: _erreurs.containsKey('reglage-$type'), hauteurFixe: AgriChamps.hauteurFormulaire),
                ),
              ),
              const Expanded(
                child: Text(
                  ' mois inclus ; au-delà, palier long. Durée comptée de la date de début à la date de fin (à aujourd\'hui sans date de fin).',
                  style: TextStyle(fontSize: AgriTypography.xs),
                ),
              ),
            ],
          ),
          _erreur('reglage-$type'),
          for (final (n, role) in [
            (1, 'Directeur Général (le promoteur)'),
            (2, 'Examinateur'),
            (3, 'Président du Jury'),
          ]) ...[
            const SizedBox(height: AgriSpacing.sm),
            Container(
              key: Key('att-reglage-$type-sig$n'),
              padding: const EdgeInsets.all(AgriSpacing.sm),
              decoration: _carte(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.toUpperCase(), style: _etiquette),
                  const SizedBox(height: AgriSpacing.xs),
                  Row(
                    children: [
                      champ('att-$type-sig$n-titre', c.titre[n]!, 'Intitulé imprimé (vide : aucun)'),
                      const SizedBox(width: AgriSpacing.xs),
                      champ('att-$type-sig$n-nom', c.nom[n]!, 'Nom'),
                      const SizedBox(width: AgriSpacing.xs),
                      champ('att-$type-sig$n-fonction', c.fonction[n]!, 'Fonction'),
                    ],
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  Row(
                    children: [
                      for (final (palier, libelle) in [('court', 'Signe le palier court'), ('long', 'Signe le palier long')])
                        Expanded(
                          child: InkWell(
                            key: Key('att-$type-sig$n-$palier'),
                            onTap: () => setState(() => c.basculer(n, palier)),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: palier == 'court' ? c.court[n]! : c.long[n]!,
                                    onChanged: (_) => setState(() => c.basculer(n, palier)),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    activeColor: AgriColors.brandEmerald,
                                  ),
                                ),
                                const SizedBox(width: AgriSpacing.xs),
                                Flexible(child: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AgriSpacing.md),
          InkWell(
            key: Key('att-$type-appreciation-imprimee'),
            onTap: () => setState(() => c.appreciationImprimee = !c.appreciationImprimee),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: c.appreciationImprimee,
                    onChanged: (v) => setState(() => c.appreciationImprimee = v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: AgriColors.brandEmerald,
                  ),
                ),
                const SizedBox(width: AgriSpacing.xs),
                const Flexible(
                  child: Text(
                    "Imprimer l'appréciation par défaut (modifiable à chaque émission)",
                    style: TextStyle(fontSize: AgriTypography.xs),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          TextField(
            key: Key('att-$type-appreciation'),
            controller: c.appreciation,
            minLines: 2,
            maxLines: 2,
            style: const TextStyle(fontSize: AgriTypography.xs),
            decoration: _decor(
              type == 'stagiaire' ? AttestationsRepository.appreciationStagiaire : 'Aucune phrase standard',
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "Vide : la phrase standard du modèle officiel. **texte** s'imprime en gras. Balises : [CIVILITE_LONGUE], [NOM], [TITRE_NOM], [ACCORD_E].",
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.md),
          FilledButton(
            key: Key('att-enregistrer-reglage-$type'),
            onPressed: _enCours ? null : () => _enregistrerReglage(type),
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
            ),
            child: const Text(
              'Enregistrer la règle de signature',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
          ),
        ],
      ),
    );
  }

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
      'Balises : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DUREE], '
          "[DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E]. **texte** s'imprime en gras.",
    );
    final stagiaire = _carteModele(
      'stagiaire',
      SymbolesAgri.school,
      'Modèle - Attestation de Formation (Stagiaire)',
      'Balises : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], '
          '[DUREE], [DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E], [DATE_NAISSANCE], '
          "[DATE_NAISSANCE_LONGUE], [LIEU_NAISSANCE]. **texte** s'imprime en gras.",
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
        const SizedBox(height: AgriSpacing.md),
        _carteReglage('employe', 'Attestation de Travail (Employé)'),
        const SizedBox(height: AgriSpacing.md),
        _carteReglage('stagiaire', 'Attestation de Formation (Stagiaire)'),
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

/// Les champs de l'onglet « Personnaliser les Modèles » pour la règle de signature d'UN modèle (ATT-2).
class _ChampsReglage {
  final seuil = TextEditingController();
  final appreciation = TextEditingController();
  bool appreciationImprimee = true;
  final titre = {for (final n in [1, 2, 3]) n: TextEditingController()};
  final nom = {for (final n in [1, 2, 3]) n: TextEditingController()};
  final fonction = {for (final n in [1, 2, 3]) n: TextEditingController()};
  final court = <int, bool>{1: true, 2: false, 3: false};
  final long = <int, bool>{1: true, 2: true, 3: true};

  /// Vrai dès que les valeurs du serveur ont été chargées : un rechargement ne doit pas écraser une saisie en cours.
  bool initialise = false;

  void charger(ReglageSignature r) {
    initialise = true;
    seuil.text = '${r.seuilMois}';
    appreciation.text = r.appreciationText ?? '';
    appreciationImprimee = r.appreciationImprimee;
    for (final n in [1, 2, 3]) {
      final sig = r.signataires[n];
      titre[n]!.text = sig?.titre ?? '';
      nom[n]!.text = sig?.nom ?? '';
      fonction[n]!.text = sig?.fonction ?? '';
      court[n] = sig?.court ?? false;
      long[n] = sig?.long ?? false;
    }
  }

  void basculer(int n, String palier) {
    if (palier == 'court') {
      court[n] = !court[n]!;
    } else {
      long[n] = !long[n]!;
    }
  }

  /// Les messages du serveur (`Attestations::saveReglage`, mêmes mots), sans aller-retour.
  String? erreurSeuil() {
    final texte = seuil.text.trim();
    if (texte.isEmpty) return 'Indiquez la durée en mois.';
    final n = int.tryParse(texte);
    if (n == null) return 'La durée est un nombre entier de mois.';
    if (n < 1) return "La durée doit être d'au moins 1 mois.";
    if (n > 120) return 'La durée ne peut pas dépasser 120 mois.';
    return null;
  }

  ReglageSignature versReglage() => ReglageSignature(
    seuilMois: int.parse(seuil.text.trim()),
    appreciationText: appreciation.text.trim().isEmpty ? null : appreciation.text,
    appreciationImprimee: appreciationImprimee,
    signataires: {
      for (final n in [1, 2, 3])
        n: SignataireModele(
          position: n,
          titre: titre[n]!.text.trim(),
          nom: nom[n]!.text.trim(),
          fonction: fonction[n]!.text.trim(),
          court: court[n]!,
          long: long[n]!,
        ),
    },
  );

  void dispose() {
    seuil.dispose();
    appreciation.dispose();
    for (final c in [...titre.values, ...nom.values, ...fonction.values]) {
      c.dispose();
    }
  }
}
