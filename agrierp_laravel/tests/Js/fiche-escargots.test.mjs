import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { ESCARGOTS_F, FAMILLES, familleDuLot } from '../../resources/js/hors-ligne/fiche-familles.js';
import { LIBELLES_ESCARGOTS as L, MOTIFS_ESCARGOTS as M } from '../../resources/js/hors-ligne/fiche-escargots.js';
import { MODULE_DESACTIVE } from '../../resources/js/hors-ligne/fiche-lapins-ecran.js';

/**
 * PWA-3 (fiche escargots) — GARDE DE SOURCES : `fiche-escargots.blade.php` et `FicheEscargots.php` sont les MAÎTRES. Libellés, ordre des champs et des
 * colonnes, KPI, textes du module désactivé et des blocs « à venir », colonnes écrites par `saveDay`, règles des morts et des dons enregistrés, et ce
 * que la fiche n'a PAS au web (prophylaxie du jour, autonomie alimentaire, rationnement : jamais inventés dans la PWA).
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/&gt;/g, '>').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const blade = norm(lire('resources/views/livewire/elevage/fiche-escargots.blade.php'));
const php = norm(lire('app/Livewire/Elevage/FicheEscargots.php'));
const pending = norm(lire('resources/views/components/module-pending.blade.php'));
const E = ESCARGOTS_F.ecran;

test('famille : espèce helico, module helico, pas de calcul par catégorie', () => {
    assert.ok(php.includes("where('code', 'helico')") && php.includes("ModuleConfig::isEnabled('helico')"));
    assert.equal(ESCARGOTS_F.espece, 'helico');
    assert.equal(ESCARGOTS_F.module, 'helico');
    assert.equal(ESCARGOTS_F.calcul, null);
    assert.equal(familleDuLot({ species_code: 'helico' }), ESCARGOTS_F);
    assert.equal(FAMILLES.escargots, ESCARGOTS_F);
});

test('ce que le web n\'a PAS pour les escargots : ni prophylaxie du jour, ni autonomie, ni rationnement calculé', () => {
    assert.ok(!blade.includes('x-prophylaxie-du-jour') && !blade.includes('x-autonomie-alimentaire'));
    assert.ok(!php.includes('AvecProphylaxieDuJour') && !php.includes('getFeedAutonomyProperty') && !php.includes('EffectifParCategorieService'));
    assert.ok(blade.includes('<x-module-pending label="Le calcul du rationnement"') && blade.includes('<x-module-pending label="Le suivi hygrométrique"'));
    assert.equal(ESCARGOTS_F.prophylaxie, null);
});

test('module désactivé et écran : titres, KPI, bandes', () => {
    for (const t of [MODULE_DESACTIVE.titre, MODULE_DESACTIVE.texte, E.titre, E.sousTitre, E.aucuneBande, E.saisieTitre]) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    assert.equal(M.moduleTitre, MODULE_DESACTIVE.titre);
    assert.equal(M.moduleTexte, MODULE_DESACTIVE.texte);
    assert.deepEqual(E.kpis, [...blade.matchAll(/<x-kpi-card label="([^"]+)"/g)].map((m) => m[1]));
    assert.ok(blade.includes("$this->kpis['taux_eclosion'] === null ? '—' : number_format($this->kpis['taux_eclosion'], 1, ',', ' ').' %'"));
    assert.deepEqual(ESCARGOTS_F.kpiValeurs({ effectif_total: 1234, naissains_mois: 7, taux_eclosion: null, taux_mortalite_mois: 2.5 }), ['1 234', '7', '—', '2,5 %']);
    assert.deepEqual(ESCARGOTS_F.kpiValeurs({ effectif_total: 5, naissains_mois: 7, taux_eclosion: 87.5, taux_mortalite_mois: 0 }), ['5', '7', '87,5 %', '0,0 %']);
    for (const cle of ['effectif_total', 'naissains_mois', 'taux_eclosion', 'taux_mortalite_mois']) assert.ok(php.includes(`'${cle}' =>`));
    assert.ok(php.includes("$totalOeufs > 0 ? round(($totalNaissains / $totalOeufs) * 100, 1) : null"));
});

test('tableau mensuel : groupes (4 colonnes d\'effectif), sous-colonnes et cellules dans l\'ordre du Blade', () => {
    const debut = blade.indexOf('<thead class="bg-surface-zebra border-b');
    const bloc = blade.slice(debut, blade.indexOf('</thead>', debut));
    const lignes = bloc.split('</tr>');
    const ths = (l) => [...l.matchAll(/<th([^>]*)>([^<]*)<\/th>/g)].map((m) => [norm(m[2]), /rowspan="2"/.test(m[1]) ? 'rowspan' : Number(/colspan="(\d+)"/.exec(m[1])?.[1])]);
    assert.deepEqual(E.groupes, ths(lignes[0]));
    assert.deepEqual(E.sousColonnes, ths(lignes[1]).map(([l]) => l));
    const champs = [...blade.slice(blade.indexOf('$entry = $this->monthlyEntries->get($dateStr)')).matchAll(/\$entry\?->(\w+) \?\? '—'/g)].map((m) => m[1]);
    assert.deepEqual(champs.slice(0, 9), ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_final']);
    assert.deepEqual(E.colonnesEffectif, ['effectif_m', 'effectif_f', 'effectif_sevres']);
    assert.ok(blade.includes("{{ $entry?->poids_general_g ?? '—' }}"), 'poids en grammes');
});

test('saisie : libellés du Blade, dans l\'ordre ; répartition par catégorie des morts et des dons', () => {
    const textes = [L.achat, L.vente, L.venteSuite, L.ponte, L.oeufs, L.naissains, L.eclosion, L.morts, L.dons, ...L.categories, ...L.effectifs, L.effectifFinal, L.taux, L.rationnementTitre, L.pesee, L.peseeExemple, L.poidsMoyen, L.poidsMoyenSuite, L.gmq, L.entretien, L.observations, L.observationsExemple, L.enregistrer];
    for (const t of textes) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    let courant = blade.indexOf(norm(L.achat));
    for (const t of [L.achat, L.ponte, L.oeufs, L.naissains, L.eclosion, L.morts, L.dons, L.effectifs[0], L.effectifFinal, L.taux, L.rationnementTitre, L.pesee, L.poidsMoyen, L.entretien, L.observations, L.enregistrer]) {
        const p = blade.indexOf(norm(t), courant);
        assert.ok(p >= courant, `« ${t} » hors de l'ordre du Blade`);
        courant = p + 1;
    }
    assert.ok(blade.includes(norm(M.mortEnregistre('{{ $mortEnregistre }}'))) && blade.includes(norm(M.donEnregistre('{{ $donEnregistre }}'))));
    for (const t of [M.rationnement.replace('Le calcul du rationnement', '{{ $label }}'), 'Prévu : {{ $since }}']) assert.ok(pending.includes(norm(t)), `composant : ${t}`);
    assert.ok(blade.includes(norm("since=\"qu'un barème officiel soit fourni pour l'héliciculture (absent de FeedRationStandards, ticket 2.7)\"")) && M.rationnementPrevu.includes("qu'un barème officiel soit fourni pour l'héliciculture (absent de FeedRationStandards, ticket 2.7)"));
    assert.ok(blade.includes("since=\"à planifier — aucune table de mesures d'hygrométrie n'existe encore ; le ticket 3.11 (soins vétérinaires) ne la fournit pas\"") && M.hygrometriePrevu.includes("à planifier — aucune table de mesures d'hygrométrie n'existe encore ; le ticket 3.11 (soins vétérinaires) ne la fournit pas"));
});

test('règles : morts et dons (répartition saisie, sinon total enregistré), colonnes écrites, refus', () => {
    assert.ok(php.includes('return $saisis > 0 ? $saisis : (int) ($this->mortEnregistre ?? 0);') && php.includes('return $saisis > 0 ? $saisis : (int) ($this->donEnregistre ?? 0);'));
    assert.ok(php.includes('$this->mortBorde + $this->mortEngraissement + $this->mortNaissain') && php.includes('$this->donBorde + $this->donEngraissement + $this->donNaissain'));
    const bloc = php.slice(php.indexOf('LivestockDailyEntry::updateOrCreate('), php.indexOf('app(SyncLotProductionStockAction::class)'));
    const colonnes = [...bloc.matchAll(/'(\w+)' =>/g)].map((m) => m[1]).slice(2); // sans `lot_id` ni `entry_date` (la clé de la fiche)
    assert.deepEqual(colonnes, ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'ponte_total', 'effectif_m', 'effectif_f', 'effectif_sevres', 'weight_sample_avg_g']);
    const js = norm(lire('resources/js/hors-ligne/fiche-escargots.js'));
    for (const c of colonnes) assert.ok(js.includes(`${c}:`), `colonne « ${c} » non écrite par le JavaScript`);
    assert.ok(!js.includes('mort_repro:') && !js.includes('cat_depart'), 'aucune colonne de répartition écrite');
    assert.ok(php.includes(norm(M.aucuneBande)) && php.includes('refusExerciceClos($this->selectedDate)') && php.includes("$this->authorize('manage-elevage')"));
    assert.ok(php.includes('recalculerEnCascade($lot->id, $this->selectedDate)'));
    assert.ok(php.includes('$this->oeufsTerre > 0 ? round(($this->naissainsNes / $this->oeufsTerre) * 100, 1) : null'));
    assert.ok(php.includes("return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->naissainsNes, $mort, $this->venteDuJour, $this->donDuJour(),"));
});
