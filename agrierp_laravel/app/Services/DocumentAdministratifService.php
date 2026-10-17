<?php

namespace App\Services;

use App\Models\AdministrativeDocument;
use App\Models\AuditLog;

/**
 * Ticket 15.25 — ENREGISTRER, MODIFIER, RETIRER UN DOCUMENT ADMINISTRATIF : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Administration\DocumentsAdministratifs` pour que la page web ET
 * `/sync/push` (le poste Flutter, table `administrative_documents`) appliquent les MÊMES règles
 * et la même trace d'audit. Même gabarit que `CourrierService` (15.23) et
 * `ArchiveDocumentService` (15.24).
 *
 * ⚠️ C'EST UN REGISTRE, PAS UN GÉNÉRATEUR : aucun fichier n'est produit ici. Les attestations
 * certifiées (aperçu, PDF) restent à `AttestationService` / RH › Attestations — ne pas les
 * dupliquer. Aucun catalogue de modèles, aucune pièce jointe, aucun statut autre que
 * `signe` / `en_attente`.
 *
 * ⚠️ « Retirer » = archivage logique (`is_active = false`), jamais un DELETE. Idempotent.
 * L'audit du retrait garde son nom historique `administrative_document.archived`.
 */
class DocumentAdministratifService
{
    /** Statut d'un document créé sans statut (valeur par défaut de la page web). */
    public const STATUT_PAR_DEFAUT = 'en_attente';

    /**
     * Règles de la page web (`saveDocument`), reprises telles quelles — clés = colonnes.
     *
     * @return array<string, array<int, string>>
     */
    public function regles(): array
    {
        return [
            'title' => ['required', 'string', 'max:255'],
            'type' => ['required', 'string', 'max:100'],
            'beneficiary' => ['required', 'string', 'max:150'],
            'doc_date' => ['required', 'date'],
            'status' => ['required', 'in:signe,en_attente'],
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
            'type' => $v['type'],
            'beneficiary' => $v['beneficiary'],
            'doc_date' => $v['doc_date'],
            'status' => $v['status'],
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): AdministrativeDocument
    {
        $document = new AdministrativeDocument();
        // ⚠️ `HasUuids` en engendrerait un autre ; `id` n'est pas remplissable.
        if ($id !== null) {
            $document->id = $id;
        }
        $document->fill($this->payload($v) + ['is_active' => true]);
        $document->save();

        AuditLog::record('administrative_document.created', 'administration');

        return $document;
    }

    /**
     * L'état actif n'est jamais touché ici (voir `archiver`).
     *
     * @param  array<string, mixed>  $v
     */
    public function modifier(AdministrativeDocument $document, array $v): AdministrativeDocument
    {
        $document->update($this->payload($v));

        AuditLog::record('administrative_document.updated', 'administration');

        return $document->fresh();
    }

    /** @return bool vrai si le document vient d'être retiré, faux s'il l'était déjà */
    public function archiver(AdministrativeDocument $document): bool
    {
        if (! $document->is_active) {
            return false;
        }

        $document->update(['is_active' => false]);

        AuditLog::record('administrative_document.archived', 'administration');

        return true;
    }
}
