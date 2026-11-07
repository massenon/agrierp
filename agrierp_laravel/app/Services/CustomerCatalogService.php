<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Customer;

/**
 * Ticket 15.18 — CRÉER, MODIFIER, ARCHIVER UN CLIENT : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Ventes\ListeClients` (ticket 4.6) pour que la page web ET
 * `/sync/push` (le poste Flutter) appliquent les MÊMES règles — nom obligatoire,
 * téléphone / e-mail / ville / IFU (13 chiffres) facultatifs —, la même trace d'audit et le même archivage.
 *
 * ⚠️ ARCHIVER N'EFFACE RIEN : `is_active = false`, jamais un DELETE. Les ventes, les
 * créances et les avances du client restent lisibles.
 *
 * ⚠️ `credit_limit` n'est PAS dans le formulaire (web ni poste) : il n'est donc jamais
 * écrit ici, et un poste ne peut pas relever le plafond d'un client.
 */
class CustomerCatalogService
{
    /** @return array<string, array<int, string>> */
    public function regles(): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            'phone' => ['nullable', 'string', 'max:30'],
            'email' => ['nullable', 'email', 'max:150'],
            'city' => ['nullable', 'string', 'max:100'],
            // IFU du client (facultatif : un client particulier n'en a pas) : 13 chiffres. Il préremplit la facture normalisée.
            'ifu' => ['nullable', 'string', 'regex:/^\d{13}$/'],
            'is_active' => ['nullable', 'boolean'],
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @return array<string, mixed>
     */
    public function payload(array $v): array
    {
        $charge = [
            'name' => $v['name'],
            'phone' => ($v['phone'] ?? null) ?: null,
            'email' => ($v['email'] ?? null) ?: null,
            'city' => ($v['city'] ?? null) ?: null,
        ];

        // `ifu` ABSENT (poste ancien) = conservé ; présent mais vide = effacé. Les factures déjà normalisées gardent leur propre IFU.
        if (array_key_exists('ifu', $v)) {
            $charge['ifu'] = ($v['ifu'] ?? null) ?: null;
        }

        return $charge;
    }

    /**
     * @param  array<string, mixed>  $v
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): Customer
    {
        $client = new Customer();
        // ⚠️ `HasUuids` en engendrerait un autre ; `id` n'est pas remplissable et
        // `create(['id' => …])` l'ignorerait EN SILENCE.
        if ($id !== null) {
            $client->id = $id;
        }
        $client->fill($this->payload($v) + [
            'is_active' => array_key_exists('is_active', $v) && $v['is_active'] !== null
                ? (bool) $v['is_active']
                : true,
        ]);
        $client->save();

        AuditLog::record('customer.created', 'ventes');

        return $client;
    }

    /** @param array<string, mixed> $v */
    public function modifier(Customer $client, array $v): Customer
    {
        $etaitActif = (bool) $client->is_active;

        $charge = $this->payload($v);
        if (array_key_exists('is_active', $v) && $v['is_active'] !== null) {
            $charge['is_active'] = (bool) $v['is_active'];
        }

        $client->update($charge);

        AuditLog::record('customer.updated', 'ventes');

        if ($etaitActif && ! $client->is_active) {
            AuditLog::record('customer.archived', 'ventes', null, $client);
        }

        return $client->fresh();
    }

    public function archiver(Customer $client): void
    {
        $client->update(['is_active' => false]);

        AuditLog::record('customer.archived', 'ventes', null, $client);
    }

    /**
     * Archivage en masse : mêmes règles que `archiver()`, jamais un DELETE.
     *
     * @param  array<int, string>  $ids
     * @return int nombre de clients réellement archivés (déjà archivés : non comptés)
     */
    public function archiverPlusieurs(array $ids): int
    {
        $aArchiver = Customer::whereIn('id', $ids)->where('is_active', true)->get();
        $nombre = $aArchiver->count();
        Customer::whereIn('id', $ids)->update(['is_active' => false]);

        AuditLog::record('customer.bulk_archived', 'ventes');
        // Ticket ARC-Q2 — la Corbeille doit savoir qui a archivé CHAQUE client : une ligne d'audit par client réellement archivé.
        foreach ($aArchiver as $client) {
            AuditLog::record('customer.archived', 'ventes', null, $client);
        }

        return $nombre;
    }
}
