import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/database/app_database.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/export/pdf_recu.dart';
import '../../core/theme/agri_tokens.dart';
import 'sujets_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/animal-details.html` → Fiche Sujet.
///
/// ⚠️⚠️ **TROIS ONGLETS SUR HUIT N'ONT AUCUNE SOURCE, ET L'ÉCRAN LE DIT.** Le
/// prototype écrit toutes ses valeurs en dur ; Alimentation (la ration se calcule
/// par BANDE, jamais par sujet), Production (la ponte se relève par bande) et
/// Documents (aucune pièce jointe par sujet) n'ont rien de réel à montrer. Ils
/// affichent leur motif — celui de la page web — plutôt qu'un contenu plausible.
///
/// ⚠️ **LE PDF EST PRODUIT PAR LE SERVEUR** et exige le réseau : l'en-tête officiel
/// de la ferme n'a pas à être recopié sur chaque machine.
///
/// ⚠️ **ÉCARTS ASSUMÉS, TOUS DE LARAVEL** : pas de bouton « Déclarer un Mouvement »
/// (aucun mouvement ne se déclare — les mouvements affichés sont ceux réellement
/// saisis), pas de matrice « Liaison avec les Autres Modules » (texte de
/// maquette sans donnée), et la reproduction/les soins sont retrouvés comme la
/// page web le fait, sans rien fabriquer.
class FicheSujetScreen extends StatefulWidget {
  const FicheSujetScreen({
    super.key,
    required this.depot,
    required this.sujetId,
    required this.enregistrer,
    required this.imprimer,
    this.onRetour,
    this.onOuvrirReproduction,
    this.maintenant,
  });

  final SujetsRepository depot;
  final String sujetId;

  /// Écrit le PDF, rend son chemin.
  final Future<String> Function(PdfRecu) enregistrer;

  /// Ouvre la boîte d'impression.
  final Future<void> Function(PdfRecu) imprimer;

  /// Revient à l'écran d'où l'on vient.
  final VoidCallback? onRetour;

  /// Ouvre le Suivi de Reproduction (lien de l'onglet Reproduction).
  final VoidCallback? onOuvrirReproduction;

  /// Instant de référence de l'âge — fixé par les tests.
  final DateTime? maintenant;

  /// Ce que le QR ENCODE : l'identifiant lisible, celui de la boucle du sujet.
  ///
  /// ⚠️ Isolé ici pour être testable : le widget `QrImageView` garde sa donnée
  /// privée, et un test qui ne peut pas la lire ne prouverait rien.
  static String donneesQr(Sujet s) => s.identifier;

  @override
  State<FicheSujetScreen> createState() => _FicheSujetScreenState();
}

class _FicheSujetScreenState extends State<FicheSujetScreen> {
  static const onglets = <(String, String)>[
    ('general', 'Général'),
    ('historique', 'Historique'),
    ('alimentation', 'Alimentation'),
    ('vaccins', 'Vaccins'),
    ('reproduction', 'Reproduction'),
    ('production', 'Production'),
    ('mouvements', 'Mouvements'),
    ('documents', 'Documents'),
  ];

  /// Motifs des trois onglets sans source — ceux de la page web.
  static const _motifs = {
    'alimentation':
        // Tickets F0.92 puis F0.96 : texte du web (glossaire lapins du 17/10/2026).
        'Le rationnement est calculé PAR BANDE et par catégorie (par exemple, '
        'pour les lapins : Reproducteur / Jeune / Sous-mères), jamais par '
        'sujet. Afficher une ration individuelle '
        "supposerait de diviser arbitrairement la provende de la bande — un "
        "chiffre qui n'aurait aucune valeur zootechnique.",
    'production':
        'La ponte est relevée par bande dans la fiche journalière (œufs '
        'récoltés, cassés, commercialisables). Aucune source ne rattache une '
        'production à une poule donnée.',
    'documents':
        "Aucune table de pièces jointes par sujet n'existe dans le schéma. Le "
        'module Administration gère les documents de la ferme, pas ceux '
        "d'un animal.",
  };

  String _onglet = 'general';
  FicheSujet? _fiche;
  bool _chargee = false;

