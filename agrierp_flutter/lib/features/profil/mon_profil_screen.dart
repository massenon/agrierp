import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_service.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import 'mon_profil_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/mon-profil.html` → Mon Profil.
///
/// ⚠️⚠️ **LE CHANGEMENT DE MOT DE PASSE EST RÉEL.** Il part vers
/// `POST /api/auth/password` (ticket Laravel 15.9), qui vérifie l'ancien mot de
/// passe contre son hachage et journalise `password.updated`. Le prototype se
/// contente de simuler un succès ; ici, « mis à jour » ne s'affiche que si le
/// serveur l'a confirmé, et un échec (réseau, ancien mot de passe faux, règle
/// refusée) reste affiché avec sa cause.
///
/// ⚠️ **RÈGLE : 8 CARACTÈRES, UNE MAJUSCULE, UN CHIFFRE** — décision du
/// commanditaire, celle que le prototype annonce dans le champ. Le serveur la
/// revérifie (`PolitiqueMotDePasse`) ; le contrôle local évite un aller-retour.
/// Elle diffère de `Password::defaults()` du ticket 14.65 (réinitialisation,
/// avec symbole) : cette divergence-là n'est pas tranchée.
///
/// ⚠️ **LE RÔLE N'EST PAS « Administrateur Principal » EN DUR.** Le prototype
/// l'écrit tel quel ; le badge affiche ici le libellé de rôle de la session.
class MonProfilScreen extends StatefulWidget {
  const MonProfilScreen({
    super.key,
    required this.depot,
    required this.session,
    this.changer,
    this.changerPin,
  });

  final MonProfilRepository depot;

  /// Envoi du changement au serveur. `null` : aucune session, donc rien à
  /// changer — l'écran le dit au lieu de simuler.
  final Future<void> Function({
    required String ancien,
    required String nouveau,
    required String confirmation,
  })?
  changer;

  /// Ticket VL-1 — « Changer le code PIN » (verrou local) : (réussi, message). `null` : la section n'est pas montrée.
  ///
  /// ⚠️ **FONCTION PROPRE AU POSTE** : le web n'a pas de verrou ; la section est un ajout assumé (doctrine, art. 5,
  /// exception), qui ne remplace ni ne déplace rien du Blade.
  final Future<(bool, String)> Function({
    required String ancien,
    required String nouveau,
    required String confirmation,
  })?
  changerPin;

  /// Session ouverte, `null` si aucun utilisateur n'est connecté.
  final SessionUtilisateur? session;

  /// `->created_at->format('d/m/Y H:i')` du web (« Dernière connexion », « Date / Heure » du journal). 🔴→✅ Ticket
  /// U12b (reste de S-T11) — un instant du journal d'audit, affiché à l'heure du Bénin quel que soit le réglage de
  /// Windows.
  static String dateHeure(DateTime d) {
    final l = HeureBenin.depuisInstant(d);
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  State<MonProfilScreen> createState() => _MonProfilScreenState();
}

class _MonProfilScreenState extends State<MonProfilScreen> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  final _pinAncien = TextEditingController();
  final _pinNouveau = TextEditingController();
  final _pinConfirmation = TextEditingController();
  (bool, String)? _resultatPin;
  bool _pinEnCours = false;

  DonneesProfil? _donnees;
  Map<String, String> _erreurs = const {};

  /// Résultat du dernier envoi : `null` tant qu'aucun, sinon (réussi, message).
  (bool, String)? _resultat;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    _pinAncien.dispose();
    _pinNouveau.dispose();
    _pinConfirmation.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger(widget.session);
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  Future<void> _soumettrePin() async {
    final changer = widget.changerPin;
    if (_pinEnCours || changer == null) return;
    setState(() {
      _pinEnCours = true;
      _resultatPin = null;
    });
    (bool, String) resultat;
    try {
      resultat = await changer(
        ancien: _pinAncien.text,
        nouveau: _pinNouveau.text,
        confirmation: _pinConfirmation.text,
      );
    } on Object {
      resultat = (false, 'Changement impossible.');
    }
    if (!mounted) return;
    if (resultat.$1) {
      _pinAncien.clear();
      _pinNouveau.clear();
      _pinConfirmation.clear();
    }
    setState(() {
      _pinEnCours = false;
      _resultatPin = resultat;
    });
  }

