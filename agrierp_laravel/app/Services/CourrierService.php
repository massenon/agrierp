<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Correspondence;
use Illuminate\Database\UniqueConstraintViolationException;

/**
 * Ticket 15.23 — ENREGISTRER, MODIFIER, ARCHIVER UN COURRIER : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Administration\GestionCourriers` (ticket 9.x) pour que la page web ET
 * `/sync/push` (le poste Flutter, table `mails`) appliquent les MÊMES règles, la même trace
 * d'audit et le même archivage.
 *
 * ⚠️ LA RÉFÉRENCE (`CR-AAAA-NNN`) EST ATTRIBUÉE PAR LE SERVEUR, JAMAIS PAR LE POSTE, et ne
 * change JAMAIS à la modification. Un poste hors ligne n'en connaît pas : elle redescend au
 * tirage après l'acquittement.
 *
 * ⚠️ ARCHIVER N'EFFACE RIEN : `is_active = false`, jamais un DELETE. Idempotent : archiver un
 * courrier déjà archivé est un succès sans nouvelle trace d'audit.
 *
 * ⚠️ AUCUN STATUT DE COURRIER, AUCUNE PIÈCE JOINTE : ni la maquette ni le schéma n'en ont.
 */
class CourrierService
{
    /** Nombre de tentatives si deux courriers se disputent la même référence. */
    private const TENTATIVES = 5;

    /**
     * Règles de la page web (`saveMail`), reprises telles quelles — clés = colonnes.
     *
     * @return array<string, array<int, string>>
     */
    public function regles(): array
    {
        return [
            'type' => ['required', 'in:entrant,sortant'],
            'subject' => ['required', 'string', 'max:255'],
            'party' => ['required', 'string', 'max:150'],
            'mail_date' => ['required', 'date'],
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @return array<string, mixed>
     */
    private function payload(array $v): array
    {
        return [
            'type' => $v['type'],
            'subject' => $v['subject'],
            'party' => $v['party'],
            'mail_date' => $v['mail_date'],
        ];
    }

    /**
     * @param  array<string, mixed>  $v
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): Correspondence
    {
        $derniere = null;

        for ($essai = 1; $essai <= self::TENTATIVES; $essai++) {
            try {
                // Un seul INSERT : atomique en soi. Le recalcul de la référence et l'écriture
                // sont départagés par la contrainte UNIQUE (voir le `catch`).
                $courrier = new Correspondence();
                // ⚠️ `HasUuids` en engendrerait un autre ; `id` n'est pas remplissable.
                if ($id !== null) {
                    $courrier->id = $id;
                }
                $courrier->fill($this->payload($v) + [
                    'reference' => Correspondence::generateReference(),
                    'is_active' => true,
                ]);
                $courrier->save();

                AuditLog::record('mail.created', 'administration');

                return $courrier;
            } catch (UniqueConstraintViolationException $e) {
                // Un autre enregistrement a pris la même référence entre le calcul et
                // l'écriture : la contrainte UNIQUE l'a refusé, on recalcule.
                // Un `id` déjà présent n'est PAS un conflit de référence : on ne boucle pas.
                if ($id !== null && Correspondence::whereKey($id)->exists()) {
                    throw $e;
                }
                $derniere = $e;
            }
        }

        throw $derniere;
    }

    /**
     * La référence n'est jamais touchée, ni l'état actif (voir `archiver`).
     *
     * @param  array<string, mixed>  $v
     */
    public function modifier(Correspondence $courrier, array $v): Correspondence
    {
        $courrier->update($this->payload($v));

        AuditLog::record('mail.updated', 'administration');

        return $courrier->fresh();
    }

    /** @return bool vrai si le courrier vient d'être archivé, faux s'il l'était déjà */
    public function archiver(Correspondence $courrier): bool
    {
        if (! $courrier->is_active) {
            return false;
        }

        $courrier->update(['is_active' => false]);

        AuditLog::record('mail.archived', 'administration', null, $courrier);

        return true;
    }
}
