import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import 'contact_editeur_repository.dart';

/// `prototype_html/contact-editeur.html` → Contactez l'Éditeur.
///
/// ⚠️⚠️ **L'ENVOI EXIGE LE RÉSEAU, ET LE TEXTE EST CONSERVÉ.** Le serveur envoie
/// un e-mail réel ; hors ligne, l'envoi est refusé par une phrase et le brouillon
/// reste en place — y compris si l'utilisateur ouvre un autre écran, car il est
/// possédé par la coque ([BrouillonContact]). « Envoyé » ne s'affiche que sur
/// réponse du serveur ; le prototype, lui, l'affiche sans rien envoyer.
///
/// ⚠️ **ÉCARTS ASSUMÉS** :
///  * la zone « Capture d'écran » n'est pas portée comme contrôle : le projet n'a
///    pas de sélecteur de fichier, et un bloc cliquable qui ne joint rien serait
///    pire qu'absent (Laravel l'a rendue réelle, le poste ne le peut pas) ;
///  * les coordonnées et la carte « Qui contacter ? » sont celles de Laravel
///    (ticket 15.8), pas les coordonnées de remplissage du prototype.
class ContactEditeurScreen extends StatefulWidget {
  const ContactEditeurScreen({
    super.key,
    required this.depot,
    required this.brouillon,
    this.onAide,
  });

  final ContactEditeurRepository depot;
  final BrouillonContact brouillon;

  /// Ouvre « Aide & À Propos » (lien de la carte « Avant de nous contacter »).
  final VoidCallback? onAide;

  @override
  State<ContactEditeurScreen> createState() => _ContactEditeurScreenState();
}

class _ContactEditeurScreenState extends State<ContactEditeurScreen> {
  static const onglets = <(String, String, IconData)>[
    ('message', 'Envoyer un Message', Icons.mail),
    ('bug', 'Signaler un Bug', Icons.bug_report),
  ];

  BrouillonContact get _b => widget.brouillon;

  Map<String, String> _erreurs = const {};

  /// Dernier retour : (réussi, message).
  (bool, String)? _retour;
  bool _enCours = false;

