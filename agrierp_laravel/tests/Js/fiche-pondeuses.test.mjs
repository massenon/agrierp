import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { PONDEUSES_F as P, FAMILLES, familleDuLot } from '../../resources/js/hors-ligne/fiche-familles.js';
import { LIBELLES_PONDEUSES_FICHE as L, MOTIFS_PONDEUSES as M, STADES_SAISIE, produitOeufs, enPlateaux } from '../../resources/js/hors-ligne/fiche-pondeuses.js';
import { LIBELLES_STADES_PONDEUSE, EMPLACEMENTS_STADES_PONDEUSE, RATIONS_STADES_PONDEUSE_PAR_DEFAUT, CLES_STADES_PONDEUSE, OEUFS_PAR_PLATEAU } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (fiche volailles PONDEUSES, VOL-2) — GARDE DE SOURCES : `fiche-pondeuses.blade.php`, `FichePondeuses.php`, `StadePondeuse` et `EggStockLedgerService`
 * sont les MAÎTRES. Libellés, KPI, tableau du mois, départ à quatre stades, trois passages, œufs, phrases de refus, colonnes écrites par `saveDay`, rationnement par stade.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const blade = norm(lire('resources/views/livewire/elevage/fiche-pondeuses.blade.php'));
const php = norm(lire('app/Livewire/Elevage/FichePondeuses.php'));
const stade = norm(lire('app/Support/StadePondeuse.php'));
const egg = norm(lire('app/Services/EggStockLedgerService.php'));
const E = P.ecran;

test('famille : aviculture au stade ponte, quatre stades aux libellés et emplacements du serveur', () => {
    assert.ok(php.includes("where('code', $this->speciesCode())") || php.includes("where('code', $this->speciesCode()"));
    assert.ok(php.includes("->where('stage', 'ponte')") && php.includes("->orderBy('code')"));
    assert.equal(P.accepte({ species_code: 'aviculture', stage: 'ponte' }), true);
    assert.equal(P.accepte({ species_code: 'aviculture', stage: 'croissance' }), false);
    assert.equal(familleDuLot({ species_code: 'aviculture', stage: 'ponte' }), P);
    assert.deepEqual(Object.keys(FAMILLES), ['lapins', 'porcs', 'escargots', 'reproducteurs', 'pondeuses']);
    for (const [cle, libelle] of Object.entries(LIBELLES_STADES_PONDEUSE)) assert.ok(stade.includes(norm(`self::${{ poussin_ponte: 'POUSSIN_PONTE', poussin_croissance: 'POUSSIN_CROISSANCE', poulette: 'POULETTE', pondeuse: 'PONDEUSE' }[cle]} => '${libelle}'`)), cle);
    assert.deepEqual(CLES_STADES_PONDEUSE, ['poussin_ponte', 'poussin_croissance', 'poulette', 'pondeuse']);
    for (const [cle, emp] of Object.entries(EMPLACEMENTS_STADES_PONDEUSE)) assert.ok(stade.includes(`self::${{ poussin_ponte: 'POUSSIN_PONTE', poussin_croissance: 'POUSSIN_CROISSANCE', poulette: 'POULETTE', pondeuse: 'PONDEUSE' }[cle]} => '${emp}'`), cle);
    assert.deepEqual(RATIONS_STADES_PONDEUSE_PAR_DEFAUT, { poussin_ponte: 30, poussin_croissance: 60, poulette: 80, pondeuse: 110 });
    for (const [cle, v] of Object.entries(RATIONS_STADES_PONDEUSE_PAR_DEFAUT)) assert.ok(stade.includes(`self::${{ poussin_ponte: 'POUSSIN_PONTE', poussin_croissance: 'POUSSIN_CROISSANCE', poulette: 'POULETTE', pondeuse: 'PONDEUSE' }[cle]} => ${v}`), cle);
    assert.ok(stade.includes('if ($l === self::normaliser(self::LIBELLES[$cle]))'), 'rapprochement par ÉGALITÉ STRICTE, tranche d\'âge ignorée');
    assert.ok(php.includes('EffectifParCategorieService::VOLAILLES_PONTE'));
    assert.deepEqual(STADES_SAISIE.map((s) => [s.cle, s.emp]), [['poussin_ponte', 'quatre'], ['poussin_croissance', 'sevre'], ['poulette', 'jeune'], ['pondeuse', 'repro']]);
});

