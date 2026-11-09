import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { PORCS_F, LAPINS_F, FAMILLES, familleDuLot } from '../../resources/js/hors-ligne/fiche-familles.js';
import { LIBELLES_PORCS, RATIONS_PORCS_DE_SECOURS } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (fiche porcs) — GARDE DE SOURCES : `fiche-porcs.blade.php` et `FichePorcs.php` (avec `CategorieRationPorc`) sont les MAÎTRES de la fiche
 * porcs de la PWA ; les libellés, l'ordre des colonnes et des champs, les phrases de refus, l'unité (Kg), la clé de ration et l'espèce de la
 * famille « porcs » (`fiche-familles.js`) sont lus dans leurs sources et comparés. Les règles communes (saveDay, autonomie, prophylaxie) restent
 * gardées par les tests des lapins, qui lisent `FicheLapins.php` : ce fichier prouve que `FichePorcs.php` les porte à l'identique ou dit ce qui diffère.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const blade = norm(lire('resources/views/livewire/elevage/fiche-porcs.blade.php'));
const php = norm(lire('app/Livewire/Elevage/FichePorcs.php'));
const phpLapins = norm(lire('app/Livewire/Elevage/FicheLapins.php'));
const ration = norm(lire('app/Support/CategorieRationPorc.php'));
const E = PORCS_F.ecran;
const L = PORCS_F.libelles;

test('espèce et filière : porciculture, « porcine »', () => {
    assert.ok(php.includes("return 'porciculture';"));
    assert.equal(PORCS_F.espece, 'porciculture');
    assert.ok(blade.includes('filiere="porcine"') && PORCS_F.filiere === 'porcine');
    assert.equal(familleDuLot({ species_code: 'porciculture' }), PORCS_F);
    assert.equal(familleDuLot({ species_code: 'cuniculture' }), LAPINS_F);
    assert.equal(familleDuLot({ species_code: 'aviculture', stage: 'ponte' })?.id, 'pondeuses', 'les pondeuses sont l\'autre famille de volailles');
    assert.equal(familleDuLot({ species_code: 'aviculture', stage: 'croissance' })?.id, 'reproducteurs');
    assert.deepEqual(Object.keys(FAMILLES), ['lapins', 'porcs', 'escargots', 'reproducteurs', 'pondeuses']);
});

test('écran : titre, KPI (libellés, valeurs), message sans bande, titre de saisie', () => {
    for (const t of [E.titre.replace('Fiches Porcs - Porciculture', 'Fiches Porcs - Porciculture'), E.sousTitre, E.aucuneBande, E.saisieTitre]) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    const labels = [...blade.matchAll(/<x-kpi-card label="([^"]+)"/g)].map((m) => m[1]);
    assert.deepEqual(E.kpis, labels);
    assert.ok(blade.includes("$this->kpis['truies'].' Truies / '.$this->kpis['verrats'].' Verrats'"));
    assert.deepEqual(PORCS_F.kpiValeurs({ effectif_total: 1234, truies: 12, verrats: 3, porcelets_sous_mere: 40, taux_mortalite_mois: 2.5 }), ['1 234', '12 Truies / 3 Verrats', '40', '2,5 %']);
    for (const cle of ['truies', 'verrats', 'porcelets_sous_mere', 'taux_mortalite_mois', 'effectif_total']) assert.ok(php.includes(`'${cle}' =>`), `KPI PHP : ${cle}`);
    assert.ok(php.includes("'truies' => (int) $latestPerLot->sum('effectif_f')") && php.includes("'verrats' => (int) $latestPerLot->sum('effectif_m')") && php.includes("'porcelets_sous_mere' => (int) $latestPerLot->sum('effectif_sevres')"));
});

