<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * LES 36 COMPTES DE LA FERME (extrait des règles métier documentées), puis — depuis le ticket 15.27 — le plan
 * SYSCOHADA révisé officiel du client (1 332 comptes), importé en insertion seule par
 * `ImporterPlanSyscohadaService`. Les 36 comptes gardent leur code, leur libellé et leur sens.
 */
class ChartOfAccountsSeeder extends Seeder
{
    /**
     * Les 36 comptes de la ferme (code, libellé, classe). Exposée pour que le garde-fou de `NatureComptesTiersTest`
     * lise LA liste réelle du semis : tout compte ajouté ici sans nature décidée y fait échouer le test.
     *
     * @return array<int, array{code: string, label: string, class: int}>
     */
    public static function comptesDeLaFerme(): array
    {
        return [
            // 🔴→✅ TICKET 14.34 — COMPTE DE CAPITAL, absent du plan comptable.
            // La classe 1 ne contenait que 131/139 (résultat) : aucun compte de
            // capital social. Conséquences : les capitaux propres du Bilan se
            // réduisaient au seul résultat de l'exercice, et surtout AUCUN
            // BILAN D'OUVERTURE n'était passable — un bien déjà possédé par la
            // ferme n'avait pas de contrepartie possible autre qu'une dette
            // fournisseur fictive. C'est la limite documentée au ticket 14.26
            // (« reprise d'antériorité hors comptabilité ») ; elle tombe ici.
            ['code' => '101', 'label' => 'Capital social', 'class' => 1],
            ['code' => '131', 'label' => 'Résultat net (bénéfice)', 'class' => 1],
            ['code' => '139', 'label' => 'Résultat net (perte)', 'class' => 1],
            // 🔴→✅ TICKET 14.26 — comptes de classe 2 des BIENS eux-memes. Seul
            // `281 Amortissements` existait : on amortissait des immobilisations
            // qu'aucun compte ne portait. Les 3 natures reprennent celles du
            // prototype (`balance-generale.html`, `etats-financiers.html`), jamais
            // inventees.
            ['code' => '221', 'label' => 'Bâtiments et constructions', 'class' => 2],
            ['code' => '241', 'label' => "Cages et matériel d'élevage", 'class' => 2],
            ['code' => '244', 'label' => 'Broyeurs et équipements', 'class' => 2],
            ['code' => '281', 'label' => 'Amortissements des immobilisations', 'class' => 2],
            ['code' => '313', 'label' => 'Produits transformés', 'class' => 3],
            ['code' => '401', 'label' => 'Fournisseurs', 'class' => 4],
            // TICKET 15.20 (D1/D7) — fournisseurs débiteurs : la part DÉJÀ PAYÉE d'un achat retourné est une
            // créance sur le fournisseur (il doit rendre l'argent). Proposition à faire valider par le cabinet
            // FAGUEZ. Doublée par la migration de rattrapage `2026_10_09_000008` pour les bases déjà semées.
            ['code' => '409', 'label' => 'Fournisseurs débiteurs', 'class' => 4],
            ['code' => '411', 'label' => 'Clients', 'class' => 4],
            // TICKET 15.19 (D1) — avances et acomptes reçus des clients. Une avance encaissée
            // n'est NI un produit NI une créance : c'est une dette envers le client (livrer ou
            // rembourser). Proposition à faire valider par le cabinet FAGUEZ. Doublée par la
            // migration de rattrapage `2026_10_09_000003` pour les bases déjà semées.
            ['code' => '419', 'label' => 'Avances et acomptes reçus', 'class' => 4],
            ['code' => '443', 'label' => 'TVA facturée', 'class' => 4],
            ['code' => '445', 'label' => 'TVA récupérable', 'class' => 4],
            // 🔴→✅ TICKET 14.25 — compte d'organismes sociaux, absent alors que la
            // paie retient DEJA une cotisation CNSS de 3,6 % (`GestionPaie`). Sans
            // lui, l'ecriture de paie ne pouvait pas equilibrer : la retenue n'a pas
            // de contrepartie. Meme demarche que `661`/`65` au ticket 14.6 —
            // completer le plan SYSCOHADA pour un mecanisme qui existe deja, jamais
            // inventer un compte pour une operation imaginaire.
            ['code' => '431', 'label' => 'Sécurité sociale (CNSS)', 'class' => 4],
            ['code' => '521101', 'label' => 'Banque - Compte principal', 'class' => 5],
            ['code' => '521201', 'label' => 'Mobile Money', 'class' => 5],
            ['code' => '531', 'label' => 'Caisse', 'class' => 5],
            ['code' => '601', 'label' => 'Achats de marchandises', 'class' => 6],
            // 🔴→✅ TICKET 14.6 — `661` et `65` manquaient alors que `661` était
            // déjà proposé comme compte réel dans le sélecteur du Grand Livre
            // (écart signalé au ticket 14.1, comblé ici) et que le Compte de
            // Résultat en a besoin pour ses lignes « Charges de Personnel » et
            // « Autres charges de gestion ».
            // 🔴→✅ TICKET 14.33 — COMPTES DE CHARGES DES DEPENSES.
            // L'ecran Saisie Depenses propose 9 comptes SYSCOHADA (601, 602,
            // 604, 605, 606, 614, 621, 624, 628) repris du prototype, dont 7
            // n'existaient nulle part au plan comptable : aucune ecriture de
            // depense n'aurait pu trouver son compte de contrepartie.
            ['code' => '602', 'label' => 'Produits vétérinaires', 'class' => 6],
            ['code' => '604', 'label' => 'Fournitures et matériel', 'class' => 6],
            ['code' => '605', 'label' => 'Énergie', 'class' => 6],
            ['code' => '606', 'label' => 'Entretien', 'class' => 6],
            ['code' => '614', 'label' => 'Transports', 'class' => 6],
            ['code' => '621', 'label' => 'Salaires', 'class' => 6],
            ['code' => '624', 'label' => 'Transports (variante prototype)', 'class' => 6],
            ['code' => '628', 'label' => 'Autres charges', 'class' => 6],
            ['code' => '65', 'label' => 'Autres charges de gestion', 'class' => 6],
            // 🔴→✅ TICKET 14.41 — charges exceptionnelles, absentes du plan.
            // L'ecran Gestion des Stocks promettait pourtant a l'utilisateur
            // « l'ecriture de charge exceptionnelle (compte 657) » depuis le
            // Sprint 6 : le compte n'a jamais existe.
            ['code' => '657', 'label' => 'Charges exceptionnelles', 'class' => 6],
            ['code' => '661', 'label' => 'Charges de personnel', 'class' => 6],
            // 🔴→✅ TICKET 14.38 — comptes de la paie beninoise, absents.
            // Sans eux, ni les charges patronales (VPS, CNSS employeur) ni la
            // retenue d'impot ne pouvaient etre comptabilisees.
            ['code' => '664', 'label' => 'Charges sociales patronales', 'class' => 6],
            ['code' => '4472', 'label' => 'Impôt sur les traitements et salaires (ITS)', 'class' => 4],
            ['code' => '4473', 'label' => 'Versement patronal sur salaires (VPS)', 'class' => 4],
            ['code' => '681', 'label' => 'Dotations aux amortissements', 'class' => 6],
            ['code' => '701', 'label' => 'Ventes de produits', 'class' => 7],
            ['code' => '73', 'label' => 'Variation de stocks', 'class' => 7],
        ];
    }