test('écran : titre, KPI, message sans bande, taux de ponte moyen et stock de plateaux du PHP', () => {
    for (const t of [E.titre, E.sousTitre, E.aucuneBande, E.saisieTitre]) assert.ok(blade.includes(norm(t)), `absent du Blade : « ${t} »`);
    assert.deepEqual(E.kpis, [...blade.matchAll(/<x-kpi-card label="([^"]+)"/g)].map((m) => m[1]).filter((v, i, a) => a.indexOf(v) === i));
    assert.ok(blade.includes("pending-since=\"qu'un produit \"Œufs de table\" existe au catalogue\"") || blade.includes('existe au catalogue'));
    assert.ok(P.kpiLegendeDe({ stock_plateaux: null })[2].includes('Œufs de table'));
    assert.ok(php.includes("$tauxPonteMoyen = $effectifTotal > 0 && $joursAvecEffectif > 0 ? round(($totalOr / $joursAvecEffectif) / $effectifTotal * 100, 1) : 0.0;"));
    assert.ok(php.includes("'stock_plateaux' => $this->eggProduct ? (int) floor($this->eggProduct->stock_qty) : null"));
    assert.deepEqual(P.kpiValeurs({ effectif: 1234, taux_ponte_moyen: 61.25, stock_plateaux: 12, taux_mortalite_mois: 2.5 }), ['1 234', '61,3 %', '12 Plateaux', '2,5 %']);
    assert.deepEqual(P.kpiValeurs({ effectif: 5, taux_ponte_moyen: 0, stock_plateaux: null, taux_mortalite_mois: 0 }), ['5', '0,0 %', '—', '0,0 %']);
});

test('œufs : produit « Œufs » du serveur (premier par nom contenant « oeufs »), plateaux de 30', () => {
    assert.ok(egg.includes("Product::orderBy('name')->get() ->first(fn (Product $p) => str_contains($this->normaliser((string) $p->name), 'oeufs'))") || egg.includes("str_contains($this->normaliser((string) $p->name), 'oeufs')"));
    assert.ok(egg.includes("str_replace('œ', 'oe', mb_strtolower($libelle))"));
    assert.ok(egg.includes('OEUFS_PAR_PLATEAU = 30') && OEUFS_PAR_PLATEAU === 30);
    assert.ok(egg.includes("'plateaux' => intdiv($oeufs, self::OEUFS_PAR_PLATEAU)") && egg.includes("'vrac' => $oeufs % self::OEUFS_PAR_PLATEAU"));
    assert.deepEqual(enPlateaux(95), { plateaux: 3, vrac: 5 });
    assert.deepEqual(enPlateaux(-4), { plateaux: 0, vrac: 0 });
    assert.equal(produitOeufs([{ name: 'Poulet' }, { name: 'Œufs de table', stock_qty: 3 }, { name: 'Plateau d\'oeufs' }]).name, 'Plateau d\'oeufs');
    assert.equal(produitOeufs([{ name: 'Poulet' }]), null);
    assert.ok(php.includes('$this->commercialisables') && php.includes('max(0, $this->oeufsRecoltes - $this->oeufsCasses)'));
    assert.ok(php.includes('round(($this->oeufsRecoltes / $this->previousEffectif) * 100, 1)'));
    // Le stock d'œufs (incrémentation, grand livre) reste au serveur : le navigateur n'en écrit rien.
    assert.ok(php.includes('app(RecordEggProductionStockAction::class)->execute($dailyEntry)') && php.includes('->ligne($this->selectedDate, $this->commercialisables)'));
    const js = lire('resources/js/hors-ligne/fiche-pondeuses.js');
    assert.ok(!/stock_qty\s*=|stock_movements|StockMovement/.test(js.replace(/\/\*\*[\s\S]*?\*\//g, '')), 'le navigateur ne touche à aucun stock');
});

test('tableau mensuel : groupes, sous-colonnes et cellules dans l\'ordre du Blade (avec traitements)', () => {
    const debut = blade.indexOf('<thead class="bg-surface-zebra border-b');
    const bloc = blade.slice(debut, blade.indexOf('</thead>', debut));
    const lignes = bloc.split('</tr>');
    const ths = (l) => [...l.matchAll(/<th([^>]*)>([^<]*)<\/th>/g)].map((m) => [norm(m[2]), /rowspan="2"/.test(m[1]) ? 'rowspan' : Number(/colspan="(\d+)"/.exec(m[1])?.[1] ?? 1)]);
    assert.deepEqual(E.groupes, ths(lignes[0]));
    assert.deepEqual(E.sousColonnes, ths(lignes[1]).map(([l]) => l));
    assert.deepEqual(E.cartes, [...E.sousColonnes, 'Traitements & Rappels']);
    const corps = blade.slice(blade.indexOf('$entry = $this->monthlyEntries->get($dateStr)'));
    assert.ok(corps.includes('$entry->previousEffectif()') && corps.includes("$this->traitementsDuJour($dateStr, $entry)"));
    assert.ok(corps.includes('round((($entry->ponte_total ?? 0) / $entry->previousEffectif()) * 100, 1)'));
    assert.ok(corps.includes("max(0, ($entry->ponte_total ?? 0) - ($entry->ponte_casses ?? 0))"));
    assert.deepEqual(E.cellules.map((c) => c[0]), ['effectif_debut', 'mort', 'taux', 'effectif_final', 'ponte_total', 'taux_ponte', 'ponte_casses', 'comm', 'stock', 'stock', 'stock', 'stock', 'traitements']);
    assert.ok(corps.includes("$isToday ? $this->stockToday['srh']") && E.note.includes('serveur'), 'le stock par jour est celui du serveur : « — » hors ligne');
    assert.ok(blade.includes(norm('Colonnes SRH/TS/OS/Stock Final : valeurs précises uniquement pour le jour sélectionné')));
});

test('saisie : libellés du Blade, dans l\'ordre ; trois passages ; départ à quatre stades', () => {
    const textes = [L.achat, L.ne, L.vente, L.venteSuite, L.oeufs, L.recoltes, L.casses, L.commercialisables, L.tauxPonte, L.morts, L.dons, ...L.passages, L.departTitre, L.departVerrouille, L.effectifFinal, L.taux, L.provende, L.categorie, L.effectif, L.ration, L.servie, L.totalProvende, L.pesee, L.peseeExemple, L.taille, L.poidsMoyen, L.poidsMoyenSuite, L.stockTitre, ...L.stockCases, L.enregistrer, P.prophylaxie.titre, P.prophylaxie.observations, P.prophylaxie.observationsExemple, ...Object.values(LIBELLES_STADES_PONDEUSE)];
    for (const t of textes) assert.ok(blade.includes(norm(t)) || php.includes(norm(t)) || stade.includes(norm(t)), `absent du Blade : « ${t} »`);
    let courant = blade.indexOf(norm(L.achat));
    for (const t of [L.achat, L.ne, L.vente, L.oeufs, L.recoltes, L.casses, L.commercialisables, L.tauxPonte, L.morts, L.dons, L.passages[0], L.departTitre, L.effectifFinal, L.taux, L.provende, L.pesee, L.stockTitre, P.prophylaxie.titre, P.prophylaxie.observations, L.enregistrer]) {
        const p = blade.indexOf(norm(t), courant);
        assert.ok(p >= courant, `« ${t} » hors de l'ordre du Blade`);
        courant = p + 1;
    }
    assert.ok(blade.includes("{{ $libellesStades[$st['cle']] }} {{ $ventesJ[$st['emp']] }}") && L.ventesStade({ quatre: 1, sevre: 2, jeune: 3, repro: 4 }) === 'Poussin ponte (0 à 2 mois) 1 · Poussin en croissance (2 à 4 mois) 2 · Poulette (4 à 5.5 mois) 3 · Pondeuse (6 à 18 mois) 4');
    assert.ok(blade.includes('id="ventes-par-stade"'));
    assert.deepEqual([...blade.matchAll(/\['cle' => '(\w+)', 'emp' => '(\w+)', 'mort' => '(\w+)', 'don' => '(\w+)', 'depart' => '(\w+)'\]/g)].map((m) => [m[1], m[2]]), STADES_SAISIE.map((s) => [s.cle, s.emp]));
    assert.deepEqual([...blade.matchAll(/id="passage-(\d)" wire:model\.live="(passage\d)"/g)].map((m) => m[2]), ['passage1', 'passage2', 'passage3']);
    assert.ok(blade.includes(norm(M.departRequis('{{ $this->previousEffectif }}'))) && blade.includes(norm(M.departFixe("{{ \\Carbon\\Carbon::parse($cat['depart_date'])->format('d/m/Y') }}"))));
    assert.ok(blade.includes(norm(M.mortEnregistre('{{ $mortEnregistre }}'))) && blade.includes(norm(M.donEnregistre('{{ $donEnregistre }}'))));
    assert.ok(blade.includes(norm(M.rationDepart)) && blade.includes(norm(M.ventesNonVentileesAvertissement)) && blade.includes(norm(M.aucunProduitOeufs)));
    assert.ok(blade.includes(norm(L.plateaux({ plateaux: '{{ $this->plateaux[\'plateaux\'] }}', vrac: '{{ $this->plateaux[\'vrac\'] }}' }).replace('Plateaux Nets Générés (30 œufs/plateau) : ', 'Plateaux Nets Générés (30 œufs/plateau) : <strong class="text-brand-emerald text-sm">')).split('Plateaux (')[0]));
    assert.ok(blade.includes(norm(M.proposition({ repro: '{{ $cat[\'proposition\'][\'repro\'] }}', jeune: '{{ $cat[\'proposition\'][\'jeune\'] }}', sevre: '{{ $cat[\'proposition\'][\'sevre\'] }}', quatre: '{{ $cat[\'proposition\'][\'quatre\'] }}' }).replace(/\(Pondeuse \(6 à 18 mois\)/, "({{ $libellesStades['pondeuse'] }}").replace(/ · Poulette \(4 à 5.5 mois\)/, " · {{ $libellesStades['poulette'] }}").replace(/ · Poussin en croissance \(2 à 4 mois\)/, " · {{ $libellesStades['poussin_croissance'] }}").replace(/ · Poussin ponte \(0 à 2 mois\)/, " · {{ $libellesStades['poussin_ponte'] }}"))));
    assert.ok(blade.includes('<x-autonomie-alimentaire :autonomie="$this->feedAutonomy" filiere="aviculture" />') && blade.includes('<x-prophylaxie-du-jour'));
});

test('refus de saveDay : mêmes phrases, même ordre ; colonnes écrites (quatre stades, passages, œufs, départ)', () => {
    for (const t of [M.bande, M.dateInvalide, M.departManquant, M.ancienneFiche, M.ventesNonVentilees]) assert.ok(php.includes(norm(t)), `absent du PHP : « ${t} »`);
    assert.ok(php.includes("Jour antérieur à l\\'effectif de départ fixé le") || php.includes("Jour antérieur à l'effectif de départ fixé le"));
    assert.ok(php.includes(norm(M.mortsAuDessus('{$morts}', '{$this->previousEffectif}'))));
    assert.ok(php.includes("Avertissement — fiche du '.Carbon::parse($this->selectedDate)->format('d/m/Y')") && php.includes('la somme des stades ('));
    const ordrePhp = ["authorize('manage-elevage')", "Aucune bande active au stade Ponte", 'refusExerciceClos', 'Date invalide', "$cat['mode'] === 'avant_depart'", "$cat['mode'] === 'refus'", "$cat['mode'] === 'depart_requis'", "$cat['refus_passage'] !== null", 'non ventilés par stade', "$this->ventesDuJour['non_ventilee']"].map((m) => php.indexOf(norm(m), php.indexOf('public function saveDay')));
    assert.deepEqual([...ordrePhp].sort((a, b) => a - b), ordrePhp, 'ordre des contrôles du PHP');
    const js = lire('resources/js/hors-ligne/fiche-pondeuses.js');
    const fonction = js.slice(js.indexOf('export function enregistrerJourPondeuses'), js.indexOf('// ----------------------------------------------------------------------------------------------------------- formulaire') > 0 ? js.indexOf('// ----------------------------------------------------------------------------------------------------------- formulaire') : js.indexOf('rendreFormulairePondeuses'));
    const ordreJs = ['ctx.role', 'MOTIFS_PONDEUSES.bande', 'ctx.refusExercice', 'MOTIFS_PONDEUSES.dateInvalide', "'avant_depart'", "'refus'", "'depart_requis'", 'refus_passage', 'ancienneFiche', 'ventesNonVentilees'].map((m) => fonction.indexOf(m));
    assert.ok(ordreJs.every((p) => p >= 0), JSON.stringify(ordreJs));
    assert.deepEqual([...ordreJs].sort((a, b) => a - b), ordreJs, 'ordre des contrôles du JavaScript');
    const bloc = php.slice(php.indexOf('LivestockDailyEntry::updateOrCreate('), php.indexOf('if ($departAEcrire)'));
    const colonnes = [...bloc.matchAll(/'(\w+)' =>/g)].map((m) => m[1]).slice(2);
    assert.ok(colonnes.length >= 24, `colonnes lues : ${colonnes.length}`);
    for (const c of colonnes) assert.ok(new RegExp(`\\b${c}\\b`).test(fonction), `colonne « ${c} » de saveDay non écrite par le JavaScript`);
    for (const c of ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_depart_4', 'passage_4_sevre', 'passage_sevre_jeune', 'passage_jeune_repro', 'ponte_casses', 'ponte_total', 'vente_4', 'mort_4', 'don_4']) assert.ok(php.includes(`'${c}' =>`) && fonction.includes(c), c);
    assert.ok(php.includes('recalculerEnCascade($lot->id, $this->selectedDate)'));
    assert.ok(php.includes("if ($dailyEntry->wasRecentlyCreated) { app(RecordEggProductionStockAction::class)->execute($dailyEntry); }"), 'le stock d\'œufs est écrit PAR LE SERVEUR, à la première création de la fiche');
});

test('rationnement et autonomie : StadePondeuse::tableau, filière aviculture', () => {
    assert.ok(php.includes("StadePondeuse::tableau(") && php.includes("FeedRationStandard::where('species_code', 'aviculture')"));
    assert.ok(php.includes("$service->produitProvende('aviculture')"));
    assert.ok(stade.includes("'total_kg' => $total === null ? null : round($total / 1000, 2)"));
    assert.ok(stade.includes("preg_replace('/\\([^)]*\\)/u', ' ', (string) $texte)"));
});
