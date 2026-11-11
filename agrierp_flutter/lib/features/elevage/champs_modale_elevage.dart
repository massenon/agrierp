// Ticket MP2 : widgets de formulaire promus vers `lib/core/widgets/champs_formulaire_agri.dart`.
// Ce fichier expose les ANCIENS NOMS comme alias pour ne pas casser les imports existants.
import 'package:flutter/material.dart' show BoxDecoration;

export '../../core/widgets/champs_formulaire_agri.dart'
    show cadreChampFormulaire, BlocChampFormulaire, ChampTexteFormulaire, ChampLectureFormulaire, ChampListeFormulaire;

import '../../core/widgets/champs_formulaire_agri.dart';

/// Alias de [cadreChampFormulaire] (nom historique).
BoxDecoration cadreChampModale({bool enErreur = false, bool grise = false}) =>
    cadreChampFormulaire(enErreur: enErreur, grise: grise);

/// Alias de [BlocChampFormulaire] (nom historique).
typedef BlocChampModale = BlocChampFormulaire;

/// Alias de [ChampTexteFormulaire] (nom historique).
typedef ChampTexteModale = ChampTexteFormulaire;

/// Alias de [ChampLectureFormulaire] (nom historique).
typedef ChampLectureModale = ChampLectureFormulaire;

/// Alias de [ChampListeFormulaire] (nom historique).
typedef ChampListeModale = ChampListeFormulaire;
