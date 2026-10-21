<?php

namespace App\Livewire\Parametres;

use App\Services\CorbeilleService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.55 (Sprint 14) — CORBEILLE & RESTAURATION.
 *
 * Onglet de Paramètres Généraux. Le projet impose l'archivage logique depuis
 * toujours ; **rien ne permettait de revoir ni de restaurer** ce qui avait été
 * archivé. En pratique, une archive valait donc une suppression : la règle
 * protégeait la donnée en base sans jamais la rendre récupérable par
 * l'utilisateur.
 *
 * ⚠️ **ÉCRAN HORS MAQUETTE** — le prototype ne montre pas de corbeille. Ajout
 * demandé explicitement par le client (« comme le principe de corbeille de
 * Windows »), à valider au prochain point comme les autres ajouts.
 *
 * ⚠️ **RÉSERVÉ À L'ADMINISTRATEUR**, et le contrôle est posé sur CHAQUE méthode,
 * pas seulement sur l'onglet : la corbeille agrège les archives de tous les
 * modules — un caissier y verrait des dépenses, un animalier des documents
 * administratifs. Masquer l'onglet ne suffit pas, c'est la règle des deux
 * niveaux appliquée partout dans ce projet.
 *
 * Les exclusions de sécurité (écritures comptables, utilisateurs, ventes,
 * paies) sont motivées dans `CorbeilleService`.
 */
class Restauration extends Component
{
    #[Url]
    public string $typeFiltre = '';

    public function getElementsProperty(): array
    {
        $this->authorize('manage-parametres');

        return app(CorbeilleService::class)
            ->elements($this->typeFiltre !== '' ? $this->typeFiltre : null);
    }

    public function getTypesProperty(): array
    {
        return CorbeilleService::registre();
    }

    public function restaurer(string $type, string $id): void
    {
        // ⚠️ Autorisation en PREMIÈRE LIGNE de la méthode qui écrit — jamais
        // seulement sur l'affichage.
        $this->authorize('manage-parametres');

        $restaure = app(CorbeilleService::class)->restaurer($type, $id);

        // ⚠️ Un échec est DIT. Un élément déjà restauré par quelqu'un d'autre,
        // ou un type inconnu, ne doit pas produire un succès silencieux qui
        // laisserait croire l'enregistrement revenu.
        $this->dispatch(
            'toast',
            message: $restaure
                ? 'Élément restauré — il réapparaît dans son module.'
                : "Restauration impossible : élément introuvable ou déjà restauré.",
            type: $restaure ? 'success' : 'error',
        );
    }

    public function render()
    {
        return view('livewire.parametres.restauration');
    }
}
