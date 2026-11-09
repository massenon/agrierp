import 'justificatifs_navigateur.dart';

/// Natif : jamais utilisé (les justificatifs sont des fichiers du disque) ; mémoire par sécurité.
MagasinJustificatifs creerMagasinJustificatifsPlateforme() => MagasinJustificatifsMemoire();
