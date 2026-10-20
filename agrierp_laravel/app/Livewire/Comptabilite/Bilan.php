<?php

namespace App\Livewire\Comptabilite;

use App\Services\FinancialReportService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 10.5 (Sprint 10) — rapport-bilan.html → Livewire\Comptabilite\Bilan
 * "Situation patrimoniale de la Ferme École OLOUWACHEGOUN."
 *
 * ⚠️ DÉCISION ARCHITECTURALE CENTRALE : ce Bilan est calculé
 * EXCLUSIVEMENT depuis le grand livre (`accounting_entries`/
 * `accounting_entry_lines`, regroupées par classe SYSCOHADA du plan
 * comptable) — JAMAIS en recalculant les mêmes montants depuis des
 * tables métier disjointes (`receivables`, `payables`,
 * `treasury_accounts.balance`, valorisation de `products.stock_qty`...).
 * Un bilan comptable est PAR DÉFINITION un résumé du grand livre ; aller
 * chercher des données métier en direct court-circuiterait la
 * comptabilité elle-même et romprait le principe "un seul point de
 * vérité" appliqué partout ailleurs dans ce projet — le grand livre EST
 * la source de vérité financière, pas une source parmi d'autres.
 *
 * ⚠️ TICKET 10.8 : le calcul lui-même a été extrait vers
 * `App\Services\FinancialReportService::bilan()` — le hub Comptabilité
 * affiche des KPI ("Total Actif", "Trésorerie Disponible") qui recoupent
 * exactement ce même calcul ; dupliquer la logique ici et là-bas aurait
 * recréé deux implémentations pouvant un jour diverger. Ce composant
 * reste responsable de l'affichage, plus du calcul lui-même.
 *
 * ⚠️ CONSÉQUENCE HONNÊTE, SIGNALÉE EXPLICITEMENT : le rétro-câblage des
 * modules métier (POS, Achats, Paie...) vers le grand livre reste
 * délibérément différé depuis le ticket 10.2 — ce Bilan reflète donc
 * fidèlement ce qui existe RÉELLEMENT dans le grand livre aujourd'hui
 * (les écritures manuelles du Journal Comptable, ticket 10.4), pas
 * encore l'activité complète de la ferme. Il ne s'agit pas d'un Bilan
 * "de démonstration" avec des chiffres inventés pour paraître complet —
 * chaque montant affiché est réel et vérifiable dans le Journal, même si
 * la couverture reste partielle tant que le rétro-câblage n'est pas fait.
 *
 * ⚠️ ÉQUILIBRE ACTIF/PASSIF : PAS UNE COÏNCIDENCE, UNE IDENTITÉ
 * COMPTABLE GARANTIE PAR CONSTRUCTION. Puisque `AccountingEntryService`
 * (ticket 10.2) refuse toute écriture où débit ≠ crédit, la somme de
 * tous les débits du grand livre égale toujours la somme de tous les
 * crédits. Il en découle mathématiquement que Total Actif = Total
 * Capitaux Propres + Résultat + Total Dettes = Total Passif — cette
 * identité n'est PAS vérifiée en espérant qu'elle soit vraie, elle EST
 * vraie tant que le grand livre ne contient que des écritures créées via
 * ce service. La bannière la recalcule et l'affiche à chaque chargement
 * comme preuve vivante de l'intégrité comptable, pas comme simple
 * décoration.
 *
 * Classement par classe SYSCOHADA :
 * - Classe 2 (Immobilisations) → Actif Immobilisé, solde débiteur (débit-crédit)
 * - Classe 3 (Stocks) → Actif Circulant, solde débiteur
 * - Classe 4 (Tiers) → par compte : solde débiteur → Actif (créances,
 *   ex. 411 Clients) ; solde créditeur → Passif (dettes, ex. 401
 *   Fournisseurs) — classification par le signe réel du solde, pas par
 *   une liste de comptes codée en dur.
 * - Classe 5 (Trésorerie) → Actif, solde débiteur
 * - Classe 1 (Ressources/Capitaux) → Passif, solde créditeur (crédit-débit)
 * - Classe 6 (Charges) et Classe 7 (Produits) → Résultat de l'exercice
 *   (Produits − Charges), intégré aux Capitaux Propres au Passif.
 */
#[Layout('layouts.app')]
class Bilan extends Component
{
    public string $asOfDate = '';

    /**
     * Ticket EX8 (EF11) + EX7 (EF8) — L'EXERCICE AFFICHÉ. Il vient du point de passage unique
     * `App\Support\ExerciceChoisi` (le sélecteur de la barre supérieure, mémorisé en session) : changer d'exercice au
     * sélecteur recharge la page, `mount` relit l'exercice choisi, et les DEUX colonnes changent (N = l'exercice choisi,
     * N-1 = son précédent, à sa clôture).
     *
     * Le paramètre `exercice` (d'EX8) n'est pas une seconde vérité : une année donnée à la page (ou changée en cours de
     * route) est CHOISIE par `ExerciceChoisi::choisir()` — bandeau, sélecteur et Bilan disent alors la même année. Une
     * année sans exercice enregistré est refusée par `choisir()` : la page reste sur l'exercice affiché.
     */
    public ?int $exercice = null;

    public function mount(?int $exercice = null): void
    {
        if ($exercice !== null) {
            ExerciceChoisi::choisir($exercice);
        }

        $this->exercice = ExerciceChoisi::annee();
        // Ticket EX7 (EF9) — arrêté à aujourd'hui, ramené dans l'exercice affiché (sa clôture pour 2026 consulté en
        // 2027, son premier jour pour un exercice à venir) : `ExerciceChoisi::dateArrete()`, la règle unique (EX8 :
        // `FinancialReportService::arreteDeLExercice` y renvoie).
        $this->asOfDate = ExerciceChoisi::dateArrete();
    }

    /** Ticket EX7 (EF9) — une date d'arrêté hors de l'exercice affiché est ramenée à sa borne. */
    public function updatedAsOfDate(): void
    {
        $this->asOfDate = ExerciceChoisi::borner($this->asOfDate !== '' ? $this->asOfDate : ExerciceChoisi::dateArrete());
    }

    /** Ticket EX8 — l'exercice changé en cours de route est CHOISI (un seul exercice affiché), la date recalée. */
    public function updatedExercice(): void
    {
        if ($this->exercice !== null) {
            ExerciceChoisi::choisir($this->exercice);
        }

        $this->exercice = ExerciceChoisi::annee();
        $this->asOfDate = ExerciceChoisi::dateArrete();
    }

    /**
     * Ticket EX8 (EF11) — Bilan N / N-1 : l'exercice de la date choisie (colonne « Exercice N ») et l'exercice précédent
     * à sa clôture (colonne « Exercice N-1 », « — » s'il n'existe pas). Un seul point de calcul.
     */
    public function getComparatifProperty(): array
    {
        return $this->calculs[$this->asOfDate] ??= app(FinancialReportService::class)->bilanComparatif($this->asOfDate);
    }

    /** @var array<string, array> calculs de la requête en cours, par date d'arrêté (jamais conservés d'une requête à l'autre) */
    private array $calculs = [];

    /** Solde de chaque compte (débit-crédit) à la date choisie — la colonne N du comparatif. */
    public function getBilanProperty(): array
    {
        return $this->comparatif['n'];
    }

    public function render()
    {
        return view('livewire.comptabilite.bilan', ['title' => 'Comptabilité > Bilan']);
    }
}
