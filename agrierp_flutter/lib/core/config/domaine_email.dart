/// Ticket MAIL1 (décision du client, 21/10/2026) — le domaine des adresses e-mail de la ferme change :
/// `@olouwachegoun.bj` devient `@fermeolouwachegoun.com`, y compris pour les anciennes adresses déjà enregistrées.
///
/// Les données locales sont converties une fois par le palier v50 de la base (`AppDatabase._convertirAdressesEmail`). Cette
/// fonction ne sert qu'à ce que le palier ne peut pas atteindre : la session mise en cache au coffre du système
/// (`SessionUtilisateur.depuisJson`), lue — jamais réécrite — sans aller-retour serveur.
const ancienDomaineEmail = 'olouwachegoun.bj';
const nouveauDomaineEmail = 'fermeolouwachegoun.com';

final _ancienneAdresse = RegExp(
  '@${RegExp.escape(ancienDomaineEmail)}(?![A-Za-z0-9-])',
  caseSensitive: false,
);

/// [adresse] avec `@olouwachegoun.bj` (insensible à la casse) remplacé par `@fermeolouwachegoun.com`. Toute autre valeur,
/// un nom de serveur sans « @ » compris, est rendue telle quelle.
String convertirDomaineEmail(String adresse) =>
    adresse.replaceAll(_ancienneAdresse, '@$nouveauDomaineEmail');