test('tableau mensuel : groupes, sous-colonnes et cellules dans l\'ordre du Blade (Truies avant Verrats, poids en Kg)', () => {
    const debut = blade.indexOf('<thead class="bg-surface-zebra border-b');
    const bloc = blade.slice(debut, blade.indexOf('</thead>', debut));
    const lignes = bloc.split('</tr>');
    const ths = (l) => [...l.matchAll(/<th([^>]*)>([^<]*)<\/th>/g)].map((m) => [norm(m[2]), /rowspan="2"/.test(m[1]) ? 'rowspan' : Number(/colspan="(\d+)"/.exec(m[1])?.[1])]);
    assert.deepEqual(E.groupes, ths(lignes[0]));
    assert.deepEqual(E.sousColonnes, ths(lignes[1]).map(([l]) => l));
    const champs = [...blade.slice(blade.indexOf('$entry = $this->monthlyEntries->get($dateStr)')).matchAll(/\$entry\?->(\w+) \?\? '—'/g)].map((m) => m[1]);
    assert.deepEqual(champs.slice(0, 10), ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_f', 'effectif_m', 'effectif_sevres', 'effectif_smeres', 'effectif_final']);
    assert.deepEqual(E.colonnesEffectif, ['effectif_f', 'effectif_m', 'effectif_sevres', 'effectif_smeres']);
    assert.ok(blade.includes('round(($entry->weight_sample_avg_g * $entry->effectif_final) / 1000, 1)'), 'poids en Kg, une décimale');
    assert.ok(blade.includes('{{ $poidsKg ?? \'—\' }}'));
});

test('saisie : libellés du Blade, ordre des champs (morts, dons, départ, effectifs, pesée en Kg)', () => {
    const textes = [L.titre, L.achat, L.ne, L.morts, L.dons, L.passage, L.passageSuite, L.departSaisissable, L.departVerrouille, L.effectifM, L.effectifF, L.effectifSevres, L.effectifSmeres,
        L.effectifFinal, L.taux, L.pesee, L.echantillon, L.echantillonAuto, L.poidsMoyen, L.gmq, L.enregistrer, L.provende, L.categorie, L.effectif, L.ration, L.servie, L.totalProvende, ...L.mortsCat, ...L.donsCat, L.peseeExemple, PORCS_F.prophylaxie.titre, PORCS_F.prophylaxie.observations, PORCS_F.prophylaxie.observationsExemple];
    for (const t of textes) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    // Ordre des trois catégories de morts puis de dons, puis du départ (Reproducteur, Porcelet, Porc Marchand).
    const pos = (t, depuis = 0) => blade.indexOf(norm(t), depuis);
    const m = L.mortsCat.map((t) => pos(t, pos(L.morts)));
    assert.deepEqual([...m].sort((a, b) => a - b), m);
    const d = L.donsCat.map((t, i) => blade.indexOf(norm(t), pos(L.dons) + (i === 0 ? 0 : 1)));
    assert.ok(d.every((p) => p > 0));
    const ordreDepart = [...blade.matchAll(/<input id="depart-(\w+)" wire:model\.live="(depart\w+)"/g)].map((x) => x[2]);
    assert.deepEqual(L.ordreDepart.map((x) => x[0]), ordreDepart);
    assert.deepEqual(L.ordreDepart.map((x) => x[0]), ['departRepro', 'departSevre', 'departJeune']);
    const ordre = ['achat', 'ne', 'morts', 'dons', 'passage', 'departSaisissable', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres', 'effectifFinal', 'taux', 'pesee', 'poidsMoyen', 'enregistrer'];
    // Recherche SÉQUENTIELLE : chaque libellé est cherché après le précédent (« Verrats » existe aussi dans un libellé de KPI).
    let courant = pos(L.achat);
    for (const k of ordre) {
        const p = blade.indexOf(norm(L[k]), courant);
        assert.ok(p >= courant, `libellé « ${L[k]} » (${k}) hors de l'ordre du Blade`);
        courant = p + 1;
    }
    assert.ok(blade.includes('wire:model.live="peseeTotalKg" type="number" min="0" step="0.1"'), 'pesée en Kg avec pas de 0,1');
    assert.ok(blade.includes("number_format($peseeTotalKg / $this->effectifFinalCalc, 1).' Kg'") && blade.includes("number_format($this->poidsMoyenEstimeKg, 2) }} Kg / animal"));
});

test('provende : lignes dans l\'ordre du Blade, identifiants, ration du reproducteur en g et en Kg, clé de ration', () => {
    const ids = [...blade.matchAll(/<input id="cat-eff-(\w+)"/g)].map((m) => m[1]);
    assert.deepEqual(L.lignesProvende.map((x) => x[1]), ids);
    assert.deepEqual(L.lignesProvende.map((x) => x[2]), ['Porcelet', 'Porc Marchand', 'Reproducteur']);
    assert.ok(blade.includes("number_format($provende['repro']['ration'], 0, ',', ' ') }} g/j ({{ number_format($provende['repro']['ration'] / 1000, 1) }} Kg)"));
    assert.equal(PORCS_F.rationAffichee('repro', 2000), '2 000 g/j (2.0 Kg)');
    assert.equal(PORCS_F.rationAffichee('porcelet', 300), '300 g/j');
    assert.deepEqual(RATIONS_PORCS_DE_SECOURS, { reproducteur: 2000, porcelet: 300, marchand: 600 });
    assert.ok(ration.includes("REPRODUCTEUR => 2000") && ration.includes("PORCELET => 300") && ration.includes("MARCHAND => 600"));
    assert.ok(ration.includes("'Porc Marchand'") && LIBELLES_PORCS.marchand === 'Porc Marchand');
    assert.ok(ration.includes("str_contains($l, 'marchand') || str_contains($l, 'engraissement') || preg_match('/^jeune( porc)?$/', $l) === 1"));
    assert.ok(php.includes('CategorieRationPorc::ration($rations, CategorieRationPorc::PORCELET)'));
});

test('refus : phrases de FichePorcs.php (espèce, catégories), mêmes contrôles que les lapins', () => {
    assert.ok(php.includes(norm(PORCS_F.motifs.aucuneBande)) && php.includes(norm(PORCS_F.motifs.ancienneFiche)));
    // Le reste de saveDay est identique à FicheLapins (les gardes des lapins le lisent) : mêmes contrôles, même ordre.
    for (const phrase of ['Date invalide : choisissez un jour.', 'refusExerciceClos', "$cat['refus_passage']", 'verifierDepart($departSaisi', 'recalculerEnCascade($lot->id, $this->selectedDate)', "$this->authorize('manage-elevage')"]) {
        assert.ok(php.includes(norm(phrase)) && phpLapins.includes(norm(phrase)), `contrôle absent d'une des deux fiches : ${phrase}`);
    }
    assert.ok(php.includes('EffectifParCategorieService::calculerJour(EffectifParCategorieService::PORCS'));
    assert.ok(php.includes('Morts du jour ({$morts}) supérieurs à l\'effectif de la veille ({$this->previousEffectif}) : l\'effectif est ramené à 0, vérifiez la saisie.'));
});

test('prophylaxie, transferts et mois : mêmes traits et même composant que les lapins', () => {
    for (const t of ['use AvecProphylaxieDuJour;', 'use AvecSoinsDuMois;', 'use AvecTransfertsDuJour;', 'use AvecDepartAutomatique;', 'use \\App\\Livewire\\Elevage\\Concerns\\AvecMoisDeFiche;']) assert.ok(php.includes(norm(t)) && phpLapins.includes(norm(t)), `trait absent d'une des deux fiches : ${t}`);
    assert.ok(blade.includes('<x-prophylaxie-du-jour :protocole="$protocoleDuJour" />') && blade.includes('<x-autonomie-alimentaire'));
    assert.ok(php.includes('protected function bandeDeLaFiche()') && php.includes('return $this->bande;'), 'le protocole du jour porte sur LA bande de la fiche');
});

test('poids : colonne en grammes, saisie et affichage en Kg (conversion ×1000 à l\'enregistrement)', () => {
    assert.ok(php.includes("(int) round(($this->peseeTotalKg * 1000) / $effectifFinal)"));
    assert.ok(php.includes('round(($entry->weight_sample_avg_g * $effectifFiche) / 1000, 2)'));
    assert.ok(php.includes('return round($derniere->weight_sample_avg_g / 1000, 2);') && php.includes('return round($estimG / 1000, 2);'));
    const saisie = lire('resources/js/hors-ligne/fiche-lapins-saisie.js');
    assert.ok(saisie.includes('F.kg ? Number(s.peseeTotal) * 1000') && saisie.includes('arrondiPhp((Number(f.weight_sample_avg_g) * final) / 1000, 2)'));
});
