import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/verrou_local.dart';
import '../../core/theme/agri_tokens.dart';

/// Commande externe du pavé : le bouton plein de l'écran (celui de la connexion) valide la saisie du pavé.
class ControleurPave {
  _PavePinState? _etat;

  /// Valide la saisie en cours, comme la touche Entrée.
  Future<void> valider() async => _etat?._valider();
}

/// Ticket VL-1 — saisie d'un code PIN : points masqués, clavier numérique à l'écran ET clavier physique
/// (chiffres de la rangée du haut ou du pavé numérique, Retour arrière pour corriger, Entrée pour valider).
///
/// ⚠️ **LES CHIFFRES NE S'AFFICHENT JAMAIS** : seuls des points, un par chiffre saisi. Le pavé efface sa saisie
/// dès que [onValider] a rendu la main, qu'elle ait réussi ou non.
class PavePin extends StatefulWidget {
  const PavePin({
    super.key,
    required this.onValider,
    this.actif = true,
    this.controleur,
  });

  /// Reçoit la saisie ; le pavé se vide ensuite.
  final Future<void> Function(String pin) onValider;

  /// Faux : pavé grisé (temporisation, vérification en cours).
  final bool actif;

  /// Fourni : la touche « Valider » du pavé disparaît, l'écran porte son propre bouton (et appelle
  /// [ControleurPave.valider]). Entrée valide dans tous les cas.
  final ControleurPave? controleur;

  @override
  State<PavePin> createState() => _PavePinState();
}

class _PavePinState extends State<PavePin> {
  String _saisie = '';
  bool _enCours = false;

  static final _chiffresClavier = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  @override
  void initState() {
    super.initState();
    widget.controleur?._etat = this;
  }

  @override
  void dispose() {
    if (widget.controleur?._etat == this) widget.controleur?._etat = null;
    super.dispose();
  }

  bool get _saisissable => widget.actif && !_enCours;

  void _ajouter(String chiffre) {
    if (!_saisissable || _saisie.length >= VerrouLocal.longueurMax) return;
    setState(() => _saisie += chiffre);
  }

  void _effacer() {
    if (!_saisissable || _saisie.isEmpty) return;
    setState(() => _saisie = _saisie.substring(0, _saisie.length - 1));
  }

  Future<void> _valider() async {
    if (!_saisissable) return;
    final pin = _saisie;
    setState(() => _enCours = true);
    try {
      await widget.onValider(pin);
    } finally {
      if (mounted) {
        setState(() {
          _saisie = '';
          _enCours = false;
        });
      }
    }
  }

  KeyEventResult _touche(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final chiffre = _chiffresClavier[k];
    if (chiffre != null) {
      _ajouter(chiffre);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _effacer();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _valider();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _touche,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _points(),
          const SizedBox(height: AgriSpacing.lg),
          for (final ligne in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            _ligne([for (final c in ligne) _touchePave(c)]),
          _ligne([
            _toucheAction('effacer', 'Effacer', _effacer),
            _touchePave('0'),
            if (widget.controleur == null)
              _toucheAction('valider', 'Valider', _valider, accent: true)
            else
              const SizedBox(width: 80),
          ]),
        ],
      ),
    );
  }

  /// Au moins quatre emplacements (longueur minimale), jusqu'à un par chiffre saisi.
  Widget _points() {
    final n = _saisie.length < VerrouLocal.longueurMin
        ? VerrouLocal.longueurMin
        : _saisie.length;

    return Row(
      key: const Key('pin-saisie'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < n; i++)
          Container(
            key: Key(i < _saisie.length ? 'pin-rempli-$i' : 'pin-vide-$i'),
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _saisie.length ? AgriColors.brandEmerald : Colors.transparent,
              border: Border.all(
                color: i < _saisie.length ? AgriColors.brandEmerald : AgriColors.outline,
                width: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _ligne(List<Widget> enfants) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: enfants),
  );

  Widget _touchePave(String c) => _bouton(
    cle: 'touche-$c',
    libelle: c,
    surPression: () => _ajouter(c),
    taille: AgriTypography.xl,
  );

  Widget _toucheAction(String id, String libelle, VoidCallback f, {bool accent = false}) => _bouton(
    cle: 'touche-$id',
    libelle: libelle,
    surPression: f,
    taille: AgriTypography.xs,
    accent: accent,
  );

  Widget _bouton({
    required String cle,
    required String libelle,
    required VoidCallback surPression,
    required double taille,
    bool accent = false,
  }) {
    final actif = _saisissable;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: accent ? AgriColors.brandEmerald : AgriColors.surfaceBg,
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        child: InkWell(
          key: Key(cle),
          // Le focus reste au pavé : sinon la souris ferait perdre la saisie au clavier physique.
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          onTap: actif ? surPression : null,
          child: Container(
            width: 72,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: accent ? AgriColors.brandEmerald : AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Text(
              libelle,
              style: TextStyle(
                fontSize: taille,
                fontWeight: AgriTypography.gras,
                color: !actif
                    ? AgriColors.outline
                    : accent
                    ? Colors.white
                    : AgriColors.brandForest,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
