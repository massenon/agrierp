import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';

/// Les trois types de `components/toast-container.blade.php` (`$dispatch('toast', type: …)`).
enum TypeToast { succes, erreur, avertissement }

/// Ticket H1 / H2 — COMPOSANT TOAST UNIQUE du poste, transposé de `toast-container.blade.php` du web.
///
/// Web (maître) : `fixed top-4 right-4 z-[200] flex flex-col gap-sm`, chaque toast
/// `flex items-center gap-sm px-md py-sm rounded-lg shadow-lg border min-w-[260px]`, icône 20 px, message
/// `text-sm font-semibold`, entrée glissée de 20 px depuis la droite (`toastIn`, 0,3 s), retiré après 3,5 s.
/// - succès : `bg-brand-emerald text-white`, icône `check_circle` ;
/// - erreur : `bg-error-red text-white`, icône `error` ;
/// - avertissement : `bg-accent-yellow text-brand-forest`, icône `warning`.
///
/// 🔴 Avant : chaque écran affichait une `SnackBar` Material par défaut (en bas, gris foncé, sans icône, 4 s), et
/// l'avertissement n'existait pas. Un seul composant désormais, empilable comme au web.
class ToastAgri {
  ToastAgri._();

  /// Durée d'affichage du web (`setTimeout(…, 3500)`).
  static const duree = Duration(milliseconds: 3500);

  static final _ouverts = <_EntreeToast>[];

  /// UNE seule entrée d'overlay porte toute la pile (`flex flex-col gap-sm` du web).
  static OverlayEntry? _pile;

  /// Affiche [message] en haut à droite. [duree] ne se change que pour un message long qui doit être lu
  /// (refus du serveur) : le défaut est celui du web.
  static void afficher(
    BuildContext context,
    String message, {
    TypeToast type = TypeToast.succes,
    Duration? duree,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entree = _EntreeToast(_ToastVisible(message: message, type: type));
    _ouverts.add(entree);

    final pile = _pile;
    if (pile == null || !pile.mounted) {
      _pile = OverlayEntry(builder: (_) => _PileDeToasts(ouverts: List.of(_ouverts)));
      overlay.insert(_pile!);
    } else {
      pile.markNeedsBuild();
    }

    entree.minuterie = Timer(duree ?? ToastAgri.duree, () => _retirer(entree));
  }

  static void _retirer(_EntreeToast entree) {
    _ouverts.remove(entree);
    final pile = _pile;
    if (pile == null || !pile.mounted) return;
    if (_ouverts.isEmpty) {
      pile.remove();
      _pile = null;
    } else {
      pile.markNeedsBuild();
    }
  }

  /// Retire tous les toasts (fin d'un test, changement de session).
  static void toutRetirer() {
    for (final o in _ouverts) {
      o.minuterie?.cancel();
    }
    _ouverts.clear();
    if (_pile?.mounted ?? false) _pile!.remove();
    _pile = null;
  }
}

class _EntreeToast {
  _EntreeToast(this.toast);

  final _ToastVisible toast;
  Timer? minuterie;
}

class _PileDeToasts extends StatelessWidget {
  const _PileDeToasts({required this.ouverts});

  final List<_EntreeToast> ouverts;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: AgriSpacing.md,
      right: AgriSpacing.md,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          key: const Key('pile-toasts'),
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < ouverts.length; i++) ...[
              if (i > 0) const SizedBox(height: AgriSpacing.sm),
              ouverts[i].toast,
            ],
          ],
        ),
      ),
    );
  }
}

class _ToastVisible extends StatelessWidget {
  const _ToastVisible({required this.message, required this.type});

  final String message;
  final TypeToast type;

  @override
  Widget build(BuildContext context) {
    final (fond, texte, icone) = switch (type) {
      TypeToast.succes => (AgriColors.brandEmerald, Colors.white, Icons.check_circle),
      TypeToast.erreur => (AgriColors.errorRed, Colors.white, Icons.error),
      TypeToast.avertissement => (AgriColors.accentYellow, AgriColors.brandForest, Icons.warning),
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (_, t, enfant) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(20 * (1 - t), 0), child: enfant),
      ),
      child: Container(
        key: Key('toast-${type.name}'),
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          border: Border.all(color: fond),
          boxShadow: AgriShadows.lg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 20, color: texte),
            const SizedBox(width: AgriSpacing.sm),
            Flexible(
              child: Text(
                message,
                style: TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.w600, color: texte),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
