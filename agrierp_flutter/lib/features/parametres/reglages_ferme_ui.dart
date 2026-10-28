import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../comptabilite/documents_comptabilite.dart';
import '../rh/calcul_paie.dart';
import 'reglages_ferme_repository.dart';

/// Tickets PA-2, PA-3, PA-4, PA-7, PA-8 — modales et sous-pages des réglages de la ferme. Les libellés sont ceux des Blade
/// (`donnees-entreprise`, `bareme-its`, `integrations`, `modes-paiement`, `roles-permissions`). Chaque geste écrit une DEMANDE.

Widget _etiquette(String texte) => Padding(
  padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
  child: Text(texte.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
);

Widget _erreur(String? texte, Key cle) => texte == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(texte, key: cle, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
      );

/// Un champ de texte étiqueté, clé `<prefixe>-<cle>`, erreur `<prefixe>-erreur-<cle>`.
Widget champReglage(String prefixe, String cle, String etiquette, TextEditingController c, Map<String, String> erreurs, {String? indice, bool nombre = false, bool secret = false}) => Padding(
  padding: const EdgeInsets.only(bottom: AgriSpacing.md),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _etiquette(etiquette),
      TextField(
        key: Key('$prefixe-$cle'),
        controller: c,
        obscureText: secret,
        keyboardType: nombre ? TextInputType.number : null,
        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: indice),
      ),
      _erreur(erreurs[cle], Key('$prefixe-erreur-$cle')),
    ],
  ),
);

Widget _formulaire(Map<String, String> erreurs, String prefixe, List<Widget> champs) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (erreurs['formulaire'] != null)
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.md),
        child: Text(erreurs['formulaire']!, key: Key('$prefixe-erreur-formulaire'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
      ),
    ...champs,
  ],
);

// ── PA-3 · Données de l'entreprise ─────────────────────────────────────────

Future<bool> ouvrirEntreprise({required BuildContext context, required ReglagesFermeRepository depot, required CompanySetting? existante, required bool estAdmin}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleEntreprise(depot: depot, e: existante, estAdmin: estAdmin),
  );
  return ok == true;
}

class _ModaleEntreprise extends StatefulWidget {
  const _ModaleEntreprise({required this.depot, required this.e, required this.estAdmin});

  final ReglagesFermeRepository depot;
  final CompanySetting? e;
  final bool estAdmin;

  @override
  State<_ModaleEntreprise> createState() => _ModaleEntrepriseState();
}

class _ModaleEntrepriseState extends State<_ModaleEntreprise> {
  static String _n(double? v, double defaut) => ((v ?? defaut) == (v ?? defaut).roundToDouble() ? (v ?? defaut).round().toString() : (v ?? defaut).toString());

  late final _raison = TextEditingController(text: widget.e?.companyName ?? '');
  late final _promoteur = TextEditingController(text: widget.e?.promoterName ?? '');
  late final _adresse = TextEditingController(text: widget.e?.address ?? '');
  late final _tel = TextEditingController(text: widget.e?.phone ?? '');
  late final _email = TextEditingController(text: widget.e?.email ?? '');
  late final _ifu = TextEditingController(text: widget.e?.ifu ?? '');
  late final _rccm = TextEditingController(text: widget.e?.rccm ?? '');
  late final _vps = TextEditingController(text: _n(widget.e?.vpsRate, 4));
  late final _salarie = TextEditingController(text: _n(widget.e?.cnssEmployeeRate, 3.6));
  late final _pension = TextEditingController(text: _n(widget.e?.cnssEmployerPensionRate, 6.4));
  late final _famille = TextEditingController(text: _n(widget.e?.cnssEmployerFamilyRate, 9));
  late final _risque = TextEditingController(text: _n(widget.e?.cnssEmployerRiskRate, 2));
  late bool _tva = widget.e?.tvaEnabled ?? true;
  Map<String, String> _erreurs = const {};

