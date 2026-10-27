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

        $v = $request->validate(array_merge([
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
            'civilite'       => ['nullable', 'in:M.,Mme'],
        ], $this->reglesSignataires()), [
            'person_id.required' => 'Ce champ est obligatoire.',
        ]);

        $personne = $this->service->personne($v['type'], $v['person_id']);

        if (! $personne) {
            throw ValidationException::withMessages([
                'person_id' => ["Cette personne n'existe pas (ou plus) sur le serveur. Synchronisez."],
            ]);
        }

        // ⚠️ Arguments NOMMÉS : la fabrique a plus de dix paramètres, et un appel positionnel avait glissé
        // l'appréciation dans la civilité (le poste envoyait civilité et signataires, le serveur les ignorait).
        $resultat = $this->service->generer(
            type: $v['type'],
            personne: $personne,
            contrat: $v['contract_type'] ?? 'CDI',
            debut: $v['start_date'] ?? null,
            fin: $v['end_date'] ?? null,
            note: ($v['note'] ?? null) ?: ($v['appreciation'] ?? null),
            domaines: $v['domaines'] ?? [],
            civilite: $v['civilite'] ?? 'M.',
            signataires: $this->surcharges($v),
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

        $v = $request->validate(array_merge([
            'body_text' => ['sometimes', 'required', 'string', 'max:5000'],
            // ATT-2 : règle de signature selon la durée (paramétrable au web et au poste).
            'seuil_signature_mois' => ['sometimes', 'required', 'integer', 'min:1', 'max:120'],
            'appreciation_text'    => ['sometimes', 'nullable', 'string', 'max:1000'],
            'appreciation_imprimee' => ['sometimes', 'boolean'],
        ], $this->reglesSignataires(modele: true)), [
            'body_text.required' => 'Ce champ est obligatoire.',
            'seuil_signature_mois.min' => 'La durée doit être d\'au moins 1 mois.',
            'seuil_signature_mois.max' => 'La durée ne peut pas dépasser 120 mois.',
        ]);

        // `sigN_titre` est NON NULLABLE en base (le Directeur n'a pas d'intitulé : chaîne vide) ; un client qui envoie
        // une chaîne vide la fait lire comme `null` par le middleware de normalisation.
        foreach ([1, 2, 3] as $n) {
            if (array_key_exists("sig{$n}_titre", $v) && $v["sig{$n}_titre"] === null) {
                $v["sig{$n}_titre"] = '';
            }
        }

        AttestationTemplate::forType($type)->update($v);

        AuditLog::record('attestation_template.updated', 'rh', $request->user()->id);

        return response()->json(['message' => 'Modèle enregistré avec succès.']);
    }

    /**
     * Règles des trois signataires. À la génération : intitulé, nom et fonction de CETTE attestation.
     * Au modèle (`$modele`) : les mêmes, plus les drapeaux « signe les attestations courtes / longues ».
     *
     * @return array<string, list<string>>
     */
    private function reglesSignataires(bool $modele = false): array
    {
        $regles = [];

        foreach ([1, 2, 3] as $n) {
            $regles["sig{$n}_titre"] = [$modele ? 'sometimes' : 'nullable', 'nullable', 'string', 'max:120'];
            $regles["sig{$n}_nom"] = [$modele ? 'sometimes' : 'nullable', 'nullable', 'string', 'max:160'];
            $regles["sig{$n}_fonction"] = [$modele ? 'sometimes' : 'nullable', 'nullable', 'string', 'max:300'];

            if ($modele) {
                $regles["sig{$n}_court"] = ['sometimes', 'boolean'];
                $regles["sig{$n}_long"] = ['sometimes', 'boolean'];
            }
        }

        return $regles;
    }

    /**
     * Les surcharges de signataires envoyées avec la demande (« sig1 » … « sig3 »).
     *
     * @return array<string, array{titre?: ?string, nom?: ?string, fonction?: ?string}>
     */
    private function surcharges(array $v): array
    {
        $surcharges = [];

        foreach ([1, 2, 3] as $n) {
            foreach (['titre', 'nom', 'fonction'] as $champ) {
                if (array_key_exists("sig{$n}_{$champ}", $v)) {
                    $surcharges["sig{$n}"][$champ] = $v["sig{$n}_{$champ}"];
                }
            }
        }

        return $surcharges;
    }
}
