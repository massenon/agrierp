import 'package:flutter/material.dart';

import '../../core/config/envoi_email_test.dart';
import '../../core/config/parametres_smtp.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';

/// Ticket CFG-2 (décision client du 19/10/2026, D-CFG-2) — onglet « Email (SMTP) » de Paramètres, AU POSTE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5) : structure, libellés, boutons et messages sont ceux de
/// `email-smtp.blade.php` / `EmailSmtp.php` (ticket CFG-1) — deux cartes « Serveur SMTP » et « Envoyer un e-mail
/// de test », mot de passe jamais réaffiché (« Mot de passe enregistré », « Effacer le mot de passe » confirmé),
/// champ vide = inchangé. `test/email_smtp_blade_test.dart` lit le Blade et le compare à ce fichier.
///
/// ⚠️ ÉCART (plateforme) : le réglage est PROPRE À CE POSTE, en réglages locaux et au coffre du système ; celui du
/// web vit dans `company_settings` et ne descend jamais (ticket 14.84). Les deux ne se synchronisent pas.
class OngletEmailSmtp extends StatefulWidget {
  const OngletEmailSmtp({
    super.key,
    required this.parametres,
    required this.envoi,
  });

  final ParametresSmtp parametres;
  final EnvoiEmailTest envoi;

  @override
  State<OngletEmailSmtp> createState() => _OngletEmailSmtpState();
}

