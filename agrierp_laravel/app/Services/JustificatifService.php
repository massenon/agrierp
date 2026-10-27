<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\Expense;
use App\Models\Purchase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Ticket AC-3 — POINT DE PASSAGE UNIQUE DES PIÈCES JUSTIFICATIVES d'un achat et d'une dépense.
 *
 * Appelé par `EnregistrerAchat` (le web), par l'envoi du poste (`SyncController::receipt`) et par la route de lecture : un
 * justificatif se range au même endroit (disque privé `local`), se rattache à la même colonne (`receipt_path`) et se lit
 * par la même route authentifiée, d'où qu'il vienne.
 *
 * ⚠️ Le fichier d'un enregistrement n'existe qu'une fois : en poser un nouveau REMPLACE l'ancien (supprimé du disque). Un
 * même fichier renvoyé (accusé perdu) ne laisse donc aucun doublon.
 */
class JustificatifService
{
    /** Types de pièce → [modèle, dossier du disque]. `achat` = purchases, `depense` = expenses. */
    private const TYPES = [
        'achat' => [Purchase::class, 'achats-recus'],
        'depense' => [Expense::class, 'depenses-recus'],
    ];

    /** Taille maximale (Ko) et formats : ceux du formulaire du web, PDF compris (la modale du poste l'offre). */
    public const TAILLE_MAX_KO = 5120;

    public const FORMATS = 'jpg,jpeg,png,pdf';

    public static function typeDeTable(string $table): ?string
    {
        return ['purchases' => 'achat', 'expenses' => 'depense'][$table] ?? null;
    }

    /** @return array{0: class-string, 1: string}|null */
    private function type(string $type): ?array
    {
        return self::TYPES[$type] ?? null;
    }

    /** Range [fichier] et le rattache à l'enregistrement ; rend le chemin posé, ou `null` si l'enregistrement est inconnu. */
    public function rattacher(string $type, string $id, UploadedFile $fichier): ?string
    {
        [$modele, $dossier] = $this->type($type) ?? [null, null];
        $enregistrement = $modele ? $modele::find($id) : null;
        if ($enregistrement === null) {
            return null;
        }

        $ancien = $enregistrement->receipt_path;
        $chemin = $fichier->store($dossier, 'local');
        $enregistrement->forceFill(['receipt_path' => $chemin])->save();

        if ($ancien && $ancien !== $chemin) {
            Storage::disk('local')->delete($ancien);
        }
        AuditLog::record($type === 'achat' ? 'purchase.receipt_attached' : 'expense.receipt_attached', 'achats');

        return $chemin;
    }

    public function existe(string $type, string $id): bool
    {
        [$modele] = $this->type($type) ?? [null];
        $chemin = $modele ? $modele::whereKey($id)->value('receipt_path') : null;

        return $chemin !== null && Storage::disk('local')->exists($chemin);
    }

    /** Le fichier en lecture (en ligne, pas en téléchargement forcé), ou `null` s'il n'y en a pas. */
    public function lire(string $type, string $id): ?StreamedResponse
    {
        [$modele] = $this->type($type) ?? [null];
        $chemin = $modele ? $modele::whereKey($id)->value('receipt_path') : null;
        if ($chemin === null || ! Storage::disk('local')->exists($chemin)) {
            return null;
        }

        return Storage::disk('local')->response($chemin);
    }
}