  Future<void> _enregistrer() async {
    try {
      await widget.depot.enregistrerEntreprise(
        raisonSociale: _raison.text, promoteur: _promoteur.text, adresse: _adresse.text, telephone: _tel.text, email: _email.text,
        ifu: _ifu.text, rccm: _rccm.text, tva: _tva, vps: _vps.text, cnssSalarie: _salarie.text, cnssPension: _pension.text,
        cnssFamille: _famille.text, cnssRisque: _risque.text, estAdmin: widget.estAdmin,
      );
    } on ReglageRefuse catch (r) {
      setState(() => _erreurs = r.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const p = 'entreprise';
    return ModaleAgri(
      titre: "Données de l'Entreprise",
      largeur: LargeurModale.lg,
      contenu: SingleChildScrollView(
        child: _formulaire(_erreurs, p, [
          champReglage(p, 'companyName', 'Raison Sociale *', _raison, _erreurs),
          champReglage(p, 'promoterName', 'Nom du Promoteur', _promoteur, _erreurs),
          champReglage(p, 'address', "Adresse du Siège d'Exploitation", _adresse, _erreurs),
          champReglage(p, 'phone', 'Téléphone Principal', _tel, _erreurs, indice: '+229 XX XX XX XX'),
          champReglage(p, 'email', 'Email de Contact', _email, _erreurs, indice: 'contact@fermeolouwachegoun.com'),
          champReglage(p, 'ifu', 'Identifiant Fiscal Unique (IFU) *', _ifu, _erreurs, indice: 'ex : 3202601234567'),
          champReglage(p, 'rccm', 'Registre du Commerce (RCCM)', _rccm, _erreurs),
          SwitchListTile(
            key: const Key('entreprise-tva'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Exploitation assujettie à la TVA', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras)),
            value: _tva,
            onChanged: (v) => setState(() => _tva = v),
          ),
          const SizedBox(height: AgriSpacing.sm),
          champReglage(p, 'cnssEmployeeRate', 'CNSS salariale (%)', _salarie, _erreurs, nombre: true),
          champReglage(p, 'vpsRate', 'VPS — Versement Patronal sur Salaires (%)', _vps, _erreurs, nombre: true),
          champReglage(p, 'cnssEmployerPensionRate', 'CNSS patronale — pensions (%)', _pension, _erreurs, nombre: true),
          champReglage(p, 'cnssEmployerFamilyRate', 'CNSS patronale — prestations familiales (%)', _famille, _erreurs, nombre: true),
          champReglage(p, 'cnssEmployerRiskRate', 'CNSS patronale — risques professionnels (%)', _risque, _erreurs, nombre: true),
        ]),
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
        BoutonModalePrimaire(key: const Key('entreprise-enregistrer'), libelle: 'Enregistrer les Modifications', onPressed: _enregistrer),
      ],
    );
  }
}

// ── PA-7 · Barème IR-PTS / ITS ─────────────────────────────────────────────

class PageBaremeIts extends StatefulWidget {
  const PageBaremeIts({super.key, required this.depot, required this.estAdmin, required this.surRetour});

  final ReglagesFermeRepository depot;
  final bool estAdmin;
  final VoidCallback surRetour;

  @override
  State<PageBaremeIts> createState() => _PageBaremeItsState();
}

class _LigneTranche {
  _LigneTranche(String de, String a, String taux)
      : de = TextEditingController(text: de),
        a = TextEditingController(text: a),
        taux = TextEditingController(text: taux);

  final TextEditingController de;
  final TextEditingController a;
  final TextEditingController taux;
}

class _PageBaremeItsState extends State<PageBaremeIts> {
  List<_LigneTranche>? _lignes;
  CompanySetting? _entreprise;
  final _brut = TextEditingController(text: '150000');
  String? _erreur;
  bool _enregistre = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> _charger() async {
    final b = await widget.depot.bareme();
    final e = await widget.depot.entreprise();
    if (!mounted) return;
    setState(() {
      _entreprise = e;
      _lignes = b.isEmpty
          ? [_LigneTranche('0', '', '0')]
          : [for (final t in b) _LigneTranche(_n(t.fromAmount), t.toAmount == null ? '' : _n(t.toAmount!), _n(t.rate))];
    });
  }

  bool get _modifiable => !(_entreprise?.payrollLocked ?? false) || widget.estAdmin;

  List<TrancheSaisie> _saisies() => [
    for (final l in _lignes!)
      TrancheSaisie(
        de: double.tryParse(l.de.text.replaceAll(',', '.')) ?? 0,
        a: l.a.text.trim().isEmpty ? null : double.tryParse(l.a.text.replaceAll(',', '.')),
        taux: double.tryParse(l.taux.text.replaceAll(',', '.')) ?? 0,
      ),
  ];

  Future<void> _enregistrer() async {
    try {
      await widget.depot.enregistrerBareme(_saisies(), estAdmin: widget.estAdmin);
      setState(() {
        _erreur = null;
        _enregistre = true;
      });
    } on ReglageRefuse catch (r) {
      setState(() {
        _erreur = r.toString();
        _enregistre = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lignes = _lignes;
    if (lignes == null) return const Center(child: CircularProgressIndicator());

    final brut = double.tryParse(_brut.text.replaceAll(',', '.')) ?? 0;
    final e = _entreprise;
    final paie = CalculPaie.calculer(
      brut,
      0,
      bareme: [for (final t in _saisies()) TrancheIts(plancher: t.de, plafond: t.a, taux: t.taux)],
      taux: TauxPaie(
        cnssSalarie: e?.cnssEmployeeRate, vps: e?.vpsRate, cnssPatronalePension: e?.cnssEmployerPensionRate,
        cnssPatronaleFamille: e?.cnssEmployerFamilyRate, cnssPatronaleRisque: e?.cnssEmployerRiskRate,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('bareme-retour'),
            onPressed: widget.surRetour,
            icon: const Icon(SymbolesAgri.arrow_back, size: 18),
            label: const Text("Données de l'Entreprise", style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
            style: TextButton.styleFrom(foregroundColor: AgriColors.brandEmerald),
          ),
        ),
        Row(children: const [
          Icon(SymbolesAgri.functions, size: 26, color: AgriColors.brandEmerald),
          SizedBox(width: AgriSpacing.xs),
          Text('Barème IR-PTS / ITS', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        ]),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Impôt sur les Traitements et Salaires — retenu à la source, progressif, assis sur le net imposable (salaire dû moins CNSS salariale).',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        if (!_modifiable)
          Container(
            key: const Key('bareme-arrete'),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
            child: Text(
              'Barème arrêté le ${_entreprise?.payrollEditedAt ?? '—'}. Seul un administrateur peut le modifier. Les bulletins déjà réglés ne sont jamais recalculés.',
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ),
        const SizedBox(height: AgriSpacing.md),
        const Text("Tranches d'imposition", style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.sm),
        for (var i = 0; i < lignes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
            child: Row(
              children: [
                for (final (cle, c, etiquette) in [('de', lignes[i].de, 'De (FCFA)'), ('a', lignes[i].a, 'À (FCFA)'), ('taux', lignes[i].taux, 'Taux (%)')])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AgriSpacing.sm),
                      child: TextField(
                        key: Key('bareme-$cle-$i'),
                        controller: c,
                        enabled: _modifiable,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: etiquette, hintText: cle == 'a' ? 'sans plafond' : null),
                      ),
                    ),
                  ),
                if (_modifiable)
                  IconButton(
                    key: Key('bareme-retirer-$i'),
                    tooltip: 'Retirer',
                    onPressed: () => setState(() => lignes.removeAt(i)),
                    icon: const Icon(SymbolesAgri.delete, size: 18, color: AgriColors.errorDeep),
                  ),
              ],
            ),
          ),
        if (_modifiable)
          Row(children: [
            OutlinedButton.icon(
              key: const Key('bareme-ajouter'),
              onPressed: () => setState(() {
                final der = lignes.isEmpty ? null : double.tryParse(lignes.last.a.text);
                lignes.add(_LigneTranche(der == null ? '0' : _n(der), '', '0'));
              }),
              icon: const Icon(SymbolesAgri.add, size: 18),
              label: const Text('Ajouter une tranche', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: AgriSpacing.sm),
            ElevatedButton.icon(
              key: const Key('bareme-enregistrer'),
              onPressed: _enregistrer,
              icon: const Icon(SymbolesAgri.save, size: 18),
              style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
              label: const Text('Enregistrer le barème', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
            ),
          ]),
        if (_erreur != null) _erreur_(_erreur!, const Key('bareme-erreur')),
        if (_enregistre)
          const Padding(
            padding: EdgeInsets.only(top: AgriSpacing.sm),
            child: Text('Barème demandé au serveur : il sera appliqué à la prochaine synchronisation.', key: Key('bareme-demande'), style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
          ),
        const SizedBox(height: AgriSpacing.lg),
        const Text('Simulation', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.sm),
        SizedBox(
          width: 280,
          child: TextField(
            key: const Key('bareme-brut'),
            controller: _brut,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Salaire brut mensuel (FCFA)'),
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        for (final (cle, libelle, valeur) in [
          ('du', 'Salaire dû', paie.salaireDu),
          ('cnss', '− CNSS salariale', paie.cnssSalariale),
          ('imposable', '= Net imposable', paie.netImposable),
          ('its', '− ITS', paie.its),
          ('net', 'NET À PAYER', paie.net),
        ])
          Text('$libelle : ${DocumentsComptabilite.montant(valeur)} FCFA', key: Key('bareme-sim-$cle'), style: const TextStyle(fontSize: AgriTypography.xs)),
        if (!paie.baremeItsRenseigne)
          const Padding(
            padding: EdgeInsets.only(top: AgriSpacing.xs),
            child: Text("Aucune tranche enregistrée : l'ITS est nul faute de barème, et non parce que le salaire serait sous le seuil.", style: TextStyle(fontSize: 11, color: AgriColors.outline)),
          ),
      ],
    );
  }

  Widget _erreur_(String t, Key k) => Padding(
    padding: const EdgeInsets.only(top: AgriSpacing.sm),
    child: Text(t, key: k, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
  );
}

// ── PA-8 · Intégrations & Notifications (SMS) ──────────────────────────────

class PageIntegrationsSms extends StatefulWidget {
  const PageIntegrationsSms({super.key, required this.depot, required this.surRetour});

  final ReglagesFermeRepository depot;
  final VoidCallback surRetour;

  @override
  State<PageIntegrationsSms> createState() => _PageIntegrationsSmsState();
}

class _PageIntegrationsSmsState extends State<PageIntegrationsSms> {
  CompanySetting? _e;
  String _fournisseur = '';
  final _sid = TextEditingController();
  final _de = TextEditingController();
  final _jeton = TextEditingController();
  final _cle = TextEditingController();
  final _nom = TextEditingController();
  final _secret = TextEditingController();
  Map<String, String> _erreurs = const {};
  bool _demande = false;

  @override
  void initState() {
    super.initState();
    widget.depot.entreprise().then((e) {
      if (!mounted) return;
      setState(() {
        _e = e;
        _fournisseur = e?.smsProvider ?? '';
        _sid.text = e?.twilioAccountSid ?? '';
        _de.text = e?.twilioFromNumber ?? '';
        _nom.text = e?.vonageFromName ?? '';
      });
    });
  }

  Future<void> _enregistrer() async {
    try {
      await widget.depot.enregistrerSms(
        fournisseur: _fournisseur, twilioSid: _sid.text, twilioDe: _de.text, twilioJeton: _jeton.text,
        vonageCle: _cle.text, vonageDe: _nom.text, vonageSecret: _secret.text,
      );
      _jeton.clear();
      _secret.clear();
      setState(() {
        _erreurs = const {};
        _demande = true;
      });
    } on ReglageRefuse catch (r) {
      setState(() => _erreurs = r.erreurs);
    }
  }

  @override
  Widget build(BuildContext context) {
    const p = 'sms';
    final secretPose = _e?.smsIdentifiantsPoses ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('sms-retour'),
            onPressed: widget.surRetour,
            icon: const Icon(SymbolesAgri.arrow_back, size: 18),
            label: const Text("Données de l'Entreprise", style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
            style: TextButton.styleFrom(foregroundColor: AgriColors.brandEmerald),
          ),
        ),
        const Text('Intégrations & Notifications', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        const Text('Configuration réelle des canaux de communication sortants (Email SMTP, SMS).', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
        const SizedBox(height: AgriSpacing.md),
        const Text('SMS — Fournisseur API', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.sm),
        _etiquette('Fournisseur *'),
        DropdownButtonFormField<String>(
          key: const Key('sms-fournisseur'),
          initialValue: _fournisseur,
          isDense: true,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
          items: const [
            DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
            DropdownMenuItem(value: 'twilio', child: Text('Twilio')),
            DropdownMenuItem(value: 'vonage', child: Text('Vonage')),
          ],
          onChanged: (v) => setState(() => _fournisseur = v ?? ''),
        ),
        _erreur(_erreurs['smsProvider'], const Key('sms-erreur-smsProvider')),
        const SizedBox(height: AgriSpacing.md),
        if (_fournisseur == 'twilio') ...[
          champReglage(p, 'sid', 'Account SID', _sid, _erreurs),
          champReglage(p, 'jeton', 'Auth Token', _jeton, _erreurs, secret: true, indice: secretPose ? 'Laisser vide pour conserver le token actuel' : null),
          champReglage(p, 'de', "Numéro d'Envoi", _de, _erreurs, indice: 'ex : +14155238886'),
        ],
        if (_fournisseur == 'vonage') ...[
          champReglage(p, 'cle', 'API Key', _cle, _erreurs, indice: secretPose ? 'Laisser vide pour conserver la clé actuelle' : null),
          champReglage(p, 'secret', 'API Secret', _secret, _erreurs, secret: true, indice: secretPose ? 'Laisser vide pour conserver le secret actuel' : null),
          champReglage(p, 'nom', "Nom d'Expéditeur", _nom, _erreurs, indice: 'ex : AgriERP'),
        ],
        ElevatedButton(
          key: const Key('sms-enregistrer'),
          onPressed: _enregistrer,
          style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: const Text('Enregistrer la Configuration SMS', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        ),
        if (_demande)
          const Padding(
            padding: EdgeInsets.only(top: AgriSpacing.sm),
            child: Text('Configuration demandée au serveur : elle sera appliquée à la prochaine synchronisation. Le jeton part une seule fois.', key: Key('sms-demande'), style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
          ),
        const SizedBox(height: AgriSpacing.md),
        const Text(
          "L'envoi d'un SMS de test se fait en ligne depuis la surface web : il appelle le fournisseur et attend sa réponse. "
          'WhatsApp ne nécessite aucune configuration ici : les relances WhatsApp s\'ouvrent directement via un lien wa.me vers le numéro du client, sans passerelle tierce.',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      ],
    );
  }
}

// ── PA-4 · Modes de paiement ───────────────────────────────────────────────

Future<bool> ouvrirBanque({required BuildContext context, required ReglagesFermeRepository depot}) async =>
    (await afficherModale<bool>(context: context, constructeur: (_) => _ModaleSimple(
      depot: depot, prefixe: 'banque', titre: 'Ajouter un Compte Bancaire',
      champs: const [('bankName', 'Banque *'), ('holderName', 'Titulaire du compte'), ('rib', 'RIB *'), ('iban', 'IBAN *'), ('accountCode', 'Numéro de compte (plan)')],
      valeurs: const {'holderName': 'Ferme École OLOUWACHEGOUN'},
      enregistrer: (d, v) => d.creerBanque(banque: v['bankName']!, titulaire: v['holderName']!, rib: v['rib']!, iban: v['iban']!, compte: v['accountCode']!),
    ))) == true;

Future<bool> ouvrirMomo({required BuildContext context, required ReglagesFermeRepository depot}) async =>
    (await afficherModale<bool>(context: context, constructeur: (_) => _ModaleSimple(
      depot: depot, prefixe: 'momo', titre: 'Ajouter une Ligne Mobile Money',
      champs: const [('operatorName', 'Opérateur *'), ('phoneNumber', 'Numéro de téléphone *'), ('holderName', 'Titulaire'), ('simSerial', 'Numéro de série SIM'), ('accountCode', 'Numéro de compte (plan)')],
      valeurs: const {},
      enregistrer: (d, v) => d.creerMomo(operateur: v['operatorName']!, telephone: v['phoneNumber']!, titulaire: v['holderName']!, sim: v['simSerial']!, compte: v['accountCode']!),
    ))) == true;

class _ModaleSimple extends StatefulWidget {
  const _ModaleSimple({required this.depot, required this.prefixe, required this.titre, required this.champs, required this.valeurs, required this.enregistrer});

  final ReglagesFermeRepository depot;
  final String prefixe;
  final String titre;
  final List<(String, String)> champs;
  final Map<String, String> valeurs;
  final Future<void> Function(ReglagesFermeRepository, Map<String, String>) enregistrer;

  @override
  State<_ModaleSimple> createState() => _ModaleSimpleState();
}

class _ModaleSimpleState extends State<_ModaleSimple> {
  late final Map<String, TextEditingController> _c = {for (final (cle, _) in widget.champs) cle: TextEditingController(text: widget.valeurs[cle] ?? '')};
  Map<String, String> _erreurs = const {};

  Future<void> _ok() async {
    try {
      await widget.enregistrer(widget.depot, {for (final e in _c.entries) e.key: e.value.text});
    } on ReglageRefuse catch (r) {
      setState(() => _erreurs = r.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: widget.titre,
    contenu: SingleChildScrollView(
      child: _formulaire(_erreurs, widget.prefixe, [for (final (cle, etiquette) in widget.champs) champReglage(widget.prefixe, cle, etiquette, _c[cle]!, _erreurs)]),
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: Key('${widget.prefixe}-enregistrer'), libelle: 'Enregistrer', onPressed: _ok),
    ],
  );
}

Future<bool> ouvrirVirement({required BuildContext context, required ReglagesFermeRepository depot, required List<TreasuryAccount> comptes}) async =>
    (await afficherModale<bool>(context: context, constructeur: (_) => _ModaleVirement(depot: depot, comptes: comptes))) == true;

class _ModaleVirement extends StatefulWidget {
  const _ModaleVirement({required this.depot, required this.comptes});

  final ReglagesFermeRepository depot;
  final List<TreasuryAccount> comptes;

  @override
  State<_ModaleVirement> createState() => _ModaleVirementState();
}

class _ModaleVirementState extends State<_ModaleVirement> {
  String _source = '';
  String _destination = '';
  final _montant = TextEditingController();
  final _motif = TextEditingController();
  Map<String, String> _erreurs = const {};

  Widget _liste(String cle, String valeur, ValueChanged<String> surChoix) => DropdownButtonFormField<String>(
    key: Key(cle),
    initialValue: valeur,
    isDense: true,
    isExpanded: true,
    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
    style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
    items: [
      const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
      for (final c in widget.comptes) DropdownMenuItem(value: c.id, child: Text('${c.label} — ${DocumentsComptabilite.montant(c.balance)} F', overflow: TextOverflow.ellipsis)),
    ],
    onChanged: (v) => setState(() => surChoix(v ?? '')),
  );

  Future<void> _ok() async {
    try {
      await widget.depot.virer(sourceId: _source, destinationId: _destination, montant: _montant.text, motif: _motif.text);
    } on ReglageRefuse catch (r) {
      setState(() => _erreurs = r.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: 'Virement Interne',
    contenu: SingleChildScrollView(
      child: _formulaire(_erreurs, 'virement', [
        Padding(padding: const EdgeInsets.only(bottom: AgriSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_etiquette('Compte source *'), _liste('virement-source', _source, (v) => _source = v), _erreur(_erreurs['transferFromId'], const Key('virement-erreur-transferFromId'))])),
        Padding(padding: const EdgeInsets.only(bottom: AgriSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_etiquette('Compte destinataire *'), _liste('virement-destination', _destination, (v) => _destination = v), _erreur(_erreurs['transferToId'], const Key('virement-erreur-transferToId'))])),
        champReglage('virement', 'transferAmount', 'Montant (FCFA) *', _montant, _erreurs, nombre: true),
        champReglage('virement', 'transferReason', 'Motif', _motif, _erreurs),
      ]),
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('virement-enregistrer'), libelle: 'Enregistrer le virement', onPressed: _ok),
    ],
  );
}

// ── PA-2 · Rôles & permissions ─────────────────────────────────────────────

Future<bool> ouvrirRole({required BuildContext context, required ReglagesFermeRepository depot, required List<String> droits, RolesApplicatif? existant, required bool estAdmin}) async =>
    (await afficherModale<bool>(context: context, constructeur: (_) => _ModaleRole(depot: depot, droits: droits, existant: existant, estAdmin: estAdmin))) == true;

class _ModaleRole extends StatefulWidget {
  const _ModaleRole({required this.depot, required this.droits, required this.existant, required this.estAdmin});

  final ReglagesFermeRepository depot;
  final List<String> droits;
  final RolesApplicatif? existant;
  final bool estAdmin;

  @override
  State<_ModaleRole> createState() => _ModaleRoleState();
}

class _ModaleRoleState extends State<_ModaleRole> {
  late final _nom = TextEditingController(text: widget.existant?.name ?? '');
  late final Set<String> _accordes = {
    for (final p in (widget.existant?.permissions ?? '').split(',')) if (p.trim().isNotEmpty) p.trim(),
  };
  Map<String, String> _erreurs = const {};

  Future<void> _ok() async {
    try {
      await widget.depot.enregistrerRole(ancienNom: widget.existant?.name, nom: _nom.text, permissions: _accordes, estAdmin: widget.estAdmin);
    } on ReglageRefuse catch (r) {
      setState(() => _erreurs = r.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: widget.existant == null ? 'Nouveau Rôle' : 'Modifier le Rôle',
    largeur: LargeurModale.lg,
    contenu: SingleChildScrollView(
      child: _formulaire(_erreurs, 'role', [
        champReglage('role', 'roleName', 'Nom du rôle *', _nom, _erreurs, indice: 'ex : responsable-achats'),
        _etiquette('Permissions'),
        if (widget.droits.isEmpty)
          const Text('Droits non synchronisés — le serveur ne les a pas encore servis à ce poste.', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
        for (final d in widget.droits)
          CheckboxListTile(
            key: Key('role-droit-$d'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(d, style: const TextStyle(fontSize: AgriTypography.xs)),
            value: _accordes.contains(d),
            onChanged: (v) => setState(() => v == true ? _accordes.add(d) : _accordes.remove(d)),
          ),
      ]),
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('role-enregistrer'), libelle: 'Enregistrer', onPressed: _ok),
    ],
  );
}
