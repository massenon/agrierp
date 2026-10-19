import 'package:flutter/material.dart';

import '../../core/erreurs/message_erreur.dart';
import '../../core/export/pdf_recu.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
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
  // pas l'IFU de démonstration du prototype) et le Directeur Général qu'elle nomme.
  static const _ferme = 'FERME ÉCOLE OLOUWACHEGOUN';
  static const _adresse = 'Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin';
  static const _rccm = 'RCCM : RB/PNO/22 A 33870';
  static const _directeur = 'M. Olouchègoun';   // décision client du 17/10/2026, comme le web

  String _onglet = 'generer';
  String _type = 'employe';

  List<PersonneAttestation> _personnes = const [];
  String _personneId = '';
  String _contrat = AttestationsRepository.contrats.first;

  final _debut = TextEditingController();
  final _fin = TextEditingController();
  final _note = TextEditingController();

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

  static const _etiquette = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.brandForest,
  );

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

  InputDecoration _decor(String aide, {bool erreur = false, Widget? fin}) =>
      InputDecoration(
        hintText: aide,
        hintStyle: const TextStyle(
          fontSize: AgriTypography.sm,
          color: AgriColors.outline,
        ),
        suffixIcon: fin,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: 14,
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
        style: const TextStyle(fontSize: AgriTypography.sm),
        decoration: _decor(
          'jj/mm/aaaa',
          erreur: _erreurs.containsKey(champ),
          fin: IconButton(
            key: Key('$cle-calendrier'),
            icon: const Icon(SymbolesAgri.calendar_today, size: 16),
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

  Widget _carteApercu() {
    final titre = _type == 'employe'
        ? 'Attestation de Travail'
        : 'Attestation de Stage';
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
                child: Opacity(
                  opacity: 0.05,
                  child: const Icon(SymbolesAgri.agriculture, size: 220),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: AgriSpacing.md),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(width: 2, color: AgriColors.brandForest),
                  ),
                ),
                child: Row(
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
                            _adresse,
                            style: TextStyle(
                              fontSize: 9,
                              color: AgriColors.outline,
                            ),
                          ),
                          Text(
                            _rccm,
                            style: TextStyle(
                              fontSize: 9,
                              color: AgriColors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      titre.toUpperCase(),
                      key: const Key('att-apercu-titre'),
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.brandEmerald,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              Text(
                titre.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  letterSpacing: 0.8,
                  color: AgriColors.brandForest,
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
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
              if (_note.text.trim().isNotEmpty) ...[
                const SizedBox(height: AgriSpacing.md),
                Text(
                  _note.text,
                  key: const Key('att-apercu-note'),
                  style: mute,
                ),
              ],
              const SizedBox(height: AgriSpacing.lg),
              Text(
                'Fait à Ikpinlè, le ${_ecrire(_aujourdhui)}.',
                style: const TextStyle(fontSize: AgriTypography.xs),
              ),
              const SizedBox(height: AgriSpacing.xl),
              const Align(
                alignment: Alignment.centerRight,
                child: Column(
                  children: [
                    Text(
                      'Le Directeur Général',
                      style: TextStyle(fontSize: 10, color: AgriColors.outline),
                    ),
                    SizedBox(height: AgriSpacing.lg),
                    Text(
                      _directeur,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.brandForest,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      'Balises disponibles : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]',
    );
    final stagiaire = _carteModele(
      'stagiaire',
      SymbolesAgri.school,
      'Modèle - Attestation de Stage (Stagiaire)',
      'Balises disponibles : [NOM], [SPECIALITE], [ETABLISSEMENT], '
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
