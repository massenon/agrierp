import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/config/parametres_poste.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'appairage_poste.dart';

/// Ticket CFG-2 (décision client du 19/10/2026) — onglet « Appairage » de Paramètres, AU POSTE.
///
/// 🔁 REMPLACE L'ÉCRAN ISOLÉ « PARAMÈTRES DU POSTE » (`parametres_poste_screen.dart`, retiré) : l'entrée « Paramètres
/// du poste » de la barre latérale ouvre désormais le hub Paramètres sur cet onglet. Mêmes règles qu'avant : réservé
/// à l'administrateur (`PermissionsPoste`, l'écran comme le hub), identifiant non modifiable, adresse normalisée et
/// effective au redémarrage — et en plus : environnement (S-T8), compte connecté, état du jeton (S-T1), « Tester la
/// connexion » (`GET /api/auth/me`) et « Réappairer ».
///
/// ⚠️ ÉCART (plateforme) : le web a l'onglet « Postes & Appairage », qui LISTE les postes appairés et révoque leur
/// jeton ; le poste ne connaît que lui-même — il montre son propre appairage et renvoie au web pour la révocation.
class OngletAppairage extends StatefulWidget {
  const OngletAppairage({super.key, required this.appairage});

  final AppairagePoste appairage;

  @override
  State<OngletAppairage> createState() => _OngletAppairageState();
}

class _OngletAppairageState extends State<OngletAppairage> {
  final _adresse = TextEditingController();
  String _enregistree = '';

  /// Ticket H13 — intervalle de la synchronisation automatique, en minutes.
  int? _intervalle;
  EtatJeton? _jeton;

  /// Le test de connexion a reçu 401 / 403 : la session est refusée, même si la synchronisation automatique ne
  /// l'a pas encore vu.
  bool _refuseAuTest = false;
  bool _testEnCours = false;

