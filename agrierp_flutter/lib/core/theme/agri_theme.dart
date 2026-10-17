import 'package:flutter/material.dart';

import 'agri_tokens.dart';

/// Thème Material dérivé des tokens du prototype.
///
/// ⚠️ AUCUNE COULEUR N'EST INTRODUITE ICI. Tout provient de [AgriColors] :
/// un thème qui invente une nuance « proche » fait diverger l'écran Flutter
/// de son équivalent web sans que rien ne le signale.
class AgriTheme {
  const AgriTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AgriColors.surfaceBg,
      colorScheme: const ColorScheme.light(
        primary: AgriColors.brandEmerald,
        onPrimary: Colors.white,
        secondary: AgriColors.accentYellow,
        onSecondary: AgriColors.brandForest,
        surface: AgriColors.surfaceCard,
        onSurface: AgriColors.onSurface,
        error: AgriColors.errorDeep,
        onError: Colors.white,
        outline: AgriColors.outline,
        outlineVariant: AgriColors.outlineVariant,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AgriColors.onSurface,
        displayColor: AgriColors.onSurface,
      ),
      cardTheme: CardThemeData(
        color: AgriColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          side: const BorderSide(color: AgriColors.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AgriColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: AgriSpacing.sm + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: const BorderSide(color: AgriColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: const BorderSide(color: AgriColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: const BorderSide(
            color: AgriColors.brandEmerald,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: const BorderSide(color: AgriColors.errorDeep),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AgriColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