  Future<void> _envoyer() async {
    if (_enCours) return;
    final bug = _b.onglet == 'bug';

    final erreurs = bug
        ? ContactEditeurRepository.validerBug(
            module: _b.module,
            description: _b.description.text,
          )
        : ContactEditeurRepository.validerMessage(
            objet: _b.objet.text,
            message: _b.message.text,
          );

    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _retour = null;
      });
      return;
    }

    setState(() {
      _erreurs = const {};
      _retour = null;
      _enCours = true;
    });

    try {
      if (bug) {
        await widget.depot.signalerBug(
          module: _b.module,
          description: _b.description.text,
          etapes: _b.etapes.text,
        );
        _b.viderBug();
      } else {
        await widget.depot.envoyerMessage(
          objet: _b.objet.text,
          message: _b.message.text,
        );
        _b.viderMessage();
      }
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _retour = (
          true,
          bug
              ? 'Signalement envoyé — merci pour votre retour.'
              : 'Message envoyé avec succès.',
        );
      });
    } on EchecContact catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreurs = e.champs;
        _retour = (false, e.message);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _retour = (false, 'Envoi impossible.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    final gauche = _carteFormulaire();
    final droite = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _carteCoordonnees(),
        const SizedBox(height: AgriSpacing.md),
        _carteQuiContacter(),
        const SizedBox(height: AgriSpacing.md),
        _carteAvant(),
      ],
    );

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _entete(large),
            const SizedBox(height: AgriSpacing.lg),
            // `lg:grid-cols-[60%_40%]`.
            if (large)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 60, child: gauche),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(flex: 40, child: droite),
                ],
              )
            else ...[
              gauche,
              const SizedBox(height: AgriSpacing.md),
              droite,
            ],
          ],
        ),
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
            const Icon(
              Icons.support_agent,
              size: 26,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              "Contactez l'Éditeur",
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
          "Assistance technique, suggestions et signalement d'anomalies pour "
          'AgriERP.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  BoxDecoration _carte([Color? fond, Color? bordure]) => BoxDecoration(
    color: fond ?? AgriColors.surfaceCard,
    border: Border.all(color: bordure ?? AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  // ── Colonne gauche : les deux formulaires ────────────────────────────────

  Widget _carteFormulaire() {
    final bug = _b.onglet == 'bug';

    return Container(
      key: const Key('carte-formulaire'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AgriColors.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                for (final (cle, titre, _) in onglets)
                  InkWell(
                    key: Key('onglet-contact-$titre'),
                    onTap: () => setState(() {
                      _b.onglet = cle;
                      _erreurs = const {};
                      _retour = null;
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
                            color: _b.onglet == cle
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
                          color: _b.onglet == cle
                              ? AgriColors.brandEmerald
                              : AgriColors.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          if (bug) ..._panneauBug() else ..._panneauMessage(),
          if (_retour != null) ...[
            const SizedBox(height: AgriSpacing.md),
            _bandeau(_retour!.$1, _retour!.$2),
          ],
        ],
      ),
    );
  }

  List<Widget> _panneauMessage() => [
    _champ(
      'Objet *',
      _b.objet,
      const Key('contact-objet'),
      'objet',
      aide: 'ex : Question sur le module Comptabilité',
    ),
    const SizedBox(height: AgriSpacing.md),
    _champ(
      'Message *',
      _b.message,
      const Key('contact-message'),
      'message',
      aide: 'Décrivez votre question ou suggestion...',
      lignes: 6,
    ),
    const SizedBox(height: AgriSpacing.md),
    _bouton(
      const Key('contact-envoyer'),
      Icons.send,
      'Envoyer le Message',
      AgriColors.brandEmerald,
    ),
  ];

  List<Widget> _panneauBug() => [
    _listeModule(),
    const SizedBox(height: AgriSpacing.md),
    _champ(
      'Description du Problème *',
      _b.description,
      const Key('contact-description'),
      'description',
      aide: "Que s'est-il passé ? Que attendiez-vous ?",
      lignes: 4,
    ),
    const SizedBox(height: AgriSpacing.md),
    _champ(
      'Étapes pour Reproduire',
      _b.etapes,
      const Key('contact-etapes'),
      'etapes',
      aide: '1. Aller dans... 2. Cliquer sur...',
      lignes: 3,
    ),
    const SizedBox(height: AgriSpacing.md),
    _zoneCapture(),
    const SizedBox(height: AgriSpacing.md),
    _bouton(
      const Key('contact-signaler'),
      Icons.bug_report,
      'Signaler le Bug',
      AgriColors.errorRed,
    ),
  ];

  static const _etiquette = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.brandForest,
  );

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

  OutlineInputBorder _bordure(String champ, {bool focus = false}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        borderSide: BorderSide(
          color: _erreurs.containsKey(champ)
              ? AgriColors.errorRed
              : focus
              ? AgriColors.brandEmerald
              : AgriColors.outlineVariant,
        ),
      );

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    Key cle,
    String champ, {
    required String aide,
    int lignes = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle.toUpperCase(), style: _etiquette),
      const SizedBox(height: AgriSpacing.xs),
      TextField(
        key: cle,
        controller: controleur,
        minLines: lignes,
        maxLines: lignes,
        style: const TextStyle(fontSize: AgriTypography.sm),
        decoration: InputDecoration(
          hintText: aide,
          hintStyle: const TextStyle(
            fontSize: AgriTypography.sm,
            color: AgriColors.outline,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: lignes == 1 ? 14 : AgriSpacing.sm,
          ),
          enabledBorder: _bordure(champ),
          focusedBorder: _bordure(champ, focus: true),
        ),
      ),
      _erreur(champ),
    ],
  );

  Widget _listeModule() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Module Concerné *'.toUpperCase(), style: _etiquette),
      const SizedBox(height: AgriSpacing.xs),
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _erreurs.containsKey('module')
                ? AgriColors.errorRed
                : AgriColors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('contact-module'),
            value: _b.module,
            isExpanded: true,
            // ⚠️ Le menu déroulant ne reprend pas le style du thème : sans cette
            // base il retombe sur la police par défaut du moteur.
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: AgriTypography.sm,
              color: AgriColors.onSurface,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('-- Sélectionner --'),
              ),
              for (final m in ContactEditeurRepository.modules)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _b.module = v ?? ''),
          ),
        ),
      ),
      _erreur('module'),
    ],
  );

  /// ⚠️ LE BLOC « CAPTURE D'ÉCRAN » EST PRÉSENT MAIS INERTE ET DIT POURQUOI : pas
  /// de sélecteur de fichier au poste. Ni bordure pointillée cliquable ni icône
  /// d'appareil photo qui laisseraient croire qu'on peut joindre quelque chose.
  Widget _zoneCapture() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text("Capture d'Écran (optionnel)".toUpperCase(), style: _etiquette),
      const SizedBox(height: AgriSpacing.xs),
      Container(
        key: const Key('contact-capture'),
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceZebra,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Text(
          "Le poste ne peut pas joindre de capture d'écran. Décrivez le "
          'problème dans les champs ci-dessus ; vous pourrez joindre une image '
          "depuis l'application web.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ),
    ],
  );

  Widget _bouton(Key cle, IconData icone, String libelle, Color couleur) =>
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: cle,
          onPressed: _enCours ? null : _envoyer,
          icon: Icon(icone, size: 18),
          label: Text(
            libelle,
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: couleur,
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.lg,
              vertical: AgriSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
          ),
        ),
      );

  Widget _bandeau(bool reussi, String message) {
    final couleur = reussi ? AgriColors.brandEmerald : AgriColors.errorRed;

    return Container(
      key: Key(reussi ? 'contact-reussi' : 'contact-echec'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: _carte(
        couleur.withValues(alpha: 0.10),
        couleur.withValues(alpha: 0.30),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reussi ? Icons.check_circle : Icons.error,
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

  // ── Colonne droite ───────────────────────────────────────────────────────

  Widget _ligneCoordonnee(IconData icone, Widget contenu) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: AgriColors.brandEmerald),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(child: contenu),
      ],
    ),
  );

  Widget _carteCoordonnees() {
    const texte = TextStyle(fontSize: AgriTypography.xs);

    return Container(
      key: const Key('carte-coordonnees'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Coordonnées de l'Éditeur".toUpperCase(),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          _ligneCoordonnee(
            Icons.person,
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ContactEditeurRepository.editeurNom,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                Text(
                  ContactEditeurRepository.editeurTitre,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
          for (final (i, e) in ContactEditeurRepository.editeurEmails.indexed)
            _ligneCoordonnee(
              i == 0 ? Icons.mail : Icons.alternate_email,
              Text(e, style: texte),
            ),
          for (final (i, t)
              in ContactEditeurRepository.editeurTelephones.indexed)
            _ligneCoordonnee(
              i == 0 ? Icons.call : Icons.smartphone,
              Text(t, style: texte),
            ),
          _ligneCoordonnee(
            Icons.schedule,
            const Text(ContactEditeurRepository.editeurHoraires, style: texte),
          ),
        ],
      ),
    );
  }

  Widget _carteQuiContacter() => Container(
    key: const Key('carte-qui-contacter'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qui contacter ?'.toUpperCase(),
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        _ligneCoordonnee(
          Icons.bug_report,
          const Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
              children: [
                TextSpan(
                  text: 'Le logiciel se comporte mal\n',
                  style: TextStyle(
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                TextSpan(
                  text:
                      "Anomalie, question d'utilisation, évolution : utilisez "
                      'le formulaire ci-contre.',
                ),
              ],
            ),
          ),
        ),
        _ligneCoordonnee(
          Icons.balance,
          const Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
              children: [
                TextSpan(
                  text: 'Un chiffre réglementaire à valider\n',
                  style: TextStyle(
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                TextSpan(
                  text:
                      'Barème IR-PTS / ITS, taux CNSS, plan comptable : '
                      'adressez-vous au ',
                ),
                TextSpan(
                  text: 'Cabinet FAGUEZ SARL',
                  style: TextStyle(
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                TextSpan(
                  text: ', cabinet d\'accompagnement des PME du projet PAEB.',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _carteAvant() => Container(
    key: const Key('carte-avant'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte(
      AgriColors.infoBlue.withValues(alpha: 0.10),
      AgriColors.infoBlue.withValues(alpha: 0.30),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.lightbulb, size: 18, color: AgriColors.infoBlue),
            SizedBox(width: AgriSpacing.xs),
            Text(
              'Avant de nous contacter',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
            children: [
              const TextSpan(text: "Consultez d'abord notre "),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: InkWell(
                  key: const Key('contact-aide'),
                  onTap: widget.onAide,
                  child: const Text(
                    'Aide & FAQ',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
              ),
              const TextSpan(
                text:
                    " - la réponse à votre question s'y trouve peut-être déjà.",
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
