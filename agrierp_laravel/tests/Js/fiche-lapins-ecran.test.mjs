import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { ECRAN } from '../../resources/js/hors-ligne/fiche-lapins-ecran.js';

/**
 * PWA-3 (fiche lapins, É2) — GARDE DE SOURCES : la vue Blade `fiche-lapins.blade.php` (et ses trois composants) est le MAÎTRE. Ce test la LIT et exige que
 * l'écran de la PWA reprenne mot pour mot ses libellés, ses messages et l'ORDRE de ses colonnes. Un libellé changé d'un côté seulement fait échouer ce test.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const blade = lire('resources/views/livewire/elevage/fiche-lapins.blade.php');
const mois = lire('resources/views/components/mois-de-fiche.blade.php');
const transferts = lire('resources/views/components/transferts-du-jour.blade.php');
const decode = (t) => t.replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
const tout = decode(`${blade} ${mois} ${transferts}`);

test('titre, sous-titre, export, sélecteurs et messages : présents dans le Blade', () => {
    for (const cle of ['titre', 'sousTitre', 'exportPdf', 'aucuneBande', 'saisieTitre', 'bande', 'date', 'mois', 'moisPrecedent', 'moisSuivant', 'transferts', 'transfertsSuite', 'transfertsEcran']) {
        assert.ok(tout.includes(decode(ECRAN[cle])), `« ${ECRAN[cle]} » (${cle}) est absent du Blade`);
    }
});

test('KPI : mêmes libellés, même ordre que les x-kpi-card du Blade', () => {
    const labels = [...blade.matchAll(/<x-kpi-card label="([^"]+)"/g)].map((m) => m[1]);
    assert.deepEqual(ECRAN.kpis, labels);
});

test('tableau mensuel : mêmes groupes (libellé, colspan, rowspan) et mêmes sous-colonnes, dans le même ordre', () => {
    const debut = blade.indexOf('<thead class="bg-surface-zebra border-b');
    const bloc = blade.slice(debut, blade.indexOf('</thead>', debut));
    const lignes = bloc.split('</tr>');
    const ths = (l) => [...l.matchAll(/<th([^>]*)>([^<]*)<\/th>/g)].map((m) => [decode(m[2]), /rowspan="2"/.test(m[1]) ? 'rowspan' : Number(/colspan="(\d+)"/.exec(m[1])?.[1])]);
    assert.deepEqual(ECRAN.groupes, ths(lignes[0]));
    assert.deepEqual(ECRAN.sousColonnes, ths(lignes[1]).map(([l]) => l));
    assert.equal(ECRAN.sousColonnes.length, 10);
});

test('corps du tableau : les cellules suivent l\'ordre des colonnes du Blade', () => {
    const champs = [...blade.slice(blade.indexOf('$entry = $this->monthlyEntries->get($dateStr)')).matchAll(/\$entry\?->(\w+) \?\? '—'/g)].map((m) => m[1]);
    assert.deepEqual(champs, ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'effectif_final', 'poids_general_g']);
    assert.match(blade, /\$this->traitementsDuJour\(\$dateStr, \$entry\)/);
    assert.equal(ECRAN.vide, '—');
});

test('bandeau d\'exercice clos : le texte vient du PHP (ExerciceChoisi) et l\'écran reprend la même phrase', () => {
    const php = lire('app/Support/ExerciceChoisi.php');
    assert.ok(php.includes('Exercice {$exercice->year} clôturé — lecture seule'));
    assert.ok(php.includes("Les saisies se font dans l'exercice {$saisie->year}."));
    const js = lire('resources/js/hors-ligne/fiche-lapins-ecran.js');
    assert.ok(js.includes('clôturé — lecture seule.') && js.includes("Les saisies se font dans l'exercice "));
});
