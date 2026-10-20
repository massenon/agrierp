<?php

namespace App\Services;

use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\ModuleConfig;
use App\Models\TreasuryAccount;
use App\Models\User;

/**
 * Ticket 15.51 — ÉTAT DE DÉMARRAGE D'UNE BASE, LU DANS LES DONNÉES RÉELLES.
 *
 * Sur une base vide (installation neuve, ou `migrate:fresh` sans le jeu de démonstration), rien ne disait à
 * l'administrateur ce qui manquait : la première vente échouait sur « aucun exercice ouvert », la première
 * dépense sur « aucun compte de trésorerie ». Chaque étape est ici CONSTATÉE (jamais cochée à la main) et
 * renvoie à l'écran existant qui la règle.
 *
 * ⚠️ AUCUNE RÈGLE NOUVELLE : chaque condition est celle qu'un écran ou une action exige déjà.
 *  - exercice : `AccountingEntryService::record()` refuse toute écriture hors d'un exercice OUVERT qui couvre la
 *    date (`NoOpenFiscalYearException`) ;
 *  - trésorerie : une vente encaissée ou une dépense débite un compte de trésorerie actif ;
 *  - modules : `modules_config.is_enabled` ouvre les fiches d'élevage d'une espèce ;
 *  - plan comptable : chaque écriture vise un compte du plan.
 */
class DemarrageService
{
    /**
     * @return array<int, array{cle: string, titre: string, detail: string, fait: bool, obligatoire: bool, lien: ?string}>
     */
    public function etapes(): array
    {
        $entreprise = CompanySetting::query()->first();
        $exercice = $this->exerciceCourant();

        return [
            [
                'cle' => 'entreprise',
                'titre' => 'Identité de l\'entreprise',
                'detail' => 'Raison sociale, adresse et téléphone : ils figurent sur les factures et les documents officiels.',
                'fait' => filled($entreprise?->company_name) && filled($entreprise?->address) && filled($entreprise?->phone),
                'obligatoire' => true,
                'lien' => route('parametres.hub', ['tab' => 'entreprise']),
            ],
            [
                'cle' => 'plan',
                'titre' => 'Plan comptable',
                'detail' => 'Chaque écriture vise un compte du plan SYSCOHADA.',
                'fait' => ChartOfAccount::where('is_active', true)->exists(),
                'obligatoire' => true,
                'lien' => route('comptabilite.plan'),
            ],
            [
                'cle' => 'exercice',
                'titre' => 'Exercice comptable ouvert',
                'detail' => $exercice
                    ? 'Exercice '.$exercice->year.' ouvert, du '.$exercice->start_date->format('d/m/Y').' au '.$exercice->end_date->format('d/m/Y').'.'
                    : 'Aucun exercice ouvert ne couvre la date du jour : toute vente, tout achat et toute dépense seraient refusés.',
                'fait' => $exercice !== null,
                'obligatoire' => true,
                'lien' => null,
            ],
            [
                'cle' => 'tresorerie',
                'titre' => 'Compte de trésorerie',
                'detail' => 'Au moins une caisse, une banque ou un compte mobile money actif pour encaisser et payer.',
                'fait' => TreasuryAccount::where('is_active', true)->exists(),
                'obligatoire' => true,
                'lien' => route('parametres.hub', ['tab' => 'paiement']),
            ],
            [
                'cle' => 'modules',
                'titre' => 'Modules d\'élevage',
                'detail' => 'Activez les espèces élevées à la ferme : leurs fiches journalières n\'apparaissent qu\'ensuite.',
                'fait' => ModuleConfig::where('is_enabled', true)->exists(),
                'obligatoire' => true,
                'lien' => route('parametres.hub', ['tab' => 'modules']),
            ],
            [
                'cle' => 'utilisateurs',
                'titre' => 'Comptes de l\'équipe',
                'detail' => 'Un compte par personne (comptable, caissier, animalier) : chaque saisie est attribuée à son auteur.',
                'fait' => User::where('is_active', true)->count() > 1,
                'obligatoire' => false,
                'lien' => route('parametres.hub', ['tab' => 'utilisateurs']),
            ],
        ];
    }

    public function obligatoiresFaites(): bool
    {
        return collect($this->etapes())->every(fn ($e) => $e['fait'] || ! $e['obligatoire']);
    }

    /** Exercice OUVERT qui couvre aujourd'hui — la règle de `AccountingEntryService` (couverture de date). */
    public function exerciceCourant(): ?FiscalYear
    {
        $aujourdhui = now()->toDateString();

        return FiscalYear::where('status', 'ouvert')
            ->whereDate('start_date', '<=', $aujourdhui)
            ->whereDate('end_date', '>=', $aujourdhui)
            ->first();
    }
}