class _OngletEmailSmtpState extends State<OngletEmailSmtp> {
  final _hote = TextEditingController();
  final _port = TextEditingController(text: '${ParametresSmtp.portParDefaut}');
  final _utilisateur = TextEditingController();
  final _motDePasse = TextEditingController();
  final _expediteur = TextEditingController();
  final _destinataire = TextEditingController();
  SecuriteSmtp _securite = SecuriteSmtp.tls;
  ConfigurationSmtp? _config;
  Map<String, String> _erreurs = const {};
  bool _envoiEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger(initial: true);
  }

  @override
  void dispose() {
    for (final c in [_hote, _port, _utilisateur, _motDePasse, _expediteur, _destinataire]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger({bool initial = false}) async {
    final c = await widget.parametres.charger();
    if (!mounted) return;
    setState(() {
      _config = c;
      if (initial) {
        _hote.text = c.hote;
        _port.text = '${c.port}';
        _securite = c.securite;
        _utilisateur.text = c.utilisateur;
        _expediteur.text = c.expediteur;
        // Comme au web : le destinataire proposé est l'expéditeur réel.
        _destinataire.text = c.adresseExpedition ?? '';
      }
    });
  }

  void _toast(String message, {TypeToast type = TypeToast.succes}) =>
      ToastAgri.afficher(context, message, type: type);

  Future<void> _enregistrer() async {
    final erreurs = ParametresSmtp.erreursDeSaisie(
      hote: _hote.text,
      port: _port.text,
      utilisateur: _utilisateur.text,
      expediteur: _expediteur.text,
    );
    setState(() => _erreurs = erreurs);
    if (erreurs.isNotEmpty) return;

    try {
      await widget.parametres.enregistrer(
        hote: _hote.text,
        port: int.parse(_port.text.trim()),
        securite: _securite,
        utilisateur: _utilisateur.text,
        expediteur: _expediteur.text,
        // ⚠️ Vide : le mot de passe au coffre est conservé.
        motDePasse: _motDePasse.text,
      );
    } catch (e) {
      if (mounted) _toast(messageErreur(e), type: TypeToast.erreur);
      return;
    }
    _motDePasse.clear();
    await _charger();
    if (mounted) _toast('Configuration SMTP enregistrée avec succès.');
  }

  Future<void> _effacerMotDePasse() async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.warning,
        couleurIcone: AgriColors.errorDeep,
        titre: 'Effacer le mot de passe',
        message:
            'Le mot de passe SMTP enregistré sera supprimé(e) définitivement. '
            'Cette action est irréversible.',
        detail: const Text(
          "Si le serveur d'envoi exige une authentification, aucun e-mail ne partira plus tant qu'un nouveau "
          "mot de passe n'aura pas été saisi.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
        ),
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('smtp-effacer-confirmer'),
            libelle: 'Effacer le mot de passe',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await widget.parametres.effacerMotDePasse();
    _motDePasse.clear();
    await _charger();
    if (mounted) _toast('Mot de passe SMTP effacé.');
  }

  Future<void> _envoyerTest() async {
    setState(() => _envoiEnCours = true);
    try {
      final message = await widget.envoi.envoyer(_destinataire.text);
      if (mounted) _toast(message);
    } on EchecEnvoiEmail catch (e) {
      if (mounted) _toast(e.message, type: TypeToast.erreur);
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final serveur = _carteServeur();
    final test = _carteTest();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Email (SMTP)',
          style: TextStyle(
            fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          "Serveur d'envoi des e-mails de la ferme (relances, notifications, réinitialisation des mots de "
          "passe). Une seule configuration pour toute l'application.",
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: serveur),
              const SizedBox(width: AgriSpacing.md),
              Expanded(child: test),
            ],
          )
        else ...[
          serveur,
          const SizedBox(height: AgriSpacing.md),
          test,
        ],
      ],
    );
  }

  Widget _carte({required Key cle, required IconData icone, required String titre, required List<Widget> enfants}) =>
      Container(
        key: cle,
        padding: const EdgeInsets.all(AgriSpacing.lg),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
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
                      fontSize: AgriTypography.sm,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.md),
            ...enfants,
          ],
        ),
      );

  Widget _carteServeur() {
    final enregistre = _config?.motDePasseEnregistre ?? false;

    return _carte(
      cle: const Key('smtp-carte-serveur'),
      icone: SymbolesAgri.mail,
      titre: 'Serveur SMTP',
      enfants: [
        _champ('Hôte SMTP *', _hote, const Key('smtp-hote'), 'hote', aide: 'ex : smtp.gmail.com'),
        const SizedBox(height: AgriSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _champ('Port *', _port, const Key('smtp-port'), 'port', aide: '587', clavierNumerique: true),
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(child: _selecteurSecurite()),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _champ(
          'Utilisateur SMTP',
          _utilisateur,
          const Key('smtp-utilisateur'),
          'utilisateur',
          aide: 'ex : notifications@olouwachegoun.bj',
        ),
        const SizedBox(height: AgriSpacing.md),
        _champ(
          'Mot de Passe SMTP',
          _motDePasse,
          const Key('smtp-mot-de-passe'),
          'mot_de_passe',
          aide: 'Laisser vide pour conserver le mot de passe actuel',
          masque: true,
        ),
        const SizedBox(height: AgriSpacing.xs),
        Row(
          children: [
            Expanded(
              child: enregistre
                  ? const Row(
                      key: Key('smtp-mot-de-passe-etat'),
                      children: [
                        Icon(SymbolesAgri.lock, size: 14, color: AgriColors.brandEmerald),
                        SizedBox(width: 4),
                        Text(
                          'Mot de passe enregistré',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: AgriTypography.gras,
                            color: AgriColors.brandEmerald,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Aucun mot de passe enregistré',
                      key: Key('smtp-mot-de-passe-etat'),
                      style: TextStyle(fontSize: 10, color: AgriColors.outline),
                    ),
            ),
            if (enregistre)
              TextButton(
                key: const Key('smtp-effacer-mot-de-passe'),
                onPressed: _effacerMotDePasse,
                style: TextButton.styleFrom(foregroundColor: AgriColors.errorDeep),
                child: const Text(
                  'Effacer le mot de passe',
                  style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras),
                ),
              ),
          ],
        ),
        // ⚠️ ÉCART (plateforme) : « Chiffré en base » au web ; au poste, le coffre du système.
        const Text(
          'Gardé dans le coffre du système de ce poste — jamais en base, jamais synchronisé, jamais réaffiché '
          'en clair une fois enregistré.',
          style: TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        _champ(
          "Adresse d'Expédition",
          _expediteur,
          const Key('smtp-expediteur'),
          'expediteur',
          aide: _config?.emailDeContact ?? 'ex : contact@olouwachegoun.bj',
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Vide : l'e-mail de contact (Données de l'Entreprise) sert d'expéditeur.",
          style: TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        FilledButton(
          key: const Key('smtp-enregistrer'),
          onPressed: _enregistrer,
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
          ),
          child: const Text(
            'Enregistrer la Configuration SMTP',
            style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras),
          ),
        ),
      ],
    );
  }

  Widget _carteTest() => _carte(
    cle: const Key('smtp-carte-test'),
    icone: SymbolesAgri.send,
    titre: 'Envoyer un e-mail de test',
    enfants: [
      const Text(
        "Le test emploie la configuration enregistrée : enregistrez d'abord une modification avant de la "
        'tester. Un e-mail part réellement.',
        style: TextStyle(fontSize: 11, color: AgriColors.outline),
      ),
      const SizedBox(height: AgriSpacing.md),
      _champ(
        'Destinataire du test',
        _destinataire,
        const Key('smtp-destinataire'),
        'destinataire',
        aide: 'Envoyer un e-mail de test à...',
      ),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('smtp-envoyer-test'),
          onPressed: _envoiEnCours ? null : _envoyerTest,
          icon: const Icon(SymbolesAgri.send, size: 18),
          label: const Text(
            'Envoyer un e-mail de test',
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            side: const BorderSide(color: AgriColors.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      Container(
        padding: const EdgeInsets.all(AgriSpacing.sm),
        decoration: BoxDecoration(
          color: AgriColors.surfaceZebra,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Text(
          "Ce réglage est propre à ce poste : il n'est ni envoyé au serveur ni reçu de lui. Le site a sa propre "
          'configuration (Paramètres > Email (SMTP) du web).',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      ),
    ],
  );

  Widget _selecteurSecurite() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _libelle('Sécurité'),
      const SizedBox(height: AgriSpacing.xs),
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<SecuriteSmtp>(
            key: const Key('smtp-securite'),
            value: _securite,
            isExpanded: true,
            style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
            items: [
              for (final s in SecuriteSmtp.values) DropdownMenuItem(value: s, child: Text(s.libelle)),
            ],
            onChanged: (s) {
              if (s != null) setState(() => _securite = s);
            },
          ),
        ),
      ),
    ],
  );

  Widget _libelle(String libelle) => Text(
    libelle.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
  );

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    Key cle,
    String champ, {
    String? aide,
    bool masque = false,
    bool clavierNumerique = false,
  }) {
    final erreur = _erreurs[champ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _libelle(libelle),
        const SizedBox(height: AgriSpacing.xs),
        SizedBox(
          height: 44,
          child: TextField(
            key: cle,
            controller: controleur,
            obscureText: masque,
            enableSuggestions: !masque,
            autocorrect: !masque,
            keyboardType: clavierNumerique ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: AgriTypography.sm),
            decoration: InputDecoration(
              hintText: aide,
              hintStyle: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline),
              contentPadding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
                borderSide: BorderSide(color: erreur == null ? AgriColors.outlineVariant : AgriColors.errorRed),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
                borderSide: BorderSide(color: erreur == null ? AgriColors.brandEmerald : AgriColors.errorRed),
              ),
            ),
          ),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              erreur,
              key: Key('erreur-smtp-$champ'),
              style: const TextStyle(fontSize: 11, color: AgriColors.errorRed),
            ),
          ),
      ],
    );
  }
}
