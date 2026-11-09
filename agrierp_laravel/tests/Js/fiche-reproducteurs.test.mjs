import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { REPRODUCTEURS_F as R, familleDuLot } from '../../resources/js/hors-ligne/fiche-familles.js';
import { LIBELLES_VOLAILLES_FICHE as L, MOTIFS_VOLAILLES as M } from '../../resources/js/hors-ligne/fiche-volailles.js';
import { RATIONS_VOLAILLES_PROVISOIRES, LIBELLES_VOLAILLES, EMPLACEMENTS_VOLAILLES } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (fiche volailles REPRODUCTEURS) — GARDE DE SOURCES : `fiche-reproducteurs.blade.php`, `FicheReproducteurs.php` et `CategorieVolaille` sont les MAÎTRES.
 * Libellés, KPI, tableau du mois (propre à cette fiche : 6 colonnes, pas de traitements), départ obligatoire, phrases de refus, colonnes écrites par `saveDay`,
 * rationnement par catégorie.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const blade = norm(lire('resources/views/livewire/elevage/fiche-reproducteurs.blade.php'));
const php = norm(lire('app/Livewire/Elevage/FicheReproducteurs.php'));
const cat = norm(lire('app/Support/CategorieVolaille.php'));
const E = R.ecran;

test('famille : aviculture HORS stade ponte, trois catégories aux emplacements de la synchronisation', () => {
    assert.ok(php.includes("where('code', 'aviculture')") && php.includes("->where('stage', '!=', 'ponte')"));
    assert.equal(R.accepte({ species_code: 'aviculture', stage: 'croissance' }), true);
    assert.equal(R.accepte({ species_code: 'aviculture', stage: 'ponte' }), false);
    assert.equal(familleDuLot({ species_code: 'aviculture', stage: 'engraissement' }), R);
    assert.deepEqual(LIBELLES_VOLAILLES, { reproducteur: 'Reproducteur', jeune: 'Jeune', poussin: 'Poussin' });
    assert.deepEqual(EMPLACEMENTS_VOLAILLES, { reproducteur: 'repro', jeune: 'jeune', poussin: 'sevre' });
    assert.ok(cat.includes("REPRODUCTEUR => 130") && cat.includes("JEUNE => 80") && cat.includes("POUSSIN => 30"));
    assert.deepEqual(RATIONS_VOLAILLES_PROVISOIRES, { reproducteur: 130, jeune: 80, poussin: 30 });
    assert.ok(cat.includes("if ($l === self::normaliser($affiche))"), 'rapprochement par ÉGALITÉ STRICTE du libellé');
    assert.ok(php.includes('EffectifParCategorieService::VOLAILLES_REPRO'));
    assert.deepEqual(R.libelleStade('croissance') && ['reproduction', 'croissance', 'engraissement'].map((x) => R.libelleStade(x)), ['Reproducteur', 'Poussin', 'Jeune']);
    assert.ok(php.includes("'poussins_nes' =>") && php.includes("'taux_eclosion' =>"));
});

