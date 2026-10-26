<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Supplier;

/**
 * Ticket 15.17 — CRÉER, MODIFIER, ARCHIVER UN FOURNISSEUR : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Achats\AjouterFournisseur` (ticket 5.6) pour que la page web ET
 * `/sync/push` (le poste Flutter) appliquent les MÊMES règles — nom, catégorie et
 * téléphone obligatoires —, la même trace d'audit et le même archivage.
 *
 * ⚠️ ARCHIVER N'EFFACE RIEN : `is_active = false`. Le tirage ne sert que les
 * fournisseurs actifs, ce qui fait disparaître l'archivé du poste au tirage suivant ;
 * ses achats et ses dettes restent. La page web n'interdit pas d'archiver un
 * fournisseur à qui l'on doit encore de l'argent — règle conservée, signalée au ticket.
 */
class SupplierCatalogService
{
    /** @return array<string, array<int, string>> */
    public function regles(): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            'category' => ['required', 'string'],
            'phone' => ['required', 'string', 'max:30'],
            'address' => ['nullable', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:150'],
            'is_active' => ['nullable', 'boolean'],
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @return array<string, mixed>
     */
    public function payload(array $v): array
    {
        $payload = [
            'name' => $v['name'],
            'category' => $v['category'],
            'phone' => $v['phone'],
            'address' => ($v['address'] ?? null) ?: null,
        ];

        // ⚠️ L'e-mail n'est écrit que s'il est fourni : le formulaire n'a pas ce champ,
        // et un poste qui ne l'envoie pas ne doit pas effacer celui du serveur.
        if (array_key_exists('email', $v)) {
            $payload['email'] = $v['email'] ?: null;
        }

        return $payload;
    }

    /**
     * @param  array<string, mixed>  $v
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): Supplier
    {
        $fournisseur = new Supplier();
        // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait EN SILENCE.
        if ($id !== null) {
            $fournisseur->id = $id;
        }
        $fournisseur->fill($this->payload($v) + [
            'is_active' => array_key_exists('is_active', $v) ? (bool) $v['is_active'] : true,
        ]);
        $fournisseur->save();

        AuditLog::record('supplier.created', 'achats');

        return $fournisseur;
    }

    /** @param array<string, mixed> $v */
    public function modifier(Supplier $fournisseur, array $v): Supplier
    {
        $etaitActif = (bool) $fournisseur->is_active;

        $charge = $this->payload($v);
        if (array_key_exists('is_active', $v) && $v['is_active'] !== null) {
            $charge['is_active'] = (bool) $v['is_active'];
        }

        $fournisseur->update($charge);

        AuditLog::record('supplier.updated', 'achats');

        if ($etaitActif && ! $fournisseur->is_active) {
            AuditLog::record('supplier.archived', 'achats', null, $fournisseur);
        }

        return $fournisseur->fresh();
    }

    public function archiver(Supplier $fournisseur): void
    {
        $fournisseur->update(['is_active' => false]);

        AuditLog::record('supplier.archived', 'achats', null, $fournisseur);
    }
}