  Future<void> _soumettre() async {
    if (_enCours) return;

    final erreurs = MonProfilRepository.validerMotDePasse(
      ancien: _ancien.text,
      nouveau: _nouveau.text,
      confirmation: _confirmation.text,
    );

    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _resultat = null;
      });
      return;
    }

    final envoyer = widget.changer;
    if (envoyer == null) {
      setState(() {
        _erreurs = const {};
        _resultat = (false, 'Aucune session ouverte : connectez-vous.');
      });
      return;
    }

    setState(() {
      _erreurs = const {};
      _resultat = null;
      _enCours = true;
    });

    try {
      await envoyer(
        ancien: _ancien.text,
        nouveau: _nouveau.text,
        confirmation: _confirmation.text,
      );
      if (!mounted) return;
      _ancien.clear();
      _nouveau.clear();
      _confirmation.clear();
      setState(() {
        _enCours = false;
        _resultat = (true, 'Mot de passe mis à jour avec succès.');
      });
    } on EchecChangementMotDePasse catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = e.champs;
        _resultat = (false, e.message);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _resultat = (false, 'Changement impossible.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                final colonneGauche = _carteIdentite(d);
                final colonneDroite = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _carteMotDePasse(),
                    const SizedBox(height: AgriSpacing.md),
                    if (widget.changerPin != null) ...[
                      _cartePin(),
                      const SizedBox(height: AgriSpacing.md),
                    ],
                    _carteJournal(d),
                  ],
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entete(large),
                      const SizedBox(height: AgriSpacing.lg),
                      // `lg:grid-cols-[35%_65%]` : deux colonnes dès `lg:`, une
                      // seule empilée en dessous.
                      if (large)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 35, child: colonneGauche),
                            const SizedBox(width: AgriSpacing.md),
                            Expanded(flex: 65, child: colonneDroite),
                          ],
                        )
                      else ...[
                        colonneGauche,
                        const SizedBox(height: AgriSpacing.md),
                        colonneDroite,
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

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
            const Icon(SymbolesAgri.person, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Mon Profil',
              style: TextStyle(
                fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Informations de session, sécurité et journal d'activité personnel.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  BoxDecoration get _carte => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  // ── Colonne gauche : identité et métadonnées de session ──────────────────

  Widget _carteIdentite(DonneesProfil d) {
    final actif = d.actif;

    return Container(
      key: const Key('carte-identite'),
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: _carte,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AgriColors.brandEmerald,
              shape: BoxShape.circle,
            ),
            child: Text(
              d.initiales,
              key: const Key('profil-initiales'),
              style: const TextStyle(
                fontSize: AgriTypography.xl,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Text(
            d.nom.isEmpty ? '—' : d.nom,
            key: const Key('profil-nom'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          Text(
            d.email.isEmpty ? '—' : d.email,
            key: const Key('profil-email'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          if (d.roleLibelle != null) ...[
            const SizedBox(height: AgriSpacing.md),
            Container(
              key: const Key('profil-role'),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AgriColors.brandEmerald.withValues(alpha: 0.10),
                border: Border.all(
                  color: AgriColors.brandEmerald.withValues(alpha: 0.30),
                ),
                borderRadius: BorderRadius.circular(AgriRadius.full),
              ),
              child: Text(
                d.roleLibelle!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandEmerald,
                ),
              ),
            ),
          ],
          const SizedBox(height: AgriSpacing.md),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Métadonnées de Session'.toUpperCase(), style: _petitGras),
                const SizedBox(height: AgriSpacing.xs),
                _metadonnee(
                  'Dernière connexion',
                  d.derniereConnexion == null
                      ? '—'
                      : _dateHeure(d.derniereConnexion!),
                  const Key('profil-derniere-connexion'),
                  gras: true,
                ),
                _metadonnee(
                  'Adresse IP',
                  d.adresseIp ?? '—',
                  const Key('profil-ip'),
                  mono: true,
                ),
                _metadonnee(
                  'Statut du compte',
                  actif == null ? '—' : (actif ? 'Actif' : 'Inactif'),
                  const Key('profil-statut'),
                  gras: true,
                  couleur: actif == null
                      ? null
                      : (actif
                            ? AgriColors.brandEmerald
                            : AgriColors.errorDeep),
                ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.infoBlue.withValues(alpha: 0.10),
              border: Border.all(
                color: AgriColors.infoBlue.withValues(alpha: 0.20),
              ),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              'Ces informations sont en lecture seule. Seul un Directeur '
              'Général peut modifier les détails du profil depuis Paramètres '
              '> Gestion Utilisateurs.',
              style: TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadonnee(
    String libelle,
    String valeur,
    Key cle, {
    bool gras = false,
    bool mono = false,
    Color? couleur,
  }) => Padding(
    padding: const EdgeInsets.only(top: AgriSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          libelle,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(width: AgriSpacing.sm),
        // ⚠️ `Flexible` : une valeur longue (adresse IPv6, date) ne doit pas
        // faire déborder la ligne, elle se tronque.
        Flexible(
          child: Text(
            valeur,
            key: cle,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: gras ? AgriTypography.gras : null,
              fontFamily: mono ? 'Consolas' : null,
              color: couleur ?? AgriColors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Colonne droite : mot de passe ─────────────────────────────────────────

  Widget _carteMotDePasse() => Container(
    key: const Key('carte-mot-de-passe'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.lock, size: 18, color: AgriColors.brandForest),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Modifier le Mot de Passe'.toUpperCase(),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _champ(
                'Ancien mot de passe *',
                _ancien,
                const Key('mdp-ancien'),
                'ancien',
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Nouveau mot de passe *',
                _nouveau,
                const Key('mdp-nouveau'),
                'nouveau',
                aide: 'Min. 8 caractères, 1 majuscule, 1 chiffre',
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Confirmer le nouveau mot de passe *',
                _confirmation,
                const Key('mdp-confirmation'),
                'confirmation',
              ),
              const SizedBox(height: AgriSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: const Key('mdp-envoyer'),
                  onPressed: _enCours ? null : _soumettre,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.lg,
                      vertical: AgriSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AgriRadius.lg),
                    ),
                  ),
                  child: const Text(
                    'Mettre à jour le mot de passe',
                    style: TextStyle(
                      fontSize: AgriTypography.sm,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                ),
              ),
              if (_resultat != null) ...[
                const SizedBox(height: AgriSpacing.md),
                _bandeauResultat(_resultat!.$1, _resultat!.$2),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  /// Ticket VL-1 — « Changer le code PIN » du verrou local (propre au poste).
  Widget _cartePin() => Container(
    key: const Key('carte-pin'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.lock, size: 18, color: AgriColors.brandForest),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Changer le code PIN'.toUpperCase(),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Le code PIN verrouille l'application à chaque lancement, même sans réseau (propre à ce poste).",
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _champ('Ancien code PIN *', _pinAncien, const Key('pin-ancien'), 'pin-ancien', chiffres: true),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Nouveau code PIN *',
                _pinNouveau,
                const Key('pin-nouveau'),
                'pin-nouveau',
                aide: '4 à 6 chiffres',
                chiffres: true,
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Confirmer le nouveau code PIN *',
                _pinConfirmation,
                const Key('pin-confirmation'),
                'pin-confirmation',
                chiffres: true,
              ),
              const SizedBox(height: AgriSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: const Key('pin-envoyer'),
                  onPressed: _pinEnCours ? null : _soumettrePin,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.lg,
                      vertical: AgriSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AgriRadius.lg),
                    ),
                  ),
                  child: const Text(
                    'Mettre à jour le code PIN',
                    style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras),
                  ),
                ),
              ),
              if (_resultatPin != null) ...[
                const SizedBox(height: AgriSpacing.md),
                _bandeauResultat(
                  _resultatPin!.$1,
                  _resultatPin!.$2,
                  cle: _resultatPin!.$1 ? 'pin-reussi' : 'pin-echec',
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    Key cle,
    String champ, {
    String? aide,
    bool chiffres = false,
  }) {
    final erreur = _erreurs[champ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        SizedBox(
          height: 44,
          child: TextField(
            key: cle,
            controller: controleur,
            obscureText: true,
            keyboardType: chiffres ? TextInputType.number : null,
            inputFormatters: chiffres
                ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
                : null,
            style: const TextStyle(fontSize: AgriTypography.sm),
            decoration: InputDecoration(
              hintText: aide,
              hintStyle: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.outline,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
                borderSide: BorderSide(
                  color: erreur == null
                      ? AgriColors.outlineVariant
                      : AgriColors.errorRed,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
                borderSide: BorderSide(
                  color: erreur == null
                      ? AgriColors.brandEmerald
                      : AgriColors.errorRed,
                ),
              ),
            ),
          ),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              erreur,
              key: Key('erreur-$champ'),
              style: const TextStyle(fontSize: 11, color: AgriColors.errorRed),
            ),
          ),
      ],
    );
  }

  /// Vert si le serveur a confirmé, rouge sinon. ⚠️ JAMAIS de vert sans
  /// réponse du serveur : le prototype affiche son succès sans rien envoyer.
  Widget _bandeauResultat(bool reussi, String message, {String? cle}) {
    final couleur = reussi ? AgriColors.brandEmerald : AgriColors.errorRed;

    return Container(
      key: Key(cle ?? (reussi ? 'mdp-reussi' : 'mdp-echec')),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        border: Border.all(color: couleur.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
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

  // ── Colonne droite : journal d'audit ──────────────────────────────────────

  Widget _carteJournal(DonneesProfil d) => Container(
    key: const Key('carte-journal'),
    decoration: _carte,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: AgriSpacing.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AgriColors.outlineVariant),
            ),
          ),
          child: const Text(
            "Journal d'Audit — 10 Dernières Actions",
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        _tableauJournal(d),
        // ⚠️ DIT CE QUE LE POSTE DÉTIENT : deux cents actions pour toute la ferme (U14 : la liste du web, `limit(200)`).
        Padding(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Text(
            "Le poste ne détient que les 200 dernières actions de l'ensemble "
            "de la ferme : ce journal peut compter moins de dix lignes.",
            key: const Key('journal-portee'),
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ),
      ],
    ),
  );

  Widget _tableauJournal(DonneesProfil d) {
    const colonnes = <(String, int)>[
      ('Date / Heure', 3),
      ('Action', 5),
      ('Module', 3),
      ('IP', 3),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 640,
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
                      child: Text(libelle.toUpperCase(), style: _petitGras),
                    ),
                ],
              ),
            ),
            if (d.journal.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  'Aucune action enregistrée pour le moment.',
                  key: Key('journal-vide'),
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (var i = 0; i < d.journal.length; i++)
              Container(
                key: Key('ligne-journal-$i'),
                color: i.isOdd
                    ? AgriColors.surfaceZebra
                    : AgriColors.surfaceCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        d.journal[i].date == null
                            ? '—'
                            : _dateHeure(d.journal[i].date!),
                        style: _cellule,
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(d.journal[i].action, style: _cellule),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        d.journal[i].module ?? '—',
                        style: _cellule.copyWith(color: AgriColors.outline),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        d.journal[i].ip ?? '—',
                        style: _cellule.copyWith(
                          fontFamily: 'Consolas',
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _petitGras = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  static const _cellule = TextStyle(
    fontSize: AgriTypography.xs,
    color: AgriColors.onSurface,
  );

  static String _dateHeure(DateTime d) => MonProfilScreen.dateHeure(d);
}