  AppairagePoste get _a => widget.appairage;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _adresse.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final actuelle = await _a.parametres.adresseServeur();
    final intervalle = await _a.parametres.intervalleSynchronisation();
    final jeton = await _a.etatDuJeton();
    if (!mounted) return;
    setState(() {
      _enregistree = actuelle;
      _adresse.text = actuelle;
      _intervalle = intervalle.inMinutes;
      _jeton = _refuseAuTest && jeton == EtatJeton.present ? EtatJeton.refuse : jeton;
    });
  }

  void _toast(String message, {TypeToast type = TypeToast.succes}) =>
      ToastAgri.afficher(context, message, type: type);

  Future<void> _enregistrerAdresse() async {
    await _a.parametres.definirAdresseServeur(_adresse.text);
    await _charger();
    // ⚠️ Le client HTTP est construit au démarrage : dire qu'il faut relancer évite de croire à une panne réseau
    // alors que l'ancienne adresse est encore en usage.
    if (mounted) {
      _toast("Adresse enregistrée. Redémarrez l'application pour qu'elle prenne effet.");
    }
  }

  Future<void> _changerIntervalle(int? minutes) async {
    if (minutes == null) return;
    await _a.parametres.definirIntervalleSynchronisation(minutes);
    await _charger();
    // L'intervalle est lu à l'ouverture de la session, comme l'adresse au démarrage : le dire.
    if (mounted) {
      _toast('Intervalle enregistré. Il prend effet à la prochaine ouverture de session.');
    }
  }

  Future<void> _tester() async {
    setState(() => _testEnCours = true);
    try {
      final compte = await _a.auth.verifierSession();
      if (!mounted) return;
      _refuseAuTest = false;
      _toast(
        'Connexion réussie : le serveur reconnaît ce poste '
        '(compte ${compte.nom.isEmpty ? '—' : compte.nom}, rôle ${compte.roleLibelle.isEmpty ? compte.role : compte.roleLibelle}).',
      );
    } catch (e) {
      if (!mounted) return;
      final statut = e is DioException ? e.response?.statusCode : null;
      _refuseAuTest = statut == 401 || statut == 403;
      _toast('Test de connexion impossible — ${messageErreur(e)}', type: TypeToast.erreur);
    } finally {
      if (mounted) setState(() => _testEnCours = false);
      await _charger();
    }
  }

  Future<void> _reappairer() async {
    final reappairer = _a.reappairer;
    if (reappairer == null) return;
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.logout,
        couleurIcone: AgriColors.brandEmerald,
        titre: 'Réappairer ce poste',
        message:
            "La session se ferme et l'écran de connexion s'ouvre : une nouvelle connexion délivre à ce poste un "
            'jeton neuf. Les saisies en attente restent sur ce poste ; elles partiront après la reconnexion.',
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('appairage-reappairer-confirmer'),
            libelle: 'Réappairer',
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme == true) await reappairer();
  }

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final session = _a.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Appairage',
          style: TextStyle(
            fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Ce poste et son appairage au serveur : identifiant, environnement, adresse du serveur, compte connecté '
          'et état de la session.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'Identifiant de ce poste',
          [
            SelectableText(
              _a.identifiant,
              key: const Key('identifiant-poste'),
              style: const TextStyle(
                fontSize: AgriTypography.base,
                fontWeight: AgriTypography.gras,
                fontFamily: 'monospace',
                color: AgriColors.brandEmerald,
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            // ⚠️ Non modifiable, et sélectionnable : le support en a besoin pour diagnostiquer un conflit. Le changer
            // romprait l'attribution des saisies déjà envoyées — et le nom du jeton du serveur (S-T2).
            _note(
              "Tiré au premier lancement et conservé. Il identifie ce poste dans l'historique de synchronisation et "
              "nomme son jeton sur le serveur (Paramètres > Postes & Appairage du web) : il ne peut pas être modifié.",
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'Environnement',
          [
            Text(
              _a.environnement.libelle,
              key: const Key('appairage-environnement'),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            _note(
              'Fixé à la construction du poste. Serveur par défaut de cet environnement : '
              '${_a.environnement.adresseParDefaut}.',
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'Adresse du serveur',
          [
            TextField(
              key: const Key('adresse-serveur'),
              controller: _adresse,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                hintText: 'https://agrierp.fermeolouwachegoun.com',
                helperText: "Adresse de l'espace web LogiAgriERP.",
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AgriSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actuelle : $_enregistree',
                        key: const Key('adresse-actuelle'),
                        style: const TextStyle(fontSize: 11, color: AgriColors.outline),
                      ),
                      if (_enregistree.isNotEmpty && _a.adresseEnUsage != _enregistree)
                        Text(
                          'En usage jusqu\'au redémarrage : ${_a.adresseEnUsage}',
                          key: const Key('adresse-en-usage'),
                          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  key: const Key('enregistrer-adresse'),
                  onPressed: _enregistrerAdresse,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'Synchronisation automatique',
          [
            DropdownButton<int>(
              key: const Key('intervalle-synchronisation'),
              value: _intervalle,
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
              items: [
                for (final m in ParametresPoste.intervallesProposes)
                  DropdownMenuItem(value: m, child: Text('Toutes les $m minutes')),
              ],
              onChanged: _changerIntervalle,
            ),
            const SizedBox(height: AgriSpacing.xs),
            _note(
              'Toutes les 5 minutes par défaut. Le poste se synchronise aussi à l\'ouverture de la session, quelques '
              'secondes après une vente, une fiche journalière ou un soin, au retour du réseau et à la fermeture. '
              'Après un échec réseau ou une erreur du serveur, il réessaie après 30 s, 2 min, 5 min, 15 min, puis '
              'toutes les heures. Une session expirée ou un accès refusé arrête la synchronisation automatique '
              'jusqu\'à la reconnexion.',
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'Compte connecté',
          [
            _ligne('Nom', session?.nom, const Key('appairage-compte-nom')),
            _ligne('Identifiant', session?.identifiant, const Key('appairage-compte-identifiant')),
            _ligne(
              'Rôle',
              session == null ? null : (session.roleLibelle.isEmpty ? session.role : session.roleLibelle),
              const Key('appairage-compte-role'),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _carte(
          'État du jeton',
          [
            Row(
              children: [
                _pastille(_jeton),
                const SizedBox(width: AgriSpacing.sm),
                Expanded(child: _note(_jeton?.explication ?? '—')),
              ],
            ),
            const SizedBox(height: AgriSpacing.md),
            Wrap(
              spacing: AgriSpacing.sm,
              runSpacing: AgriSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const Key('appairage-tester'),
                  onPressed: _testEnCours ? null : _tester,
                  icon: const Icon(SymbolesAgri.sync, size: 18),
                  label: const Text('Tester la connexion'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgriColors.brandForest,
                    side: const BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                if (_a.reappairer != null)
                  FilledButton.icon(
                    key: const Key('appairage-reappairer'),
                    onPressed: _reappairer,
                    icon: const Icon(SymbolesAgri.logout, size: 18),
                    label: const Text('Réappairer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AgriColors.brandEmerald,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AgriSpacing.sm),
            _note(
              "Un administrateur peut révoquer l'appairage de ce poste depuis le web (Paramètres > Postes & "
              'Appairage) : le poste ne synchronise plus jusqu\'à une nouvelle connexion. « Réappairer » ferme la '
              'session et rouvre la connexion ; les saisies en attente restent sur le poste.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _carte(String titre, List<Widget> enfants) => Container(
    key: Key('appairage-carte-$titre'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
        ),
        const SizedBox(height: AgriSpacing.xs),
        ...enfants,
      ],
    ),
  );

  Widget _note(String texte) => Text(texte, style: const TextStyle(fontSize: 11, color: AgriColors.outline));

  Widget _ligne(String libelle, String? valeur, Key cle) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            libelle.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline),
          ),
        ),
        Expanded(
          child: Text(
            valeur == null || valeur.isEmpty ? '—' : valeur,
            key: cle,
            style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
          ),
        ),
      ],
    ),
  );

  Widget _pastille(EtatJeton? etat) {
    final couleur = switch (etat) {
      EtatJeton.present => AgriColors.brandEmerald,
      EtatJeton.refuse => AgriColors.errorDeep,
      EtatJeton.absent => AgriColors.errorDeep,
      _ => AgriColors.outline,
    };
    return Container(
      key: const Key('appairage-etat-jeton'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etat?.libelle ?? '—',
        style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: couleur),
      ),
    );
  }
}
