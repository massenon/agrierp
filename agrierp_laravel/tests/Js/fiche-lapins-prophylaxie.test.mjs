import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { LIBELLES, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-prophylaxie.js';

/**
 * PWA-3 (fiche lapins) — GARDE DE SOURCES de la prophylaxie du jour : le composant Blade `prophylaxie-du-jour`, `AvecProphylaxieDuJour`,
 * `ProtocoleDuJourService` et `ProtocoleDuJour` sont les MAÎTRES ; leurs phrases, états et règles sont lus et comparés au module JavaScript.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const composant = norm(lire('resources/views/components/prophylaxie-du-jour.blade.php'));
const trait = norm(lire('app/Livewire/Elevage/Concerns/AvecProphylaxieDuJour.php'));
const service = norm(lire('app/Services/ProtocoleDuJourService.php'));
const dto = norm(lire('app/Services/ProtocoleDuJour.php'));
const blade = norm(lire('resources/views/livewire/elevage/fiche-lapins.blade.php'));

test('libellés du bloc : ceux du composant Blade', () => {
    assert.ok(composant.includes(norm(LIBELLES.jour('{{ $protocole->jourDeCycle }}'))));
    for (const t of [LIBELLES.jourInconnu, LIBELLES.aucun, LIBELLES.blocage, LIBELLES.valider]) assert.ok(composant.includes(norm(t)), `absent : « ${t} »`);
    assert.ok(composant.includes(norm(LIBELLES.nonCalculable('{{ $protocole->motifIndetermine }}'))));
    assert.ok(composant.includes(norm(LIBELLES.remanence('{{ $standard->withdrawal_days }}'))), 'rémanence');
    assert.ok(composant.includes(norm(LIBELLES.calendaires('{{ $protocole->calendairesNonEvalues }}'))));
    assert.ok(composant.includes(norm(LIBELLES.indice('{{ $protocole->enAttente() }}'))));
    assert.ok(blade.includes(norm(LIBELLES.titre)) && blade.includes(norm(LIBELLES.observations)) && blade.includes(norm(LIBELLES.observationsExemple)));
});

test('états : ceux de ProtocoleDuJour', () => {
    for (const t of [LIBELLES.etats.indetermine, LIBELLES.etats.libre, LIBELLES.etats.valide]) assert.ok(dto.includes(`'${t}'`), `état absent : ${t}`);
    assert.ok(dto.includes("' Prévu(s)'") && LIBELLES.etats.prevus(2) === '2 Prévu(s)');
});

test('refus et messages : ceux de validerTraitements et du service', () => {
    for (const t of [MOTIFS.aucuneBande, MOTIFS.jourAVenir, MOTIFS.rien]) assert.ok(trait.includes(norm(t)), `absent du PHP : « ${t} »`);
    assert.ok(trait.includes("$crees->count().' traitement(s) enregistré(s) au registre vétérinaire.'") && MOTIFS.enregistres(3) === '3 traitement(s) enregistré(s) au registre vétérinaire.');
    assert.ok(service.includes(norm(MOTIFS.reproduction)) && service.includes(norm(MOTIFS.miseEnLot)));
});

test('règles : jour de cycle, traitements dus, rémanence, colonnes du soin', () => {
    assert.ok(service.includes('round($reference->diffInDays($jour, false)) + 1'), 'jour de cycle PHP');
    assert.ok(service.includes("'cycle_day_start', '<=', $jourDeCycle") && service.includes("'cycle_day_end', '>=', $jourDeCycle"));
    assert.ok(service.includes("$bande->stage === 'reproduction'") && service.includes("latest('saillie_date')"));
    const js = norm(lire('resources/js/hors-ligne/fiche-lapins-prophylaxie.js'));
    assert.ok(js.includes("lot.stage === 'reproduction'") && js.includes('+ 1 : null'));
    const action = norm(lire('app/Actions/ValidateProphylaxisTreatmentsAction.php'));
    for (const [php, jsCle] of [["'action_type' => $standard->treatment", 'action_type: s.treatment'], ["'product_used' => $standard->product_recommended", 'product_used: s.product_recommended'], ["'dose' => $standard->dosage", 'dose: s.dosage'], ["(int) $standard->withdrawal_days", 'withdrawal_days: Math.trunc']]) {
        assert.ok(action.includes(php), `PHP : ${php}`);
        assert.ok(js.includes(jsCle), `JS : ${jsCle}`);
    }
    const soin = norm(lire('app/Actions/RecordVeterinaryCareAction.php'));
    assert.ok(soin.includes("addDays($remanenceJours)") && soin.includes("$remanenceJours > 0 && ! empty($donnees['product_used'])"));
    assert.ok(js.includes('soin.withdrawal_days > 0') && js.includes('!soin.product_used'));
});

test('envoi : clé et colonnes du poste (pushVeterinaryRecords), droit manage-elevage', () => {
    const controleur = norm(lire('app/Http/Controllers/Api/SyncController.php'));
    assert.ok(controleur.includes("'veterinary_records' => 'manage-elevage'"));
    const synchro = lire('resources/js/hors-ligne/synchro.js');
    assert.ok(synchro.includes('veterinary_records: liste.map'));
    for (const c of ["'lot_id' => ['required', 'uuid', 'exists:livestock_lots,id']", "'action_type' => ['required', 'string', 'max:100']", "'record_date' => ['required', 'date']", "'withdrawal_days' => ['nullable', 'integer', 'min:0']"]) assert.ok(controleur.includes(c), c);
    const js = norm(lire('resources/js/hors-ligne/fiche-lapins-prophylaxie.js'));
    for (const c of ['lot_id', 'action_type', 'record_date', 'withdrawal_days', 'product_used', 'dose', 'symptomes']) assert.ok(js.includes(c));
});
