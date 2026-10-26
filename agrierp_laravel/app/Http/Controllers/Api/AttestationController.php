<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Services\AttestationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.13 — ATTESTATIONS DEPUIS UN POSTE.
 *
 * Même fabrique que la page web (`AttestationService`) : même texte, même PDF.
 *
 * ⚠️ MÊMES DROITS QUE LA PAGE WEB. Générer exige `view-rh` (la route du hub
 * Personnel & Stages), enregistrer un modèle exige `manage-rh`
 * (`Attestations::saveTemplate`). Un jeton Sanctum n'ouvre pas ce que le rôle de
 * son porteur ferme sur le web.
 *
 * ⚠️ LA GÉNÉRATION EST JOURNALISÉE ICI, côté serveur, À CHAQUE APPEL : c'est ce
 * qui alimente le compteur « Attestations émises ». Une attestation produite au
 * poste sans passer par cette route ne laisserait aucune trace.
 */
class AttestationController extends Controller
{
    public function __construct(private readonly AttestationService $service) {}

    public function generer(Request $request): Response|JsonResponse
    {
        abort_unless($request->user()->can('view-rh'), 403, "Votre rôle ne permet pas d'éditer des attestations.");

        $v = $request->validate([
            'type'           => ['required', 'in:'.implode(',', AttestationService::TYPES)],
            'person_id'      => ['required', 'string'],
            'contract_type'  => ['nullable', 'string', 'max:60'],
            'start_date'     => ['nullable', 'date'],
            'end_date'       => ['nullable', 'date'],
            'note'           => ['nullable', 'string', 'max:1000'],
            'domaines'       => ['nullable', 'array'],
            'domaines.*'     => ['string', 'in:'.implode(',', array_keys(AttestationService::DOMAINES))],
            'appreciation'   => ['nullable', 'string', 'max:500'],
            'birth_date'     => ['nullable', 'date'],
            'birth_place'    => ['nullable', 'string', 'max:100'],
        ], [
            'person_id.required' => 'Ce champ est obligatoire.',
        ]);

        $personne = $this->service->personne($v['type'], $v['person_id']);

        if (! $personne) {
            throw ValidationException::withMessages([
                'person_id' => ["Cette personne n'existe pas (ou plus) sur le serveur. Synchronisez."],
            ]);
        }

        $resultat = $this->service->generer(
            $v['type'],
            $personne,
            $v['contract_type'] ?? 'CDI',
            $v['start_date'] ?? null,
            $v['end_date'] ?? null,
            $v['note'] ?? null,
            $v['domaines'] ?? [],
            $v['appreciation'] ?? null,
            $v['birth_date'] ?? null,
            $v['birth_place'] ?? null,
        );

        return response($resultat['octets'], 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="'.$resultat['fichier'].'"',
        ]);
    }

    public function enregistrerModele(Request $request, string $type): JsonResponse
    {
        abort_unless(in_array($type, AttestationService::TYPES, true), 404);
        abort_unless($request->user()->can('manage-rh'), 403, 'Votre rôle ne permet pas de modifier les modèles.');

        $v = $request->validate([
            'body_text' => ['required', 'string', 'max:5000'],
        ], [
            'body_text.required' => 'Ce champ est obligatoire.',
        ]);

        AttestationTemplate::forType($type)->update(['body_text' => $v['body_text']]);

        AuditLog::record('attestation_template.updated', 'rh', $request->user()->id);

        return response()->json(['message' => 'Modèle enregistré avec succès.']);
    }
}