    public function run(): void
    {
        $accounts = self::comptesDeLaFerme();

        // Ticket 14.26 : semis RENDU IDEMPOTENT. L'`insert()` brut d'origine
        // echouait des le second passage sur la contrainte d'unicite du code —
        // les 3 comptes de classe 2 ajoutes ici (221/241/244) ne seraient donc
        // jamais arrives sur une installation deja semee, et le registre des
        // immobilisations y aurait ete inutilisable faute de nature a choisir.
        foreach ($accounts as $a) {
            DB::table('chart_of_accounts')->updateOrInsert(
                ['code' => $a['code']],
                [
                    'id' => (string) DB::table('chart_of_accounts')->where('code', $a['code'])->value('id') ?: (string) Str::uuid(),
                    'label' => $a['label'],
                    'class' => $a['class'],
                    'is_active' => true,
                    'updated_at' => now(),
                ]
            );
        }

        // TICKET 15.27 (phase A de l'item 9) — plan SYSCOHADA révisé OFFICIEL du client : import en INSERTION SEULE,
        // APRÈS les 36 comptes ci-dessus. L'ordre est essentiel : 12 codes de la ferme (531, 221, 701…) ont un autre
        // sens dans le CSV ; posés d'abord, ils gardent le leur et l'import ne les touche pas. Le remappage éventuel
        // est la phase B, à valider par le cabinet FAGUEZ. Idempotent.
        app(\App\Services\ImporterPlanSyscohadaService::class)->importer();
    }
}