test('écran : titre, KPI (libellés et légendes), message sans bande, sélecteur de bande', () => {
    for (const t of [E.titre, E.sousTitre, E.aucuneBande, E.saisieTitre, E.bandeLabel, ...E.kpiLegendes, E.note]) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    assert.deepEqual(E.kpis, [...blade.matchAll(/<x-kpi-card label="([^"]+)"/g)].map((m) => m[1]));
    assert.deepEqual(E.kpiLegendes, [...blade.matchAll(/caption="([^"]+)"/g)].map((m) => m[1]));
    assert.ok(blade.includes("{{ $lot->code }} ({{ $lot->libelleStade() }} — {{ $lot->current_quantity }} têtes)"));
    assert.deepEqual(R.kpiValeurs({ effectif_total: 1234, taux_eclosion: null, poussins_nes: 9, taux_mortalite_mois: 2.5 }), ['1 234', '—', '9', '2,5 %']);
    assert.deepEqual(R.kpiValeurs({ effectif_total: 5, taux_eclosion: 87.5, poussins_nes: 9, taux_mortalite_mois: 0 }), ['5', '87,5 %', '9', '0,0 %']);
});

test('tableau mensuel : groupes, sous-colonnes et cellules dans l\'ordre du Blade (pas de colonne de traitements)', () => {
    const debut = blade.indexOf('<thead class="bg-surface-zebra border-b');
    const bloc = blade.slice(debut, blade.indexOf('</thead>', debut));
    const lignes = bloc.split('</tr>');
    const ths = (l) => [...l.matchAll(/<th([^>]*)>([^<]*)<\/th>/g)].map((m) => [norm(m[2]), /rowspan="2"/.test(m[1]) ? 'rowspan' : Number(/colspan="(\d+)"/.exec(m[1])?.[1] ?? 1)]);
    assert.deepEqual(E.groupes, ths(lignes[0]));
    assert.deepEqual(E.sousColonnes, ths(lignes[1]).map(([l]) => l));
    const champs = [...blade.slice(blade.indexOf('$entry = $this->monthlyEntries->get($dateStr)')).matchAll(/\$entry\?->(\w+) \?\? '—'/g)].map((m) => m[1]);
    assert.deepEqual(champs, ['ponte_total', 'ne', 'mort', 'effectif_final', 'poids_general_g']);
    assert.deepEqual(E.cellules.map((c) => c[0]), ['ponte_total', 'ne', 'mort', 'effectif_final', 'taux', 'poids_general_g']);
    assert.ok(!blade.includes('traitementsDuJour'));
});

test('saisie : libellés du Blade, dans l\'ordre ; ventes par catégorie en lecture seule', () => {
    const textes = [L.achat, L.vente, L.venteSuite, L.couvoir, L.oeufs, L.nes, L.eclosion, L.morts, L.dons, ...L.categories, L.passage, L.departTitre, L.departVerrouille, L.effectifFinal, L.taux, L.provende, L.categorie, L.effectif, L.ration, L.servie, L.totalProvende, L.pesee, L.peseeExemple, L.poidsMoyen, L.poidsMoyenSuite, L.gmq, L.enregistrer, R.prophylaxie.titre, R.prophylaxie.observations, R.prophylaxie.observationsExemple];
    for (const t of textes) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    let courant = blade.indexOf(norm(L.achat));
    for (const t of [L.achat, L.couvoir, L.oeufs, L.nes, L.eclosion, L.morts, L.dons, L.passage, L.departTitre, L.effectifFinal, L.taux, L.provende, L.pesee, L.poidsMoyen, R.prophylaxie.titre, R.prophylaxie.observations, L.enregistrer]) {
        const p = blade.indexOf(norm(t), courant);
        assert.ok(p >= courant, `« ${t} » hors de l'ordre du Blade`);
        courant = p + 1;
    }
    assert.ok(blade.includes('Reproducteur {{ $ventesJ[\'repro\'] }} · Jeune {{ $ventesJ[\'jeune\'] }} · Poussin {{ $ventesJ[\'sevre\'] }}') && L.ventesCategorie({ repro: 1, jeune: 2, sevre: 3 }) === 'Reproducteur 1 · Jeune 2 · Poussin 3');
    assert.ok(blade.includes('id="ventes-par-categorie"'));
    const ordreDepart = [...blade.matchAll(/<input id="depart-(\w+)" wire:model\.live="(depart\w+)"/g)].map((x) => x[2]);
    assert.deepEqual(ordreDepart, ['departRepro', 'departJeune', 'departSevre'], 'départ : Reproducteur, Jeune, Poussin');
    assert.ok(blade.includes(norm(M.departRequis('{{ $this->previousEffectif }}'))) && blade.includes(norm(M.departFixe("{{ \\Carbon\\Carbon::parse($cat['depart_date'])->format('d/m/Y') }}"))));
    assert.ok(blade.includes(norm(M.mortEnregistre('{{ $mortEnregistre }}'))) && blade.includes(norm(M.donEnregistre('{{ $donEnregistre }}'))));
    assert.ok(blade.includes(norm(M.rationDepart)) && blade.includes(norm(M.ventesNonVentileesAvertissement)));
    assert.ok(blade.includes(norm("Jour antérieur à l'effectif de départ fixé le {{ \\Carbon\\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} : il n'est pas saisissable.")));
    assert.ok(blade.includes(norm(M.proposition({ repro: '{{ $cat[\'proposition\'][\'repro\'] }}', jeune: '{{ $cat[\'proposition\'][\'jeune\'] }}', sevre: '{{ $cat[\'proposition\'][\'sevre\'] }}' }))));
    assert.ok(blade.includes('<x-autonomie-alimentaire :autonomie="$this->feedAutonomy" filiere="aviculture" />') && blade.includes('<x-prophylaxie-du-jour'));
});

test('refus de saveDay : mêmes phrases, même ordre ; colonnes écrites (ventilation des morts, dons et ventes, départ)', () => {
    for (const t of [M.bande, M.dateInvalide, M.departManquant, M.ancienneFiche, M.ventesNonVentilees]) assert.ok(php.includes(norm(t)), `absent du PHP : « ${t} »`);
    assert.ok(php.includes("'Jour antérieur à l\\'effectif de départ fixé le '.Carbon::parse($cat['depart_date'])->format('d/m/Y').' : il n\\'est pas saisissable.'".replace(/\\\\'/g, "'")) || php.includes("Jour antérieur à l'effectif de départ fixé le '"));
    assert.ok(php.includes(norm(M.mortsAuDessus('{$morts}', '{$this->previousEffectif}'))));
    assert.ok(php.includes("'Avertissement — fiche du '.Carbon::parse($this->selectedDate)->format('d/m/Y')"));
    const ordrePhp = ["authorize('manage-elevage')", 'Sélectionnez d\'abord une bande.', 'refusExerciceClos', 'Date invalide', "$cat['mode'] === 'avant_depart'", "$cat['mode'] === 'refus'", "$cat['mode'] === 'depart_requis'", "$cat['refus_passage'] !== null", 'non ventilés par catégorie', "$this->ventesDuJour['non_ventilee']"].map((m) => php.indexOf(norm(m)));
    assert.deepEqual([...ordrePhp].sort((a, b) => a - b), ordrePhp, 'ordre des contrôles du PHP');
    const js = lire('resources/js/hors-ligne/fiche-volailles.js');
    const fonction = js.slice(js.indexOf('export function enregistrerJourVolailles'), js.indexOf('// ----------------------------------------------------------------------------------------------------------- formulaire') > 0 ? js.indexOf('// ------------------------------------------------------------------------------------------------------------ formulaire') : undefined);
    const ordreJs = ['ctx.role', 'MOTIFS_VOLAILLES.bande', 'ctx.refusExercice', 'MOTIFS_VOLAILLES.dateInvalide', "'avant_depart'", "'refus'", "'depart_requis'", 'refus_passage', 'ancienneFiche', 'ventesNonVentilees'].map((m) => fonction.indexOf(m));
    assert.ok(ordreJs.every((p) => p >= 0));
    assert.deepEqual([...ordreJs].sort((a, b) => a - b), ordreJs, 'ordre des contrôles du JavaScript');
    const bloc = php.slice(php.indexOf('LivestockDailyEntry::updateOrCreate('), php.indexOf('if ($departAEcrire)'));
    const colonnes = [...bloc.matchAll(/'(\w+)' =>/g)].map((m) => m[1]).slice(2);
    assert.ok(colonnes.length >= 17);
    for (const c of colonnes) assert.ok(new RegExp(`\\b${c}\\b`).test(fonction), `colonne « ${c} » de saveDay non écrite par le JavaScript`);
    for (const c of ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune']) assert.ok(php.includes(`'${c}' =>`) && fonction.includes(c));
    assert.ok(php.includes('recalculerEnCascade($lot->id, $this->selectedDate)'));
});

test('rationnement et autonomie : CategorieVolaille::tableauReproducteurs, filière aviculture', () => {
    assert.ok(php.includes("CategorieVolaille::tableauReproducteurs(") && php.includes("FeedRationStandard::where('species_code', 'aviculture')"));
    assert.ok(php.includes("$service->produitProvende('aviculture')"));
    assert.ok(cat.includes("'total_kg' => $total === null ? null : round($total / 1000, 2)"));
});
