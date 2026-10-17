<?php

namespace App\Services;

use App\Models\ArchivedDocument;
use App\Models\AuditLog;

/**
 * Ticket 15.24 — ARCHIVER, MODIFIER, RETIRER UN DOCUMENT ARCHIVÉ : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Administration\ArchivageDocuments` pour que la page web ET `/sync/push`
 * (le poste Flutter, table `archived_documents`) appliquent les MÊMES règles et la même trace
 * d'audit. Même gabarit que `CourrierService` (15.23).
 *
 * ⚠️ « ARCHIVER » désigne ici le geste métier d'AJOUTER un document au coffre-fort ; le RETRAIT
 * du coffre (`archiver()` ci-dessous, action web « Retirer ») est un archivage logique :
 * `is_active = false`, jamais un DELETE. Idempotent.
 *
 * ⚠️ LE STATUT (Valide / Bientôt expiré / Expiré) N'EST PAS STOCKÉ : il se déduit de
 * `expiry_date` par `ArchivedDocument::statutPour()`, règle unique.
 *
 * ⚠️ AUCUN FICHIER JOINT : ni la maquette ni le schéma n'en ont.
 */
class ArchiveDocumentService
{
    /**
     * Règles de la page web (`saveDocument`), reprises telles quelles — clés = colonnes.
     *
     * @param  string  $champDateArchivage  nom du champ date d'archivage tel que le validateur le
     *                                      voit : `archived_date` (push), `archivedDate` (Livewire)
     * @return array<string, array<int, string>>
     */
    public function regles(string $champDateArchivage = 'archived_date'): array
    {
        return [
            'title' => ['required', 'string', 'max:255'],
            'category' => ['required', 'string', 'max:100'],
            'archived_date' => ['required', 'date'],
            'expiry_date' => ['nullable', 'date', 'after_or_equal:'.$champDateArchivage],
        ];
    }

    /**
     * @param  array<string, mixed>  $v
     * @return array<string, mixed>
     */
    private function payload(array $v): array
    {
        return [
            'title' => $v['title'],
            'category' => $v['category'],
            'archived_date' => $v['archived_date'],
            'expiry_date' => ($v['expiry_date'] ?? null) ?: null,
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): ArchivedDocument
    {
        $document = new ArchivedDocument();
        // ⚠️ `HasUuids` en engendrerait un autre ; `id` n'est pas remplissable.
        if ($id !== null) {
            $document->id = $id;
        }
        $document->fill($this->payload($v) + ['is_active' => true]);
        $document->save();

        AuditLog::record('archived_document.created', 'administration');

        return $document;
    }

    /**
     * L'état actif n'est jamais touché ici (voir `archiver`).
     *
     * @param  array<string, mixed>  $v
     */
    public function modifier(ArchivedDocument $document, array $v): ArchivedDocument
    {
        $document->update($this->payload($v));

        AuditLog::record('archived_document.updated', 'administration');

        return $document->fresh();
    }

    /** @return bool vrai si le document vient d'être retiré, faux s'il l'était déjà */
    public function archiver(ArchivedDocument $document): bool
    {
        if (! $document->is_active) {
            return false;
        }

        $document->update(['is_active' => false]);

        AuditLog::record('archived_document.deleted', 'administration');

        return true;
    }
}
