<?php

namespace Database\Seeders;

use App\Models\IncomeTaxBracket;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.38 (Sprint 14) — bareme IR-PTS / ITS du Benin.
 *
 * ⚠️ A VALIDER PAR LE CABINET FAGUEZ AVANT TOUTE PAIE REELLE.
 *
 * Ni le prototype ni le CDC ne documentent ce bareme : ils ne mentionnent que
 * la CNSS salariale (3,6 %). Les tranches ci-dessous correspondent au bareme
 * mensuel de l'Impot sur les Traitements et Salaires publie au Code General
 * des Impots beninois. Elles sont SEMEES, donc modifiables a l'ecran sans
 * redeploiement — un bareme fiscal change par loi de finances, et la version
 * appliquee a un bulletin doit rester visible et corrigeable par le comptable.
 *
 * Si le client fournit un bareme different, il remplace celui-ci sans qu'une
 * ligne de code ne bouge : c'est precisement pourquoi il vit en base.
 */
class IncomeTaxBracketsSeeder extends Seeder
{
    public function run(): void
    {
        if (IncomeTaxBracket::exists()) {
            return;   // jamais de doublon de bareme
        }

        foreach ([
            [0,       60_000,  0],
            [60_000,  150_000, 10],
            [150_000, 250_000, 15],
            [250_000, 500_000, 19],
            [500_000, null,    30],
        ] as [$de, $a, $taux]) {
            IncomeTaxBracket::create([
                'from_amount' => $de,
                'to_amount' => $a,
                'rate' => $taux,
                'is_active' => true,
            ]);
        }
    }
}