  /// Retour de l'export : (réussi, message).
  (bool, String)? _retour;
  PdfRecu? _dernierPdf;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final fiche = await widget.depot.charger(
      widget.sujetId,
      maintenant: widget.maintenant,
    );
    if (!mounted) return;
    setState(() {
      _fiche = fiche;
      _chargee = true;
    });
  }

  Future<void> _exporter() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _retour = null;
      _dernierPdf = null;
    });

    try {
      final pdf = await widget.depot.exporterPdf(widget.sujetId);
      final chemin = await widget.enregistrer(pdf);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _dernierPdf = pdf;
        _retour = (true, 'Fiche enregistrée : $chemin');
      });
    } on EchecSujet catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
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

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: !_chargee
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
              child: _fiche == null ? _introuvable() : _contenu(_fiche!, large),
            ),
    );
  }

  Widget _introuvable() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _boutonRetour(),
      const SizedBox(height: AgriSpacing.md),
      Container(
        key: const Key('sujet-introuvable'),
        padding: const EdgeInsets.all(AgriSpacing.lg),
        decoration: _carte(),
        child: const Text(
          "Ce sujet n'est pas dans la base du poste. Synchronisez : les sujets "
          'descendent du serveur.',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            color: AgriColors.outline,
          ),
        ),
      ),
    ],
  );

  Widget _boutonRetour() => TextButton.icon(
    key: const Key('sujet-retour'),
    onPressed: widget.onRetour,
    icon: const Icon(SymbolesAgri.arrow_back, size: 16),
    label: const Text('Retour', style: TextStyle(fontSize: AgriTypography.xs)),
  );

  BoxDecoration _carte({Color? fond, Color? bordure}) => BoxDecoration(
    color: fond ?? AgriColors.surfaceCard,
    border: Border.all(color: bordure ?? AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  Widget _contenu(FicheSujet f, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(alignment: Alignment.centerLeft, child: _boutonRetour()),
      _entete(f),
      if (_retour != null) ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_retour!.$1, _retour!.$2),
        if (_dernierPdf != null) ...[
          const SizedBox(height: AgriSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('sujet-imprimer'),
              onPressed: () => widget.imprimer(_dernierPdf!),
              icon: const Icon(SymbolesAgri.print, size: 18),
              label: const Text('Imprimer'),
            ),
          ),
        ],
      ],
      const SizedBox(height: AgriSpacing.lg),
      _barreOnglets(),
      const SizedBox(height: AgriSpacing.md),
      switch (_onglet) {
        'historique' => _historique(f),
        'vaccins' => _vaccins(f),
        'reproduction' => _reproduction(f),
        'mouvements' => _mouvements(f),
        'alimentation' || 'production' || 'documents' => _enAttente(_onglet),
        _ => _general(f, large),
      },
    ],
  );

  // ── En-tête ───────────────────────────────────────────────────────────────

  Widget _entete(FicheSujet f) {
    final s = f.sujet;
    final ligne = [
      s.speciesLabel ?? '—',
      if ((s.breed ?? '').isNotEmpty) 'Race ${s.breed}',
      f.sexe,
      if ((s.lotCode ?? '').isNotEmpty) 'Lot ${s.lotCode}',
      if ((s.cage ?? '').isNotEmpty) 'Cage ${s.cage}',
    ].join(' · ');

    return Container(
      key: const Key('sujet-entete'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AgriColors.brandEmerald.withValues(alpha: 0.10),
              border: Border.all(
                width: 2,
                color: AgriColors.brandEmerald.withValues(alpha: 0.30),
              ),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Icon(
              SymbolesAgri.pets,
              size: 36,
              color: AgriColors.brandEmerald,
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AgriSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sujet #${s.identifier}',
                      key: const Key('sujet-titre'),
                      style: const TextStyle(
                        fontSize: AgriTypography.xl,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.onSurface,
                      ),
                    ),
                    _badge(f),
                  ],
                ),
                const SizedBox(height: AgriSpacing.xs),
                Text(
                  ligne,
                  key: const Key('sujet-ligne'),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          OutlinedButton.icon(
            key: const Key('sujet-exporter'),
            onPressed: _enCours ? null : _exporter,
            icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
            label: const Text(
              'Exporter PDF',
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

  Widget _badge(FicheSujet f) {
    final couleur = f.present ? AgriColors.brandEmerald : AgriColors.errorDeep;

    return Container(
      key: const Key('sujet-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        f.badge,
        style: TextStyle(
          fontSize: 11,
          fontWeight: AgriTypography.gras,
          color: couleur,
        ),
      ),
    );
  }

  Widget _bandeau(bool reussi, String message) {
    final couleur = reussi ? AgriColors.brandEmerald : AgriColors.errorRed;

    return Container(
      key: Key(reussi ? 'sujet-reussi' : 'sujet-echec'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: _carte(
        fond: couleur.withValues(alpha: 0.10),
        bordure: couleur.withValues(alpha: 0.30),
      ),
      child: Row(
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

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (cle, titre) in onglets)
            InkWell(
              key: Key('onglet-sujet-$titre'),
              onTap: () => setState(() => _onglet = cle),
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
    ),
  );

  // ── Général : identification et QR ────────────────────────────────────────

  Widget _general(FicheSujet f, bool large) {
    final s = f.sujet;
    final age = f.ageEnMois == null ? '' : ' (${f.ageEnMois} mois)';

    final champs = <(String, String)>[
      ('N° Identification', s.identifier),
      ('Espèce', s.speciesLabel ?? '—'),
      ('Catégorie', SujetsRepository.majuscule(s.category)),
      ('Race', _ou(s.breed)),
      ('Sexe', f.sexe),
      ('Date de Naissance', '${_date(s.birthDate)}$age'),
      ("Date d'Entrée", _date(s.entryDate)),
      ('Origine', _ou(s.origin)),
      ('Cage', _ou(s.cage)),
      ('Lot', _ou(s.lotCode)),
    ];

    final identification = Container(
      key: const Key('sujet-identification'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.badge, size: 18, color: AgriColors.brandForest),
              SizedBox(width: AgriSpacing.xs),
              Text(
                'Identification',
                style: TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          Wrap(
            runSpacing: AgriSpacing.md,
            children: [
              for (final (libelle, valeur) in champs)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        libelle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        valeur,
                        key: Key('sujet-champ-$libelle'),
                        style: const TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
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

    final qr = Container(
      key: const Key('sujet-qr'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.qr_code_2, size: 18, color: AgriColors.brandForest),
              SizedBox(width: AgriSpacing.xs),
              Text(
                'QR Code Sujet',
                style: TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          // ⚠️ UN VRAI QR, QUI ENCODE L'IDENTIFIANT LISIBLE — celui de la boucle
          // du sujet, comme la page web. Jamais une image de remplacement.
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: _carte(fond: Colors.white),
            child: Center(
              child: QrImageView(
                key: const Key('sujet-qr-image'),
                data: FicheSujetScreen.donneesQr(s),
                semanticsLabel: 'QR code du sujet ${s.identifier}',
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.sm),
          const Text(
            "Scan terrain pour ouvrir directement cette fiche depuis "
            "l'application mobile.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ],
      ),
    );

    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: identification),
              const SizedBox(width: AgriSpacing.md),
              Expanded(child: qr),
            ],
          )
        : Column(
            children: [
              identification,
              const SizedBox(height: AgriSpacing.md),
              qr,
            ],
          );
  }

  // ── Tableaux ──────────────────────────────────────────────────────────────

  Widget _historique(FicheSujet f) => _tableau(
    cle: 'historique',
    colonnes: const [('Date', 2), ('Type', 2), ('Événement', 8)],
    vide: 'Aucun événement enregistré pour ce sujet.',
    lignes: [
      for (final l in f.historique) [_date(l.date), l.type, l.libelle],
    ],
  );

  Widget _vaccins(FicheSujet f) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        key: const Key('sujet-soins-bande'),
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: _carte(
          fond: AgriColors.infoBlue.withValues(alpha: 0.10),
          bordure: AgriColors.infoBlue.withValues(alpha: 0.20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              SymbolesAgri.info,
              size: 18,
              color: AgriColors.infoBlue,
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              // ⚠️ DIT QUE CE SONT LES SOINS DE LA BANDE : la prophylaxie est
              // administrée par bande sur cette ferme, jamais sujet par sujet.
              child: Text(
                'La prophylaxie est administrée par bande sur cette ferme, '
                'jamais sujet par sujet. Les soins ci-dessous sont ceux de la '
                'bande ${_ou(f.sujet.lotCode)} et concernent donc ce sujet — '
                'ils ne sont pas des traitements individuels.',
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.brandForest,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        cle: 'vaccins',
        colonnes: const [
          ('Date', 2),
          ('Action', 3),
          ('Produit', 3),
          ('Dose', 2),
        ],
        vide: 'Aucun soin enregistré pour la bande de ce sujet.',
        lignes: [
          for (final s in f.soins)
            [_date(s.date), s.action, _ou(s.produit), _ou(s.dose)],
        ],
      ),
    ],
  );

  Widget _reproduction(FicheSujet f) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _tableau(
        cle: 'reproduction',
        colonnes: const [
          ('Saillie', 2),
          ('Rôle', 2),
          ('Mise Bas', 2),
          ('Nés Vivants', 2),
          ('Nés Morts', 2),
          ('Statut', 2),
        ],
        vide: 'Aucun événement de reproduction pour ce sujet.',
        lignes: [
          for (final e in f.reproduction)
            [
              _date(e.saillie),
              e.role,
              _date(e.miseBas),
              e.vivants?.toString() ?? '—',
              e.morts?.toString() ?? '—',
              e.statut,
            ],
        ],
      ),
      const SizedBox(height: AgriSpacing.sm),
      Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 11, color: AgriColors.outline),
          children: [
            const TextSpan(
              text:
                  'Événements retrouvés par correspondance sur les références '
                  'mère/géniteur déjà saisies dans le ',
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InkWell(
                key: const Key('sujet-lien-reproduction'),
                onTap: widget.onOuvrirReproduction,
                child: const Text(
                  'Suivi de Reproduction',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandEmerald,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    ],
  );

  Widget _mouvements(FicheSujet f) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _tableau(
        cle: 'mouvements',
        colonnes: const [('Date', 2), ('Mouvement', 4), ('Détail', 6)],
        vide: 'Aucun mouvement.',
        lignes: [
          for (final m in f.mouvements) [_date(m.date), m.libelle, m.detail],
        ],
      ),
      const SizedBox(height: AgriSpacing.sm),
      const Text(
        'Seuls les mouvements réellement enregistrés sont listés. Aucun '
        "historique de déplacement entre cages n'est modélisé à ce jour — en "
        'fabriquer un ici afficherait des lignes jamais saisies.',
        key: Key('sujet-mouvements-note'),
        style: TextStyle(fontSize: 11, color: AgriColors.outline),
      ),
    ],
  );

  Widget _tableau({
    required String cle,
    required List<(String, int)> colonnes,
    required List<List<String>> lignes,
    required String vide,
  }) => Container(
    key: Key('sujet-tableau-$cle'),
    decoration: _carte(),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(880, contraintes.maxWidth),
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  key: Key('sujet-$cle-vide'),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (final (i, ligne) in lignes.indexed)
              Container(
                key: Key('sujet-$cle-ligne-$i'),
                color: i.isOdd
                    ? AgriColors.surfaceZebra
                    : AgriColors.surfaceCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (final (j, (_, flex)) in colonnes.indexed)
                      Expanded(
                        flex: flex,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AgriSpacing.sm),
                          child: Text(
                            ligne[j],
                            style: const TextStyle(fontSize: AgriTypography.xs),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    ),
  );

  // ── Onglets sans source ───────────────────────────────────────────────────

  Widget _enAttente(String onglet) => Container(
    key: Key('sujet-attente-$onglet'),
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: _carte(),
    child: Column(
      children: [
        const Icon(
          SymbolesAgri.hourglass_empty,
          size: 44,
          color: AgriColors.outlineVariant,
        ),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucune donnée réelle pour cet onglet',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: FontWeight.w600,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          _motifs[onglet]!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Cet onglet reste vide tant qu'une source réelle n'existe pas — le "
          'remplir de valeurs plausibles serait plus trompeur qu\'utile.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      ],
    ),
  );

  static String _ou(String? v) => (v == null || v.isEmpty) ? '—' : v;

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
