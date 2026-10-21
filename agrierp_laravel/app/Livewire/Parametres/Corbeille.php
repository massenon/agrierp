<?php

namespace App\Livewire\Parametres;

use App\Services\CorbeilleService;
use Illuminate\Pagination\LengthAwarePaginator;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;

/**
 * Tickets 14.55 puis ARC1 / ARC2 (PRD `docs/prd/archives.md`) — CORBEILLE : voir, restaurer, supprimer définitivement.
 *
 * Onglet de Paramètres Généraux (entre « Audit Logs » et « Réinitialisation »), ex-« Restauration ». Le projet impose
 * l'archivage logique depuis toujours ; la Corbeille rend ce qui a été archivé VISIBLE (tous modules, avec recherche,
 * type et période), RESTAURABLE (sous les règles métier de `CorbeilleService`) et, quand rien ne s'y oppose,
 * SUPPRIMABLE définitivement, en deux temps.
 *
 * ⚠️ **ÉCRAN HORS MAQUETTE** — le prototype ne montre pas de corbeille. Ajout demandé explicitement par le client
 * (« comme le principe de corbeille de Windows », puis « restaurer et/ou supprimer définitivement »). Le poste en est
 * une copie fidèle (`CorbeilleOnglet`), lue par `corbeille_blade_test.dart`.
 *
 * ⚠️ **RÉSERVÉ À L'ADMINISTRATEUR**, et le contrôle est posé sur CHAQUE méthode, pas seulement sur l'onglet : la
 * corbeille agrège les archives de tous les modules — un caissier y verrait des dépenses, un animalier des documents
 * administratifs. Le service refuse de son côté un acteur sans le droit (l'écran n'est pas la garantie).
 *
 * ⚠️ **SUPPRESSION EN DEUX TEMPS** : « Supprimer définitivement » n'ouvre qu'une modale ; l'effacement exige le mot
 * `SUPPRIMER` saisi à la main, revérifié par le serveur. Un élément qui ne peut pas être supprimé n'ouvre jamais la
 * modale : le refus est dit tout de suite.
 */
class Corbeille extends Component
{
    use WithPagination;

    public const PAR_PAGE = 25;

    #[Url]
    public string $typeFiltre = '';

    #[Url]
    public string $recherche = '';

    #[Url]
    public string $du = '';

    #[Url]
    public string $au = '';

    /** L'élément dont la suppression définitive attend son mot de confirmation. */
    public ?string $suppressionType = null;

    public ?string $suppressionId = null;

    public string $suppressionTitre = '';

    public string $suppressionLibelle = '';

    public string $confirmation = '';

    public function updatedTypeFiltre(): void
    {
        $this->resetPage('pageCorbeille');
    }

    public function updatedRecherche(): void
    {
        $this->resetPage('pageCorbeille');
    }

    public function updatedDu(): void
    {
        $this->resetPage('pageCorbeille');
    }

    public function updatedAu(): void
    {
        $this->resetPage('pageCorbeille');
    }

    public function reinitialiserFiltres(): void
    {
        $this->authorize('manage-parametres');

        $this->reset('typeFiltre', 'recherche', 'du', 'au');
        $this->resetPage('pageCorbeille');
    }

    public function getTypesProperty(): array
    {
        return CorbeilleService::registre();
    }

    public function restaurer(string $type, string $id): void
    {
        // ⚠️ Autorisation en PREMIÈRE LIGNE de la méthode qui écrit — jamais seulement sur l'affichage.
        $this->authorize('manage-parametres');

        $resultat = app(CorbeilleService::class)->tenterRestauration($type, $id);

        // ⚠️ Un échec est DIT, avec son motif : un élément déjà restauré par quelqu'un d'autre, un type inconnu ou une
        // règle métier ne doivent pas produire un succès silencieux qui laisserait croire l'enregistrement revenu.
        $this->dispatch('toast', message: $resultat['message'], type: $resultat['ok'] ? 'success' : 'error');
    }

    /** Premier temps : choisir l'élément. La modale ne s'ouvre que si la suppression est possible. */
    public function demanderSuppression(string $type, string $id): void
    {
        $this->authorize('manage-parametres');

        $element = collect(app(CorbeilleService::class)->elements($type))->firstWhere('id', $id);

        if ($element === null) {
            $this->dispatch('toast', message: CorbeilleService::MESSAGE_SUPPRESSION_INTROUVABLE, type: 'error');

            return;
        }
        if (! $element['supprimable']) {
            $this->annulerSuppression();
            $this->dispatch('toast', message: $element['motif_suppression'], type: 'error');

            return;
        }

        $this->suppressionType = $type;
        $this->suppressionId = $id;
        $this->suppressionTitre = $element['titre'];
        $this->suppressionLibelle = $element['libelle_type'];
        $this->confirmation = '';
        $this->dispatch('open-modal', name: 'modal-confirm-suppression-definitive');
    }

    public function annulerSuppression(): void
    {
        $this->reset('suppressionType', 'suppressionId', 'suppressionTitre', 'suppressionLibelle', 'confirmation');
    }

    /** Second temps : le mot SUPPRIMER est saisi — le serveur le revérifie, avec les dépendances. */
    public function supprimerDefinitivement(): void
    {
        $this->authorize('manage-parametres');

        if ($this->suppressionType === null || $this->suppressionId === null) {
            return;
        }

        $resultat = app(CorbeilleService::class)->supprimerDefinitivement($this->suppressionType, $this->suppressionId, $this->confirmation);

        if ($resultat['ok']) {
            $this->annulerSuppression();
            $this->dispatch('close-modal', name: 'modal-confirm-suppression-definitive');
        }
        $this->dispatch('toast', message: $resultat['message'], type: $resultat['ok'] ? 'success' : 'error');
    }

    public function render()
    {
        $this->authorize('manage-parametres');

        if ($this->typeFiltre !== '' && ! array_key_exists($this->typeFiltre, CorbeilleService::registre())) {
            $this->typeFiltre = '';
        }

        $service = app(CorbeilleService::class);
        $tous = $service->elements();
        $filtres = CorbeilleService::filtrer(
            $tous,
            $this->typeFiltre !== '' ? $this->typeFiltre : null,
            $this->recherche,
            $this->du !== '' ? $this->du : null,
            $this->au !== '' ? $this->au : null,
        );

        $page = $this->getPage('pageCorbeille');
        $paginateur = new LengthAwarePaginator(
            array_slice($filtres, ($page - 1) * self::PAR_PAGE, self::PAR_PAGE),
            count($filtres),
            self::PAR_PAGE,
            $page,
            ['pageName' => 'pageCorbeille', 'path' => request()->url()],
        );

        return view('livewire.parametres.corbeille', [
            'page' => $paginateur,
            'cartes' => $service->cartes($tous),
            'filtre' => $this->typeFiltre !== '' || $this->recherche !== '' || $this->du !== '' || $this->au !== '',
            'vide' => $tous === [],
        ]);
    }
}
